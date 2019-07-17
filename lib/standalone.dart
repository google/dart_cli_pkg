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

import 'src/info.dart';
import 'src/template.dart';
import 'src/utils.dart';

import 'package:archive/archive.dart';
import 'package:grinder/grinder.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Whether we're using a 64-bit Dart SDK.
bool get _is64Bit => Platform.version.contains("x64");

/// The name of the standalone package.
///
/// This defaults to [pkgName].
String get pkgStandaloneName => _pkgStandaloneName ?? pkgName;
set pkgStandaloneName(String value) => _pkgStandaloneName = value;
String _pkgStandaloneName;

/// For each executable entrypoint in [pkgExecutables], builds a script snapshot
/// to `build/${executable}.snapshot`.
@Task('Build Dart script snapshot(s).')
void pkgCompileSnapshot() {
  ensureBuild();

  for (var entrypoint in entrypoints) {
    Dart.run(entrypoint,
        vmArgs: ['--snapshot=build/${p.basename(entrypoint)}.snapshot']);
  }
}

/// For each executable entrypoint in [pkgExecutables], builds a native ("AOT")
/// executable to `build/${executable}.native`.
@Task('Build Dart native executable(s).')
void pkgCompileNative() {
  ensureBuild();

  if (!File(p.join(sdkDir.path, 'bin/dart2aot')).existsSync()) {
    fail(
        "Your SDK doesn't have dart2aot. This probably means that you're using "
        "a 32-bit SDK, which doesn't support native compilation.");
  }

  for (var entrypoint in entrypoints) {
    run(p.join(sdkDir.path, 'bin/dart2aot'), arguments: [
      entrypoint,
      '-Dversion=$pkgVersion',
      'build/${p.basename(entrypoint)}.native'
    ]);
  }
}

/// Builds a standalone 32-bit package for Linux to
/// `build/$pkgStandaloneName-$pkgVersion-linux-ia32.tar.gz`.
///
/// If [client] is passed, it's used to download the corresponding Dart SDK
/// version.
@Depends(pkgCompileSnapshot)
@Task('Build a standalone 32-bit package for Linux.')
Future<void> pkgStandaloneLinuxIa32({http.Client client}) =>
    _buildPackage("linux", x64: false, client: client);

/// Builds a standalone 64-bit package for Linux to
/// `build/$pkgStandaloneName-$pkgVersion-linux-x64.tar.gz`.
///
/// If [client] is passed, it's used to download the corresponding Dart SDK
/// version.
@Task('Build a standalone 64-bit package for Linux.')
Future<void> pkgStandaloneLinuxX64({http.Client client}) async {
  _compile("linux", x64: true);
  await _buildPackage("linux", x64: true, client: client);
}

/// Builds a standalone 32-bit package for MacOs to
/// `build/$pkgStandaloneName-$pkgVersion-macos-ia32.tar.gz`.
///
/// If [client] is passed, it's used to download the corresponding Dart SDK
/// version.
@Depends(pkgCompileSnapshot)
@Task('Build a standalone 32-bit package for Mac OS.')
Future<void> pkgStandaloneMacOsIa32({http.Client client}) =>
    _buildPackage("macos", x64: false, client: client);

/// Builds a standalone 64-bit package for MacOs to
/// `build/$pkgStandaloneName-$pkgVersion-macos-x64.tar.gz`.
///
/// If [client] is passed, it's used to download the corresponding Dart SDK
/// version.
@Task('Build a standalone 64-bit package for Mac OS.')
Future<void> pkgStandaloneMacOsX64({http.Client client}) async {
  _compile("macos", x64: true);
  await _buildPackage("macos", x64: true, client: client);
}

/// Builds a standalone 32-bit package for Windows to
/// `build/$pkgStandaloneName-$pkgVersion-windows-ia32.zip`.
///
/// If [client] is passed, it's used to download the corresponding Dart SDK
/// version.
@Depends(pkgCompileSnapshot)
@Task('Build a standalone 32-bit package for Windows.')
Future<void> pkgStandaloneWindowsIa32({http.Client client}) =>
    _buildPackage("windows", x64: false, client: client);

/// Builds a standalone 64-bit package for Windows to
/// `build/$pkgStandaloneName-$pkgVersion-windows-x64.zip`.
///
/// If [client] is passed, it's used to download the corresponding Dart SDK
/// version.
@Task('Build a standalone 64-bit package for Windows.')
Future<void> pkgStandaloneWindowsX64({http.Client client}) async {
  _compile("windows", x64: true);
  await _buildPackage("windows", x64: true, client: client);
}

