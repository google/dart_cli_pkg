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

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'js_require.dart';

/// The equality used to compare between [JSRequire]s in [JSRequireSet].
final _equality =
    EqualityBy<JSRequire, String>((require) => require.identifier);

/// A set of [JSRequire]s that's guaranteed to have at most one require for each
/// identifier.
@internal
class JSRequireSet extends EqualitySet<JSRequire> {
  /// Creates an empty set.
  JSRequireSet() : super(_equality);

  /// Creates a set containing [requires].
  ///
  /// If a require with the same identifier appears multiple times in
  /// [requires], the first one takes precedence.
  JSRequireSet.of(Iterable<JSRequire> requires)
      : super.from(_equality, requires);

  JSRequireSet union(Set<JSRequire> other) =>
      JSRequireSet.of([...this, ...other]);

  JSRequireSet difference(Set<Object?> other) =>
      JSRequireSet.of(super.difference(other));

  JSRequireSet intersection(Set<Object?> other) =>
      JSRequireSet.of(super.intersection(other));
}
