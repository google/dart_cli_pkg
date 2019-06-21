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

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test_descriptor/test_descriptor.dart';
import 'package:yaml/yaml.dart';

export 'package:test_descriptor/test_descriptor.dart';

/// The `cli_pkg` package's pubpsec.
final _ourPubpsec = loadYaml(File('pubspec.yaml').readAsStringSync(),
    sourceUrl: 'pubspec.yaml');

/// The `cli_pkg` package's dependency on grinder.
final _ourGrinderDependency = _ourPubpsec["dependencies"]["grinder"] as String;

/// Returns a directory descriptor for a package with the given pubspec and
/// `grind.dart` file, as well as other optional files.
///
/// This automatically does a couple of useful things:
///
/// * Creates an executable for each executable listed in the pubspec's
///   `executables` field.
///
/// * Adds a dependency on grinder and `cli_pkg`.
///
/// * Imports `package:grinder/grinder.dart` and `package:cli_pkg/cli_pkg.dart`.
DirectoryDescriptor package(
    String name, Map<String, Object> pubspec, String grindDotDart,
    [List<Descriptor> files]) {
  pubspec = {
    "executables": {},
    ...pubspec,
    "dev_dependencies": {
      "grinder": _ourGrinderDependency,
      "cli_pkg": {"path": p.current},
      ...?(pubspec["dev_dependencies"] as Map<String, Object>),
    }
  };

  var executables = pubspec.containsKey("executables")
      ? (pubspec["executables"] as Map<String, Object>).values.toSet()
      : const {};

  return dir(name, [
    file("pubspec.yaml", json.encode(pubspec)),

    // Use our existing lockfile as a template so that "pub get" is as fast as
    // possible.
    file("pubspec.lock", File("pubspec.lock").readAsStringSync()),

    dir("bin", [
      for (var basename in executables)
        file("$basename.dart", 'void main() => print("in $basename");')
    ]),

    dir("tool", [
      file("grind.dart", """
        import 'package:cli_pkg/cli_pkg.dart';
        import 'package:grinder/grinder.dart';

        $grindDotDart
      """)
    ]),

    ...?files
  ]);
}
