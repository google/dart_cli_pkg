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

import 'js_require_target.dart';

/// A JavaScript dependency to `require()` at the beginning of the generated JS
/// file.
///
/// This allows each individual dependency to be configured to avoid loading it
/// when it's not necessary.
///
/// Note that if [jsEsmExports] is set, ESM files with `import`s are generated
/// in addition to CJS files with `require()`.
class JSRequire {
  /// The argument to the `require()` function.
  final String package;

  /// The global identifier to assign to the result of `require()`.
  ///
  /// This defaults to a valid JS identifier based on [package].
  final String identifier;

  /// Whether the dependency is loaded lazily.
  ///
  /// A lazy-loaded dependency only executes the `require()` function the first
  /// time the module identifier is referenced, rather than eagerly executing it
  /// when this package is loaded.
  ///
  /// This defaults to false.
  final bool lazy;

  /// Whether the dependency is optional.
  ///
  /// An optional dependency's module identifier will be `null` if a load fails
  /// rather than throwing an error.
  ///
  /// This defaults to false.
  final bool optional;

  /// The target in which to include this require.
  ///
  /// This defaults to [JSRequireTarget.all].
  final JSRequireTarget target;

  JSRequire(this.package,
      {String? identifier,
      JSRequireTarget? target,
      this.lazy = false,
      this.optional = false})
      : identifier = identifier ??
            package
                .replaceFirst(RegExp(r'^@'), '')
                .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_'),
        target = target ?? JSRequireTarget.all;

  String toString() => "const $identifier = require('$package') on $target";
}
