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
import 'package:path/path.dart' as p;

import 'config_variable.dart';
import 'info.dart';
import 'template.dart';
import 'utils.dart';

/// The architecture of the current operating system.
final _architecture = () {
  if (Platform.version.contains("x64")) return "x64";
  if (Platform.version.contains("arm64")) return "arm64";
  return "ia32";
}();

/// Whether to generate a fully standalone executable that doesn't need a
/// separate `dartaotruntime` executable to run.
///
/// Note that even if this is `true`, fully standalone executables can only be
/// generated for the current operating system in 64-bit mode, so [_useNative]
/// should be checked as well.
///
/// This is currently only enabled on Linux because Windows and OS X generate
/// annoying warnings when running unsigned executables. See #67 for details.
final _useExe = Platform.operatingSystem == "linux";

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
        _useExe ? 'exe' : 'aot-snapshot',
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

  for (var os in ["linux", "macos", "windows"]) {
    if (os != "macos") {
      // Dart as of 2.7 doesn't support 32-bit Mac OS executables.
      addTask(GrinderTask('pkg-standalone-$os-ia32',
          taskFunction: () => _buildPackage(os, 'ia32'),
          description:
              'Build a standalone 32-bit package for ${humanOSName(os)}.',
          depends: ['pkg-compile-snapshot']));
    }

    addTask(GrinderTask('pkg-standalone-$os-x64',
        taskFunction: () => _buildPackage(os, 'x64'),
        description:
            'Build a standalone 64-bit package for ${humanOSName(os)}.',
        depends: _useNative(os, 'x64')
            ? ['pkg-compile-native']
            : ['pkg-compile-snapshot']));

    if (os != "windows") {
      // Dart as of 2.14 only supports ARM on Mac and Linux.
      addTask(GrinderTask('pkg-standalone-$os-arm64',
          taskFunction: () => _buildPackage(os, 'arm64'),
          description:
              'Build a standalone 64-bit package for ${humanOSName(os)}.',
          depends: _useNative(os, 'arm64')
              ? ['pkg-compile-native']
              : ['pkg-compile-snapshot']));
    }
  }

  addTask(GrinderTask('pkg-standalone-all',
      description: 'Build all standalone packages.',
      depends: [
        for (var os in ["linux", "macos", "windows"])
          for (var arch in ["ia32", "x64", "arm64"])
            if (!(os == "macos" && arch == "ia32") &&
                !(os == "windows" && arch == "arm64"))
              "pkg-standalone-$os-$arch"
      ]));
}

/// Returns whether to use the natively-compiled executable for the given [os]
/// and [arch] combination.
///
/// We can only use the native executable on the current operating system *and*
/// on 64-bit machines, because currently Dart doesn't support cross-compilation
/// (dart-lang/sdk#28617) and only 64-bit Dart SDKs support `dart compile exe`
/// (dart-lang/sdk#47177).
bool _useNative(String os, String arch) {
  _verifyOsAndArch(os, arch);
  if (os != Platform.operatingSystem) return false;
  if (arch != _architecture) return false;
  if (arch == "ia32") return false;

  return true;
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

/// Builds a package for the given [os] and architecture.
Future<void> _buildPackage(String os, String arch) async {
  _verifyOsAndArch(os, arch);
  var archive = Archive()
    ..addFile(fileFromString("$standaloneName/src/LICENSE", await license));

  var useNative = _useNative(os, arch);
  var useExe = useNative && _useExe;
  if (!useExe) {
    archive.addFile(fileFromBytes(
        "$standaloneName/src/dart${_binaryExtension(os)}",
        await _dartExecutable(os, arch),
        executable: true));
  }

  for (var name in executables.value.keys) {
    if (useExe) {
      archive.addFile(file(
          "$standaloneName/$name${os == 'windows' ? '.exe' : ''}",
          "build/$name.native",
          executable: true));
    } else {
      archive.addFile(file("$standaloneName/src/$name.snapshot",
          useNative ? "build/$name.native" : "build/$name.snapshot"));
    }
  }

  if (!useExe) {
    // Do this separately from adding entrypoints because multiple executables
    // may have the same entrypoint.
    for (var name in executables.value.keys) {
      archive.addFile(fileFromString(
          "$standaloneName/$name${os == 'windows' ? '.bat' : ''}",
          renderTemplate(
              "standalone/executable.${os == 'windows' ? 'bat' : 'sh'}",
              {"name": standaloneName.value, "executable": name}),
          executable: true));
    }
  }

  var prefix = 'build/$standaloneName-$version-$os-$arch';
  if (os == 'windows') {
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
/// the given [os] and architecture.
Future<List<int>> _dartExecutable(String os, String arch) async {
  _verifyOsAndArch(os, arch);

  // If we're building for the same SDK we're using, load its executable from
  // disk rather than downloading it fresh.
  if (_useNative(os, arch)) {
    return File(
            p.join(sdkDir.path, "bin/dartaotruntime${_binaryExtension(os)}"))
        .readAsBytesSync();
  } else if (isTesting) {
    // Don't actually download full SDKs in test mode, just return a dummy
    // executable.
    return utf8.encode("Dart $os $arch");
  }

  var channel = isDevSdk ? "dev" : "stable";
  var url = "https://storage.googleapis.com/dart-archive/channels/$channel/"
      "release/$dartVersion/sdk/dartsdk-$os-$arch-release.zip";
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

/// Throws an error if [os] and [arch] aren't a valid combination.
///
/// This is just intended to guard against programmer error within `cli_pkg`.
void _verifyOsAndArch(String os, String arch) {
  if (!["macos", "windows", "linux"].contains(os)) {
    fail("Unknown operating system $os!");
  } else if (!["ia32", "x64", "arm64"].contains(arch)) {
    fail("Unknown architecture $arch!");
  } else if (os == "macos" && arch == "ia32") {
    fail("Dart doesn't support 32-bit Mac OS!");
  } else if (os == "windows" && arch == "arm64") {
    fail("Dart doesn't support Windows on ARM!");
  }
}

/// Returns the binary extension for the given [os].
String _binaryExtension(String os) => os == 'windows' ? '.exe' : '';
