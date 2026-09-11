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

/// An enumeration of all operating systems supported by Dart.
enum OperatingSystem {
  android,
  fuchsia,
  ios,
  linux,
  macos,
  windows;

  /// Whether this represents Android.
  bool get isAndroid => this == android;

  /// Whether this represents Fuchsia.
  bool get isFuchsia => this == fuchsia;

  /// Whether this represents iOS.
  bool get isIOS => this == ios;

  /// Whether this represents Linux.
  bool get isLinux => this == linux;

  /// Whether this represents Mac OS.
  bool get isMacOS => this == macos;

  /// Whether this represents Windows.
  bool get isWindows => this == windows;

  /// Parses [name] as an architecture and throws an error if parsing fails.
  factory parse(String name) =>
      tryParse(name) ?? (throw 'Unknown operating system "$name"');

  /// Parses [name] as an operating system and returns `null` if it's not an
  /// architecture that's recognized or supported by `cli_pkg`.
  static OperatingSystem? tryParse(String name) => switch (name) {
    "android" => .android,
    "fuchsia" => .fuchsia,
    "ios" => .ios,
    "linux" => .linux,
    "macos" => .macos,
    "windows" => .windows,
    _ => null,
  };

  String toHumanString() => switch (this) {
    .ios => "iOS",
    .macos => "macOS",
    _ => name[0].toUpperCase() + name.substring(1).toLowerCase(),
  };

  @override
  String toString() => name;
}
