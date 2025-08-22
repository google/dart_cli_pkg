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

import 'package:grinder/grinder.dart';

/// An enumeration of all CPU architectures supported by Dart.
enum Architecture {
  arm,
  arm64,
  ia32,
  x64,
  riscv32,
  riscv64;

  /// Whether this is a 32-bit ARM architecture.
  bool get isArm32 => this == arm;

  /// Whether this is a 64-bit ARM architecture.
  bool get isArm64 => this == arm64;

  /// Whether this is a 32-bit x86 architecture.
  bool get isIA32 => this == ia32;

  /// Whether this is a 64-bit x86 architecture.
  bool get isX64 => this == x64;

  /// Whether this is a 32-bit RISCV architecture.
  bool get isRiscv32 => this == riscv32;

  /// Whether this is a 64-bit RISCV architecture.
  bool get isRiscv64 => this == riscv64;

  factory Architecture.parse(String name) => switch (name) {
    "arm" => Architecture.arm,
    "arm64" => Architecture.arm64,
    "ia32" => Architecture.ia32,
    "x64" => Architecture.x64,
    "riscv32" => Architecture.riscv32,
    "riscv64" => Architecture.riscv64,
    _ => fail('Unknown architecture "$name"'),
  };

  String toString() => name;
}
