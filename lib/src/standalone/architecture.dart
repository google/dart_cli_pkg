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

/// An enumeration of all CPU architectures supported by Dart.
enum Architecture {
  arm,
  arm64,
  arm64e,
  ia32,
  x64,
  riscv32,
  riscv64;

  /// Whether this is a 32-bit ARM architecture.
  bool get isArm32 => this == arm;

  /// Whether this is a 64-bit ARM architecture.
  bool get isArm64 => this == arm64;

  /// Whether this is an extended 64-bit ARM architecture.
  bool get isArm64e => this == arm64e;

  /// Whether this is a 32-bit x86 architecture.
  bool get isIA32 => this == ia32;

  /// Whether this is a 64-bit x86 architecture.
  bool get isX64 => this == x64;

  /// Whether this is a 32-bit RISCV architecture.
  bool get isRiscv32 => this == riscv32;

  /// Whether this is a 64-bit RISCV architecture.
  bool get isRiscv64 => this == riscv64;

  /// Parses [name] as an architecture and throws an error if parsing fails.
  factory parse(String name) =>
      tryParse(name) ?? (throw 'Unknown architecture "$name"');

  /// Parses [name] as an architecture and returns `null` if it's not an
  /// architecture that's recognized or supported by `cli_pkg`.
  static Architecture? tryParse(String name) => switch (name) {
    "arm" => .arm,
    "arm64" => .arm64,
    "arm64e" => .arm64e,
    "ia32" => .ia32,
    "x64" => .x64,
    "riscv32" => .riscv32,
    "riscv64" => .riscv64,
    _ => null,
  };

  @override
  String toString() => name;
}
