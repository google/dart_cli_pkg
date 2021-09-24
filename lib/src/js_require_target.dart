// Copyright 2021 Google LLC
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

/// An enumeration of possible targets in which to include the require.
class JSRequireTarget {
  /// The require is available for all targets.
  static const all = JSRequireTarget._("all");

  /// The require is available for all command-line executables, but not for the
  /// the standalone library.
  static const cli = JSRequireTarget._("cli");

  /// The require is available only when loaded by Node.js.
  ///
  /// This uses [conditional exports] to only include `require()`s for Node.
  /// Note that all Node requires are also available for CLI targets.
  ///
  /// [conditional exports]: https://nodejs.org/api/packages.html#packages_conditional_exports
  static const node = JSRequireTarget._("node");

  /// The require is available only when loaded in a browser.
  ///
  /// This uses [conditional exports] to only include `require()`s on the
  /// browser.
  ///
  /// [conditional exports]: https://webpack.js.org/guides/package-exports/#target-environment
  static const browser = JSRequireTarget._("browser");

  /// The name of the target, for debugging and const-separation purposes.
  final String _name;

  const JSRequireTarget._(this._name);

  String toString() => _name;
}
