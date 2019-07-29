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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:grinder/grinder.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'info.dart';
import 'template.dart';
import 'utils.dart';

/// Whether we're using a 64-bit Dart SDK.
bool get _is64Bit => Platform.version.contains("x64");

/// The name of the standalone package.
///
/// This defaults to [name].
String get standaloneName => _standaloneName ?? name;
set standaloneName(String value) => _standaloneName = value;
String _standaloneName;

/// For each executable entrypoint in [executables], builds a script snapshot
/// to `build/${executable}.snapshot`.
void _compileSnapshot() {
  ensureBuild();

  for (var entrypoint in entrypoints) {
    Dart.run(entrypoint,
        vmArgs: ['--snapshot=build/${p.basename(entrypoint)}.snapshot']);
  }
}

/// For each executable entrypoint in [executables], builds a native ("AOT")
/// executable to `build/${executable}.native`.
void _compileNative() {
  ensureBuild();

  if (!File(p.join(sdkDir.path, 'bin/dart2aot')).existsSync()) {
    fail(
        "Your SDK doesn't have dart2aot. This probably means that you're using "
        "a 32-bit SDK, which doesn't support native compilation.");
  }

  for (var entrypoint in entrypoints) {
    run(p.join(sdkDir.path, 'bin/dart2aot'), arguments: [
      entrypoint,
      '-Dversion=$version',
      'build/${p.basename(entrypoint)}.native'
    ]);
  }
}

/// Whehter [addStandaloneTasks] has been called yet.
var _addedStandaloneTasks = false;

/// Enables tasks for building standalone Dart VM packages.
void addStandaloneTasks() {
  if (_addedStandaloneTasks) return;
  _addedStandaloneTasks = true;

  addTask(GrinderTask('pkg-compile-snapshot',
      taskFunction: _compileSnapshot,
      description: 'Build Dart script snapshot(s).'));

  addTask(GrinderTask('pkg-compile-native',
      taskFunction: _compileNative,
      description: 'Build Dart native executable(s).'));

  for (var os in ["linux", "macos", "windows"]) {
    addTask(GrinderTask('pkg-standalone-$os-ia32',
        taskFunction: () => _buildPackage(os, x64: false),
        description:
            'Build a standalone 32-bit package for ${humanOSName(os)}.',
        depends: ['pkg-compile-snapshot']));

    addTask(GrinderTask('pkg-standalone-$os-x64',
        taskFunction: () => _buildPackage(os, x64: true),
        description:
            'Build a standalone 64-bit package for ${humanOSName(os)}.',
        depends: _useNative(os, x64: true)
            ? ['pkg-compile-native']
            : ['pkg-compile-snapshot']));
  }

  addTask(GrinderTask('pkg-standalone-all',
      description: 'Build all standalone packages.',
      depends: [
        for (var os in ["linux", "macos", "windows"])
          for (var arch in ["ia32", "x64"]) "pkg-standalone-$os-$arch"
      ]));
}

/// Returns whether to use the natively-compiled executable for the given [os]
/// and architecture combination.
///
/// We can only use the native executable on the current operating system *and*
/// on 64-bit machines, because currently Dart doesn't support cross-compilation
/// (dart-lang/sdk#28617) and only 64-bit Dart SDKs ship with `dart2aot`.
bool _useNative(String os, {@required bool x64}) =>
    os == Platform.operatingSystem && x64 == _is64Bit;

/// Builds a package for the given [os] and architecture.
Future<void> _buildPackage(String os, {@required bool x64}) async {
  var archive = Archive()
    ..addFile(fileFromBytes(
        "$standaloneName/src/dart${_binaryExtension(os)}",
        await _dartExecutable(os, x64: x64),
        executable: true))
    ..addFile(file(
        "$standaloneName/src/DART_LICENSE", p.join(sdkDir.path, 'LICENSE')));

  if (File("LICENSE").existsSync()) {
    archive.addFile(file("$standaloneName/src/LICENSE", "LICENSE"));
  }

  for (var entrypoint in entrypoints) {
    var basename = p.basename(entrypoint);
    archive.addFile(file(
        "$standaloneName/src/$basename.snapshot",
        _useNative(os, x64: x64)
            ? "build/$basename.native"
            : "build/$basename.snapshot"));
  }

  // Do this separately from adding entrypoints because multiple executables may
  // have the same entrypoint.
  executables.forEach((name, path) {
    archive.addFile(fileFromString(
        "$standaloneName/$name${os == 'windows' ? '.bat' : ''}",
        renderTemplate(
            "standalone/executable.${os == 'windows' ? 'bat' : 'sh'}", {
          "name": standaloneName,
          "version": _useNative(os, x64: x64) ? null : version.toString(),
          "executable": p.basename(path)
        }),
        executable: true));
  });

  var prefix = 'build/$standaloneName-$version-$os-${_arch(x64)}';
  if (os == 'windows') {
    var output = "$prefix.zip";
    log("Creating $output...");
    File(output).writeAsBytesSync(ZipEncoder().encode(archive));
  } else {
    var output = "$prefix.tar.gz";
    log("Creating $output...");
    File(output)
        .writeAsBytesSync(GZipEncoder().encode(TarEncoder().encode(archive)));
  }
}

/// Returns the binary contents of the `dart` or `dartaotruntime` exectuable for
/// the given [os] and architecture.
Future<List<int>> _dartExecutable(String os, {@required bool x64}) async {
  // If we're building for the same SDK we're using, load its executable from
  // disk rather than downloading it fresh.
  if (_useNative(os, x64: x64)) {
    return File(p.join(
            sdkDir.path, "bin/dartaotruntime${_binaryExtension(os)}"))
        .readAsBytesSync();
  } else if (isTesting) {
    // Don't actually download full SDKs in test mode, just return a dummy
    // executable.
    return utf8.encode("Dart $os ${_arch(x64)}");
  }

  // TODO(nweiz): Compile a single executable that embeds the Dart VM and the
  // snapshot when dart-lang/sdk#27596 is fixed.
  var channel = isDevSdk ? "dev" : "stable";
  var url = "https://storage.googleapis.com/dart-archive/channels/$channel/"
      "release/$dartVersion/sdk/dartsdk-$os-${_arch(x64)}-release.zip";
  log("Downloading $url...");
  var response = await client.get(Uri.parse(url));
  if (response.statusCode ~/ 100 != 2) {
    fail("Failed to download package: ${response.statusCode} "
        "${response.reasonPhrase}.");
  }

  var filename = "/bin/dart${_binaryExtension(os)}";
  return ZipDecoder()
      .decodeBytes(response.bodyBytes)
      .firstWhere((file) => file.name.endsWith(filename))
      .content as List<int>;
}

/// Returns the architecture name for the given boolean.
String _arch(bool x64) => x64 ? "x64" : "ia32";

/// Returns the binary extension for the given [os].
String _binaryExtension(String os) => os == 'windows' ? '.exe' : '';