/// Builds standalone 32- and 64-bit packages for all operating systems.
///
/// If [client] is passed, it's used to download the corresponding Dart SDK
/// versions.
@Task('Build all standalone packages.')
@Depends(pkgCompileSnapshot, pkgCompileNative)
Future<void> pkgStandaloneAll({http.Client client}) {
  return withClient(client, (client) {
    return Future.wait([
      _buildPackage("linux", x64: false, client: client),
      _buildPackage("linux", x64: true, client: client),
      _buildPackage("macos", x64: false, client: client),
      _buildPackage("macos", x64: true, client: client),
      _buildPackage("windows", x64: false, client: client),
      _buildPackage("windows", x64: true, client: client),
    ]);
  });
}

/// Compiles a native executable if it's supported for the OS/architecture
/// combination, and compiles a script snapshot otherwise.
void _compile(String os, {@required bool x64}) {
  if (_useNative(os, x64: x64)) {
    pkgCompileNative();
  } else {
    pkgCompileSnapshot();
  }
}

/// Returns whether to use the natively-compiled executable for the given [os]
/// and architecture combination.
///
/// We can only use the native executable on the current operating system *and*
/// on 64-bit machines, because currently Dart doesn't support cross-compilation
/// (dart-lang/sdk#28617) and only 64-bit Dart SDKs ship with `dart2aot`.
bool _useNative(String os, {@required bool x64}) =>
    os == Platform.operatingSystem && x64 == _is64Bit;

/// Builds a Sass package for the given [os] and architecture.
///
/// If [client] is passed, it's used to download the corresponding Dart SDK
/// version.
Future<void> _buildPackage(String os,
    {@required bool x64, http.Client client}) async {
  var archive = Archive()
    ..addFile(fileFromBytes(
        "$pkgStandaloneName/src/dart${os == 'windows' ? '.exe' : ''}",
        await _dartExecutable(os, x64: x64, client: client),
        executable: true))
    ..addFile(file(
        "$pkgStandaloneName/src/DART_LICENSE", p.join(sdkDir.path, 'LICENSE')));

  if (File("LICENSE").existsSync()) {
    archive.addFile(file("$pkgStandaloneName/src/LICENSE", "LICENSE"));
  }

  for (var entrypoint in entrypoints) {
    var basename = p.basename(entrypoint);
    archive.addFile(file(
        "$pkgStandaloneName/src/$basename.snapshot",
        _useNative(os, x64: x64)
            ? "build/$basename.native"
            : "build/$basename.snapshot"));
  }

  // Do this separately from adding entrypoints because multiple executables may
  // have the same entrypoint.
  pkgExecutables.forEach((name, path) {
    archive.addFile(fileFromString(
        "$pkgStandaloneName/$name${os == 'windows' ? '.bat' : ''}",
        renderTemplate(
            "standalone/executable.${os == 'windows' ? 'bat' : 'sh'}", {
          "name": pkgStandaloneName,
          "version": _useNative(os, x64: x64) ? null : pkgVersion.toString(),
          "executable": p.basename(path)
        }),
        executable: true));
  });

  var prefix = 'build/$pkgStandaloneName-$pkgVersion-$os-${_arch(x64)}';
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
///
/// If [client] is passed, it's used to download the corresponding Dart SDK
/// version.
Future<List<int>> _dartExecutable(String os,
    {@required bool x64, http.Client client}) async {
  // If we're building for the same SDK we're using, load its executable from
  // disk rather than downloading it fresh.
  if (_useNative(os, x64: x64)) {
    return File(p.join(
            sdkDir.path, "bin/dartaotruntime${os == 'windows' ? '.exe' : ''}"))
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
  var response = client == null
      ? await http.get(Uri.parse(url))
      : await client.get(Uri.parse(url));
  if (response.statusCode ~/ 100 != 2) {
    fail("Failed to download package: ${response.statusCode} "
        "${response.reasonPhrase}.");
  }

  var filename = "/bin/dart${os == 'windows' ? '.exe' : ''}";
  return ZipDecoder()
      .decodeBytes(response.bodyBytes)
      .firstWhere((file) => file.name.endsWith(filename))
      .content as List<int>;
}

/// Returns the architecture name for the given boolean.
String _arch(bool x64) => x64 ? "x64" : "ia32";
