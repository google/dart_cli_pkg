// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:grinder/grinder.dart';
import 'package:http/http.dart' as http;
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'info.dart';

/// The raw YAML of the pubspec.
final rawPubspec =
    loadYaml(File('pubspec.yaml').readAsStringSync(), sourceUrl: Uri(path: 'pubspec.yaml'))
        as Map<Object, Object>/*!*/;

/// The set of entrypoint paths for executables defined by this package.
Set<String> get entrypoints => p.PathSet.of(executables.value.values);

/// The version of the current Dart executable.
final Version dartVersion = Version.parse(Platform.version.split(" ").first);

/// Whether we're using a dev Dart SDK.
bool get isDevSdk => dartVersion.isPreRelease;

/// Returns whether tasks are being run in a test environment.
bool get isTesting => Platform.environment["_CLI_PKG_TESTING"] == "true";

/// The `src/` directory in the `cli_pkg` package.
final Future<String> cliPkgSrc = () async {
  return p.fromUri(
      await Isolate.resolvePackageUri(Uri.parse('package:cli_pkg/src')));
}();

/// A shared client to use across all HTTP requests.
///
/// This will automatically be cleaned up when the process exits.
final client = http.Client();

/// The `.bat` extension on Windows, the empty string everywhere else.
final dotBat = Platform.isWindows ? ".bat" : "";

/// The `.exe` extension on Windows, the empty string everywhere else.
final dotExe = Platform.isWindows ? ".exe" : "";

/// The path to the `dart2native` executable in the Dart SDK.
final dart2NativePath = p.join(sdkDir.path, 'bin/dart2native$dotBat');

/// Whether we should compile native executables using `dart2native` rather than
/// `dart2aot`.
///
/// Dart 2.6 and up uses an executable called "dart2native" to generate both
/// bundled native code executables AND native snapshot "AOT" executables which
/// need to be run with `dartaotruntime`. Earlier SDK versions use a different
/// executable, `dart2aot`, which has a different calling convention and only
/// generates "AOT" snapshots. We support both.
final useDart2Native = File(dart2NativePath).existsSync();

/// The combined license text for the package and all its dependencies.
///
/// We include all dependency licenses because their code may be compiled into
/// binary and JS releases.
Future<String> get license => _licenseMemo.runOnce(() async {
      // A map from license texts to the set of packages that have that same
      // license. This allows us to de-duplicate repeated licenses, such as those
      // from Dart Team packages.
      var licenses = <String, List<String>>{};
      var thisPackageLicense = _readLicense(".");

      if (thisPackageLicense != null) {
        licenses[thisPackageLicense] = [humanName.value];
      }

      licenses.putIfAbsent(_readSdkLicense(), () => []).add("Dart SDK");

      // Parse the package config rather than the pubspec so we include transitive
      // dependencies. This also includes dev dependencies, but it's possible those
      // are compiled into the distribution anyway (especially for stuff like
      // `node_preamble`).
      // TODO: remove as
      var packageConfigUrl = await Isolate.packageConfig;
      var packageConfig = await loadPackageConfigUri(packageConfigUrl);

      // Sort the dependencies alphabetically to guarantee a consistent
      // ordering.
      var dependencies = packageConfig.packages.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      for (var package in dependencies) {
        // Don't double-include this package's license.
        if (package.name == pubspec.name) continue;

        var dependencyLicense = _readLicense(p.fromUri(package.root));
        if (dependencyLicense == null) {
          log("WARNING: $package has no license and may not be legal to "
              "redistribute.");
        } else {
          licenses.putIfAbsent(dependencyLicense, () => []).add(package.name);
        }
      }

      return licenses.entries
          .map((entry) =>
              wordWrap("${toSentence(entry.value)} license:") +
              "\n\n${entry.key}")
          .join("\n\n" + "-" * 80 + "\n\n");
    });
final _licenseMemo = AsyncMemoizer<String>();

/// A regular expression that matches filenames that should be considered
/// licenses.
final _licenseRegExp =
    RegExp(r"^(([a-zA-Z0-9]+[-_])?(LICENSE|COPYING)|UNLICENSE)(\..*)?$");

/// Returns the contents of the `LICENSE` file in [sdkDir].
String _readSdkLicense() {
  final dartLicense = File(p.join(sdkDir.path, 'LICENSE'));

  if (dartLicense.existsSync()) {
    return dartLicense.readAsStringSync();
  } else {
    // Homebrew's Dart SDK installation puts the license in the directory above
    // the SDK, so if it's not in the SDK itself check there.
    return File(p.join(sdkDir.parent.path, 'LICENSE')).readAsStringSync();
  }
}

/// Returns the contents of the `LICENSE` file in [dir], with various possible
/// filenames and extensions, or `null`.
String _readLicense(String dir) {
  if (!Directory(dir).existsSync()) return null;

  var possibilities = Directory(dir)
      .listSync()
      .whereType<File>()
      .map((file) => p.basename(file.path))
      .where(_licenseRegExp.hasMatch)
      .toList();
  if (possibilities.isEmpty) return null;

  // If there are multiple possibilities, choose the shortest one because it's
  // most likely to be canonical.
  return File(p.join(dir, minBy(possibilities, (path) => path.length)))
      .readAsStringSync();
}

/// Ensure that the `build/` directory exists.
void ensureBuild() {
  Directory('build').createSync(recursive: true);
}

/// Creates an [ArchiveFile] with the given [path] and [data].
///
/// If [executable] is `true`, this marks the file as executable.
ArchiveFile fileFromBytes(String path, List<int> data,
        {bool executable = false}) =>
    ArchiveFile(path, data.length, data)
      ..mode = executable ? 495 : 428
      ..lastModTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// Creates a UTF-8-encoded [ArchiveFile] with the given [path] and [contents].
