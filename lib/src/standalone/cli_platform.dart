// Copyright 2023 Google LLC
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

import 'dart:ffi';
import 'dart:io';

import 'package:grinder/grinder.dart';
import 'package:native_stack_traces/elf.dart';
import 'package:path/path.dart' as p;

import 'architecture.dart';
import 'operating_system.dart';

/// Certain ABIs that Dart recognizes but cli_pkg doesn't support for various
/// reasons.
const _unsupportedAbis = {
  // This is still experimental and Dart isn't shipping SDKs for it yet
  Abi.linuxRiscv32
};

/// The set of all ABI strings known by this SDK.
final _abiStrings = {
  for (var abi in Abi.values)
    if (!_unsupportedAbis.contains(abi) &&
        // There are no Dart SDKs for iOS
        !abi.toString().startsWith("ios_") &&
        // https://github.com/dart-lang/sdk/issues/59698
        !abi.toString().endsWith("_ia32"))
      abi.toString()
};

/// A struct representing a platform for which we can build standalone
/// executables.
class CliPlatform {
  /// The operating system.
  final OperatingSystem os;

  /// The CPU architecture, such as "ia32" or "arm64".
  final Architecture arch;

  /// Whether the executable should be built to use musl LibC instead of glibc.
  ///
  /// This is only ever true if [os] is "linux".
  final bool isMusl;

  /// Whether this is the same platform as the running Dart executable.
  bool get isCurrent => this == current;

  /// Whether to generate a fully standalone executable that doesn't need a
  /// separate `dartaotruntime` executable to run for this platform.
  ///
  /// This is currently disabled on Windows and Mac OS because they generate
  /// annoying warnings when running unsigned executables. See #67 for details.
  ///
  /// This is currently disabled on Linux and Android because the self-contained
  /// executable can be broken due to the way a trailing snapshot in ELF is
  /// handled. See https://github.com/dart-lang/sdk/issues/50926 for details.
  bool get useExe =>
      const {OperatingSystem.fuchsia, OperatingSystem.ios}.contains(os) &&
      useNative;

  /// Returns whether to use the natively-compiled executable for this platform.
  ///
  /// We can only use the native executable on the current operating system
  /// because Dart doesn't currently support cross-compilation
  /// (dart-lang/sdk#28617). Dart also doesn't support native compilation on
  /// ia32 in particular (dart-lang/sdk#47177).
  bool get useNative => isCurrent && !arch.isIA32;

  /// The binary file extension for this platform.
  String get binaryExtension => os.isWindows ? '.exe' : '';

  /// The file extension for archives for this platform.
  String get archiveExtension => os.isWindows ? '.zip' : '.tar.gz';

  /// All platforms that are supported by Dart SDKs.
  static final Set<CliPlatform> all = {
    for (var [os, arch] in _abiStrings.map((abi) => abi.split('_')))
      for (var musl in [false, if (os == 'linux') true])
        CliPlatform(OperatingSystem.parse(os), Architecture.parse(arch),
            musl: musl)
  };

  /// The platform of the current Dart executable.
  ///
  /// This isn't necessarily the platform of the underlying OS, since 32-bit
  /// executables can run on 64-bit operating systems and the choice of LibC is
  /// OS-independent.
  static final CliPlatform current = () {
    var [osName, archName] = Abi.current().toString().split('_');
    var os = OperatingSystem.parse(osName);
    var arch = Architecture.parse(archName);
    return CliPlatform(os, arch, musl: os.isLinux && _isCurrentPlatformMusl);
  }();

  /// Returns whether the current platform is using musl LibC.
  static bool get _isCurrentPlatformMusl {
    var section = Elf.fromFile(Platform.resolvedExecutable)
        ?.namedSections('.interp')
        .firstOrNull;
    if (section == null) return false;

    var file = File(Platform.resolvedExecutable).openSync()
      ..setPositionSync(section.offset);
    var interp = String.fromCharCodes(file.readSync(section.length - 1));
    file.closeSync();
    return p.basename(interp).startsWith('ld-musl-');
  }

  CliPlatform(this.os, this.arch, {bool musl = false}) : isMusl = musl {
    if (!_abiStrings.contains('${os}_$arch')) {
      fail("Unknown or unsupported platform $os-$arch!");
    }

    if (musl && !os.isLinux) fail("musl LibC only supports Linux.");
  }

  int get hashCode => Object.hash(os.hashCode, arch.hashCode, isMusl.hashCode);

  bool operator ==(Object other) =>
      other is CliPlatform &&
      other.os == os &&
      other.arch == arch &&
      other.isMusl == isMusl;

  /// Returns a human-friendly description of this platform.
  String toHumanString() =>
      "${os.toHumanString()} $arch" + (isMusl ? " with musl LibC" : "");

  String toString() => "$os-$arch" + (isMusl ? "-musl" : "");
}
