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

import 'package:grinder/grinder.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec_parse/pubspec_parse.dart';

import 'config_variable.dart';
import 'utils.dart';

/// The parsed pubspec for the CLI package.
final pubspec = Pubspec.parse(File('pubspec.yaml').readAsStringSync(),
    sourceUrl: Uri(path: 'pubspec.yaml'));

/// The name of the package, as specified in the pubspec.
final dartName = pubspec.name;

/// The package's version, as specified in the pubspec.
final Version version = () {
  var version = pubspec.version;
  if (version != null) return version;

  fail("The pubspec must declare a version number.");
}();

/// The default name of the package on package managers other than pub.
///
/// Pub requires that a package name be a valid Dart identifier, but other
/// package managers do not and users may wish to choose a different name for
/// them. This defaults to [dartName].
final name = InternalConfigVariable.fn<String>(() => dartName);

/// The human-friendly name of the package.
///
/// This is used in places where the package name is only meant to be read by
/// humans, not used as a filename or identifier. It defaults to [name].
final humanName = InternalConfigVariable.fn<String>(() => name.value);

/// The human-friendly name to use for non-authentication-related recordings by
/// this automation tool, such as Git commit metadata.
///
/// Defaults to `"cli_pkg"`.
final botName = InternalConfigVariable.fn<String>(() => "cli_pkg");

/// The email address to use for non-authentication-related recordings, such as
/// Git commit metadata.
///
/// Defaults to `"cli_pkg@none"`.
final botEmail = InternalConfigVariable.fn<String>(() => "cli_pkg@none");

/// A mutable map from executable names to those executables' paths in `bin/`.
///
/// This defaults to a map derived from the pubspec's `executables` field. It
/// may be modified, but the values must be paths to executable files in the
/// package.
final executables = InternalConfigVariable.fn<Map<String, String>>(() {
  var executables = rawPubspec['executables'] as Map<dynamic, dynamic>?;

  return {
    for (var entry in (executables ?? {}).entries)
      entry.key as String: p.join('bin', '${entry.value}.dart')
  };
}, freeze: (map) => Map.unmodifiable(map));

/// A mutable map of environment constants to pass to Dart (using
/// `-D${name}=${value}`) when compiling executables for this package.
///
/// These values can be accessed using [String.fromEnvironment],
/// [int.fromEnvironment], and [bool.fromEnvironment].
///
/// This is also passed when spawning executables via the
/// `package:cli_pkg/testing.dart`. However, if the executable is run from
/// source (as opposed to from a compiled artifact) it won't use the value of
/// [environmentConstants] that's set in `tool/grind.dart`. It also needs to be
/// set in the test itself.
///
/// By default, this contains the following entries:
///
/// * "version": The value of [version].
///
/// * "dart-version": The version of the Dart SDK on which this application is
///   running.
///
/// **Warning:** There are several Dart SDK bugs that restrict which values can
/// be used in environment constants. If any values include these characters,
/// `cli_pkg` will throw an error in the situations where those characters
/// bugged:
///
/// * Due to [#44995], it's not safe to include commas in environment constant
///   values that are passed to `dart compile exe`.
///
/// * Due to [dart-lang/sdk#46067], it's not safe to include `<`, `>`, `^`, `&`,
///   `|`, or `%` in environment constant variables that are passed by Dart to
///   subprocessses on Windows.
///
/// * Due to [dart-lang/sdk#46079], it's not safe to include double quotes in
///   environment constant values on Windows.
///
/// [dart-lang/sdk#46050]: https://github.com/dart-lang/sdk/issues/46050
/// [#44995]: https://github.com/dart-lang/sdk/issues/44995
/// [dart-lang/sdk#46067]: https://github.com/dart-lang/sdk/issues/46067
/// [dart-lang/sdk#46079]: https://github.com/dart-lang/sdk/issues/46079
final environmentConstants = InternalConfigVariable.fn<Map<String, String>>(
    () =>
        {"version": version.toString(), "dart-version": dartVersion.toString()},
    freeze: (map) => Map.unmodifiable(map));

/// Freezes all the [ConfigVariable]s defined in `info.dart`.
void freezeSharedVariables() {
  name.freeze();
  humanName.freeze();
  botName.freeze();
  executables.freeze();
  environmentConstants.freeze();
}
