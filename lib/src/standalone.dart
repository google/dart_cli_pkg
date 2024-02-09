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

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:grinder/grinder.dart';
import 'package:path/path.dart' as p;

import 'config_variable.dart';
import 'info.dart';
import 'sdk_channel.dart';
import 'standalone/cli_platform.dart';
import 'standalone/operating_system.dart';
import 'template.dart';
import 'utils.dart';

/// The name of the standalone package.
///
/// This defaults to [name].
final standaloneName = InternalConfigVariable.fn<String>(() => name.value);

/// For each executable entrypoint in [executables], builds a script snapshot
/// to `build/${executable}.snapshot`.
///
/// If [release] is `false`, this compiles with `--enable-asserts`.
void _compileSnapshot({required bool release}) {
  ensureBuild();
  verifyEnvironmentConstants(forSubprocess: true);

  var existingSnapshots = <String, String>{};
  executables.value.forEach((name, path) {
    if (existingSnapshots.containsKey(path)) {
      var existingName = existingSnapshots[path];
      log('copying build/$existingName.snapshot to build/$name.snapshot');
      File('build/$existingName.snapshot').copySync('build/$name.snapshot');
    } else {
      existingSnapshots[path] = name;
      Dart.run(path, vmArgs: [
        if (!release) '--enable-asserts',
        for (var entry in environmentConstants.value.entries)
          '-D${entry.key}=${entry.value}',
        '--snapshot=build/$name.snapshot'
      ]);
    }
  });
}

/// For each executable entrypoint in [executables], builds a native ("AOT")
/// executable to `build/${executable}.native`.
void _compileNative() {
  ensureBuild();
  verifyEnvironmentConstants(forSubprocess: true, forDartCompileExe: true);

  var existingSnapshots = <String, String>{};
  executables.value.forEach((name, path) {
    if (existingSnapshots.containsKey(path)) {
      var existingName = existingSnapshots[path];
      log('copying build/$existingName.native to build/$name.native');
      File('build/$existingName.native').copySync('build/$name.native');
    } else {
      existingSnapshots[path] = name;
      run('dart', arguments: [
        'compile',
        CliPlatform.current.useExe ? 'exe' : 'aot-snapshot',
        path,
        for (var entry in environmentConstants.value.entries)
          '-D${entry.key}=${entry.value}',
        '--output',
        'build/$name.native'
      ]);
    }
  });
}

/// Whether [addStandaloneTasks] has been called yet.
var _addedStandaloneTasks = false;

/// Enables tasks for building standalone Dart VM packages.
void addStandaloneTasks() {
  if (_addedStandaloneTasks) return;
  _addedStandaloneTasks = true;

  freezeSharedVariables();
  standaloneName.freeze();

  addTask(GrinderTask('pkg-compile-snapshot',
      taskFunction: () => _compileSnapshot(release: true),
      description: 'Build Dart script snapshot(s) in release mode.'));

  addTask(GrinderTask('pkg-compile-snapshot-dev',
      taskFunction: () => _compileSnapshot(release: false),
      description: 'Build Dart script snapshot(s) in dev mode.'));

  addTask(GrinderTask('pkg-compile-native',
      taskFunction: _compileNative,
      description: 'Build Dart native executable(s).'));

  addTask(GrinderTask('pkg-standalone-dev',
      taskFunction: _buildDev,
      description: 'Build standalone executable(s) for testing.',
      // TODO(nweiz): Build a native executable on platforms that support it
      // when dart-lang/sdk#39973 is fixed.
      depends: ['pkg-compile-snapshot-dev']));

  var tasks = {
    for (var platform in CliPlatform.all)
      platform: GrinderTask('pkg-standalone-$platform',
          taskFunction: () => _buildPackage(platform),
          description:
              'Build a standalone package for ${platform.toHumanString()}.',
          depends: platform.useNative
              ? ['pkg-compile-native']
              : ['pkg-compile-snapshot'])
  };
  tasks.values.forEach(addTask);

  addTask(GrinderTask('pkg-standalone-all',
      description: 'Build all standalone packages.',
      depends: [
        for (var MapEntry(key: platform, value: task) in tasks.entries)
          // Omit Fuchsia tasks because we can't run those unless we're actually
          // running on Fuchsia ourselves.
          if (!platform.os.isFuchsia || platform.isCurrent) task.name
      ]));
}