///
/// If [executable] is `true`, this marks the file as executable.
ArchiveFile fileFromString(String path, String contents,
        {bool executable = false}) =>
    fileFromBytes(path, utf8.encode(contents), executable: executable);

/// Creates an [ArchiveFile] at the archive path [target] from the local file at
/// [source].
///
/// If [executable] is `true`, this marks the file as executable.
ArchiveFile file(String target, String source, {bool executable = false}) =>
    fileFromBytes(target, File(source).readAsBytesSync(),
        executable: executable);

/// Parses [url], replacing its hostname with the `_CLI_PKG_TEST_HOST`
/// environment variable if it's set.
Uri url(String url) {
  var parsed = Uri.parse(url);
  var host = Platform.environment["_CLI_PKG_TEST_HOST"];
  if (host == null) return parsed;

  var parsedHost = Uri.parse(host);
  return parsed.replace(
      scheme: parsedHost.scheme,
      // Git doesn't accept Windows `file:` URLs with user info components.
      userInfo: parsedHost.scheme == 'file' ? "" : null,
      host: parsedHost.host,
      port: parsedHost.port,
      path:
          p.url.join(parsedHost.path, p.url.relative(parsed.path, from: "/")));
}

/// Returns the human-friendly name for the given [os] string.
String humanOSName(String os) {
  switch (os) {
    case "linux":
      return "Linux";
    case "macos":
      return "Mac OS";
    case "windows":
      return "Windows";
    default:
      throw ArgumentError("Unknown OS $os.");
  }
}

/// Returns a sentence fragment listing the elements of [iter].
///
/// This converts each element of [iter] to a string and separates them with
/// commas and/or [conjunction] (`"and"` by default) where appropriate.
String toSentence(Iterable<Object> iter, {String conjunction}) {
  if (iter.length == 1) return iter.first.toString();
  conjunction ??= 'and';
  return iter.take(iter.length - 1).join(", ") + " $conjunction ${iter.last}";
}

/// The maximum line length for [wordWrap]
const _lineLength = 80;

/// Wraps [text] so that it fits within [_lineLength] characters.
///
/// This preserves existing newlines and only splits words on spaces, not on
/// other sorts of whitespace.
String wordWrap(String text) {
  return text.split("\n").map((originalLine) {
    var buffer = StringBuffer();
    var lengthSoFar = 0;
    for (var word in originalLine.split(" ")) {
      var wordLength = word.length;
      if (wordLength > _lineLength) {
        if (lengthSoFar != 0) buffer.writeln();
        buffer.writeln(word);
      } else if (lengthSoFar == 0) {
        buffer.write(word);
        lengthSoFar = wordLength;
      } else if (lengthSoFar + 1 + wordLength > _lineLength) {
        buffer.writeln();
        buffer.write(word);
        lengthSoFar = wordLength;
      } else {
        buffer.write(" $word");
        lengthSoFar += 1 + wordLength;
      }
    }
    return buffer.toString();
  }).join("\n");
}

/// Like [File.writeAsStringSync], but logs that the file is being written.
void writeString(String path, String text) {
  log("writing $path");
  File(path).writeAsStringSync(text);
}

/// Like [File.writeAsBytesSync], but logs that the file is being written.
void writeBytes(String path, List<int> contents) {
  log("writing $path");
  File(path).writeAsBytesSync(contents);
}

/// Like Grinder's [copy], but without Windows bugs (google/grinder.dart#345).
void safeCopy(String source, String destination) {
  log("copying $source to $destination");
  Directory(destination).createSync(recursive: true);
  File(source).copySync(p.join(destination, p.basename(source)));
}

/// Options for [run] that tell Git to commit using [botName] and [botemail.
final botEnvironment = RunOptions(environment: {
  "GIT_AUTHOR_NAME": botName.value,
  "GIT_AUTHOR_EMAIL": botEmail.value,
  "GIT_COMMITTER_NAME": botName.value,
  "GIT_COMMITTER_EMAIL": botEmail.value
});

/// Ensure that the repository at [url] is cloned into the build directory and
/// pointing to the latest master revision.
///
/// Returns the path to the repository.
Future<String> cloneOrPull(String url) async {
  var name = p.url.basename(url);
  if (p.url.extension(name) == ".git") name = p.url.withoutExtension(name);

  var path = p.join("build", name);

  if (Directory(p.join(path, '.git')).existsSync()) {
    log("Updating $url");
    await runAsync("git",
        arguments: ["fetch", "origin"], workingDirectory: path);
  } else {
    delete(Directory(path));
    await runAsync("git", arguments: ["clone", url, path]);
    await runAsync("git",
        arguments: ["config", "advice.detachedHead", "false"],
        workingDirectory: path);
  }
  await runAsync("git",
      arguments: ["checkout", "origin/HEAD"], workingDirectory: path);
  log("");

  return path;
}

/// Returns an unmodifiable copy of the JSON-compatible [object] (that is, a
/// structure of lists and arrays of immutable scalar objects).
Object freezeJson(Object object) {
  if (object is Map<String, Object>) return freezeJsonMap(object);
  // TODO: remove as
  if (object is List) return List<Object>.unmodifiable(object.map(freezeJson));
  return object;
}

/// Like [freezeJson], but typed specifically for a map argument.
Map<String, Object> freezeJsonMap(Map<String, Object> map) =>
    UnmodifiableMapView(
        {for (var entry in map.entries) entry.key: freezeJson(entry.value)});
