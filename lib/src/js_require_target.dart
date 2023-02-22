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

import 'npm.dart';

/// An enumeration of possible targets in which to include the require.
enum JSRequireTarget {
  /// The require is available for all targets that any other [JSRequire] uses.
  ///
  /// This target is _always_ loaded for the CLI, and if [jsModuleMainLibrary]
  /// is set it's always for the `"default"` [conditional export] in
  /// package.json.
  ///
  /// [conditional export]: https://nodejs.org/api/packages.html#packages_conditional_exports
  all,

  /// The require is available for all command-line executables, but not for the
  /// the standalone library.
  cli,

  /// The require is available only when loaded by Node.js.
  ///
  /// This corresponds to the `"node"` [conditional export] in package.json.
  /// Note that all Node requires are also available for CLI targets.
  ///
  /// [conditional export]: https://nodejs.org/api/packages.html#packages_conditional_exports
  node,

  /// The require is available only when loaded in a browser.
  ///
  /// This corresponds to the `"browser"` [conditional export] in package.json.
  ///
  /// [conditional export]: https://nodejs.org/api/packages.html#community-conditions-definitions
  browser,

  /// The require is available when loaded by the default target.
  ///
  /// This corresponds to the `"default"` [conditional export] in package.json.
  /// These requires will be used by any platform for which no other requires
  /// are specified. For example, Node.js will use these requires if and only if
  /// there are no requires explicitly specified for [node].
  ///
  /// [conditional export]: https://nodejs.org/api/packages.html#packages_conditional_exports
  defaultTarget,
}
