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

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:yaml/yaml.dart';

/// The parsed pubspec for the CLI package.
final _pubspec = Pubspec.parse(File('pubspec.yaml').readAsStringSync(),
    sourceUrl: 'pubspec.yaml');

/// The raw YAML of the pubspec.
final _rawPubspec = loadYaml(File('pubspec.yaml').readAsStringSync(),
    sourceUrl: 'pubspec.yaml');

//? The name of the package, as specified in the pubspec.
final pkgDartName = _pubspec.name;

/// The package's version, as specified in the pubspec.
final pkgVersion = _pubspec.version;

/// The default name of the package on package managers other than pub.
///
/// Pub requires that a package name be a valid Dart identifier, but other
/// package managers do not and users may wish to choose a different name for
/// them. This defaults to [pkgDartName].
String get pkgName => _pkgName ?? pkgDartName;
set pkgName(String value) => _pkgName = value;
String _pkgName;

/// A mutable map from executable names to those executables' paths in `bin/`.
///
/// This defaults to a map derived from the pubspec's `executables` field. It
/// may be modified, but the values must be paths to executable files in the
/// package.
Map<String, String> pkgExecutables = () {
  var executables = _rawPubspec['executables'] as Map;

  return {
    for (var entry in (executables ?? {}).entries)
      entry.key as String: p.join('bin', '${entry.value}.dart')
  };
}();
