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

import 'utils.dart';

export 'package:test_descriptor/test_descriptor.dart';

/// The `cli_pkg` package's pubpsec.
final _ourPubpsec = loadYaml(File('pubspec.yaml').readAsStringSync(),
    sourceUrl: 'pubspec.yaml');

/// Returns a directory descriptor for a package in [appDir] with the given
/// pubspec and `grind.dart` file, as well as other optional files.
///
/// This automatically does a couple of useful things:
///
/// * Creates an executable for each executable listed in the pubspec's
///   `executables` field.
///
/// * Adds a dependency on grinder and `cli_pkg`.
///
/// * Imports `package:grinder/grinder.dart` and `package:cli_pkg/cli_pkg.dart`.
DirectoryDescriptor package(Map<String, Object> pubspec, String grindDotDart,
    [List<Descriptor> files]) {
  pubspec = {
    "executables": <String, Object>{},
    ...pubspec,
    "dev_dependencies": {
      ..._ourDependency("grinder"),
      ..._ourDependency("test"),
      "cli_pkg": {"path": p.current},
      ...?(pubspec["dev_dependencies"] as Map<String, Object>),
    },
    "dependency_overrides": {
      ...?_ourDependencyOverride("grinder"),
      ...?_ourDependencyOverride("test"),
    },
  };

  var executables = pubspec.containsKey("executables")
      ? (pubspec["executables"] as Map<String, Object>).values.toSet()
      : const <Object>{};

  return dir(p.basename(appDir), [
    file("pubspec.yaml", json.encode(pubspec)),

    // Use our existing lockfile as a template so that "pub get" is as fast as
    // possible.
    file("pubspec.lock", File("pubspec.lock").readAsStringSync()),

    dir("bin", [
      for (var basename in executables)
        file(
            "$basename.dart",
            // Include the version variable to ensure that executables we invoke
            // have access to it.
            'void main() => print("in $basename '
                '\${const String.fromEnvironment("version")}");')
    ]),

    dir("tool", [
      file("grind.dart", """
        import 'package:cli_pkg/cli_pkg.dart' as pkg;
        import 'package:grinder/grinder.dart';

        $grindDotDart
      """)
    ]),

    ...?files
  ]);
}

/// Returns the dependency description for `package` from `cli_pkg`'s own
/// pubspec, as a map so it can be included in a map literal with `...`.
Map<String, Object> _ourDependency(String package) =>
    {package: _ourPubpsec["dependencies"][package]};

/// Returns the dependency override for `package` from `cli_pkg`'s own pubspec,
/// as a map so it can be included in a map literal with `...?`.
Map<String, Object> _ourDependencyOverride(String package) {
  var overrides = (_ourPubpsec["dependency_overrides"] as YamlMap);
  return overrides != null && overrides.containsKey(package)
      ? {package: overrides[package]}
      : const {};
}