/// Builds scripts for testing each executable on the current OS and
/// architecture.
Future<void> _buildDev() async {
  verifyEnvironmentConstants();

  for (var name in executables.value.keys) {
    var script = "build/$name${Platform.isWindows ? '.bat' : ''}";
    writeString(
        script,
        renderTemplate(
            "standalone/executable-dev.${Platform.isWindows ? 'bat' : 'sh'}", {
          "dart": Platform.resolvedExecutable,
          "environment-constants":
              environmentConstants.value.entries.map((entry) {
            var arg = "-D${entry.key}=${entry.value}";
            return Platform.isWindows ? windowsArgEscape(arg) : shEscape(arg);
          }).join(" "),
          "executable": "$name.snapshot"
        }));

    if (!Platform.isWindows) run("chmod", arguments: ["a+x", script]);
  }
}

/// Builds a package for the given [platform].
Future<void> _buildPackage(CliPlatform platform) async {
  var archive = Archive()
    ..addFile(fileFromString("$standaloneName/src/LICENSE", await license));

  if (!platform.useExe) {
    archive.addFile(fileFromBytes(
        "$standaloneName/src/dart${platform.binaryExtension}",
        await _dartExecutable(platform),
        executable: true));
  }

  for (var name in executables.value.keys) {
    if (platform.useExe) {
      archive.addFile(file("$standaloneName/$name${platform.binaryExtension}",
          "build/$name.native",
          executable: true));
    } else {
      archive.addFile(file("$standaloneName/src/$name.snapshot",
          platform.useNative ? "build/$name.native" : "build/$name.snapshot"));
    }
  }

  if (!platform.useExe) {
    // Do this separately from adding entrypoints because multiple executables
    // may have the same entrypoint.
    for (var name in executables.value.keys) {
      archive.addFile(fileFromString(
          "$standaloneName/$name${platform.os.isWindows ? '.bat' : ''}",
          renderTemplate(
              "standalone/executable${platform.os.isWindows ? '.bat' : '.sh'}",
              {"name": standaloneName.value, "executable": name}),
          executable: true));
    }
  }

  var prefix = 'build/$standaloneName-$version-$platform';
  if (platform.os.isWindows) {
    var output = "$prefix.zip";
    log("Creating $output...");
    File(output).writeAsBytesSync(ZipEncoder().encode(archive)!);
  } else {
    var output = "$prefix.tar.gz";
    log("Creating $output...");
    File(output)
        .writeAsBytesSync(GZipEncoder().encode(TarEncoder().encode(archive))!);
  }
}

/// Returns the binary contents of the `dart` or `dartaotruntime` exectuable for
/// the given [platform].
Future<List<int>> _dartExecutable(CliPlatform platform) async {
  // If we're building for the same SDK we're using, load its executable from
  // disk rather than downloading it fresh.
  if (platform.useNative) {
    return File(p.join(
            sdkDir.path, "bin/dartaotruntime${platform.binaryExtension}"))
        .readAsBytesSync();
  } else if (isTesting) {
    // Don't actually download full SDKs in test mode, just return a dummy
    // executable.
    return utf8.encode("Dart ${platform.toHumanString()}");
  }

  var url = switch (platform) {
    CliPlatform(isMusl: true) => "https://github.com/dart-musl/dart/releases/"
        "download/$dartVersion/"
        "dartsdk-${platform.os}-${platform.arch}-release.tar.gz",
    CliPlatform(os: OperatingSystem.android) => "https://github.com/"
        "dart-android/dart/releases/download/$dartVersion/"
        "dartsdk-${platform.os}-${platform.arch}-release.tar.gz",
    CliPlatform(
      os: var os && (OperatingSystem.fuchsia || OperatingSystem.ios)
    ) =>
      fail(
          "${os.toHumanString()} executables can only be generated when running "
          "on ${os.toHumanString()}, because Dart doesn't distribute SDKs for "
          "that platform."),
    _ => "https://storage.googleapis.com/dart-archive/channels/"
        "${SdkChannel.current}/release/$dartVersion/sdk/dartsdk-${platform.os}-"
        "${platform.arch}-release.zip"
  };
  log("Downloading $url...");
  var response = await client.get(Uri.parse(url));
  if (response.statusCode ~/ 100 != 2) {
    fail("Failed to download package: ${response.statusCode} "
        "${response.reasonPhrase}.");
  }

  var filename = "/bin/dart${platform.binaryExtension}";
  return (url.endsWith(".zip")
          ? ZipDecoder().decodeBytes(response.bodyBytes)
          : TarDecoder()
              .decodeBytes(GZipDecoder().decodeBytes(response.bodyBytes)))
      .firstWhere((file) => file.name.endsWith(filename))
      .content as List<int>;
}
