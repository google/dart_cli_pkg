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
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'src/info.dart';

/// A set of executable targets whose up-to-date status has already been
/// verified.
final _executableUpToDateCache = p.PathSet();

/// Whether this package has any path dependencies.
///
/// When a package has path dependencies, `pub run` updates the modification
/// time on the `pubspec.lock` file after every run, which means
/// [ensureUpToDate] can't reliably use it for freshness checking.
final _hasPathDependency = _dependenciesHasPath(pubspec.dependencies) ||
    _dependenciesHasPath(pubspec.devDependencies) ||
    _dependenciesHasPath(pubspec.dependencyOverrides);

/// Starts a [TestProcess] running [executable], which is the name of the
/// executable as listed in the pubspec (or in `pkg.executables`).
///
/// If [node] is `true`, this will run a NodeJS process using the executable
/// compiled by `pkg-npm-dev`. Otherwise, it will run a Dart VM process using
/// the executable compiled by `pkg-standalone-dev` if one exists and running
/// from source otherwise.
///
/// All other arguments are just like [TestProcess.start] and/or
/// [Process.start].
///
/// This throws a [TestFailure] if it would run a compiled executable that's
/// out-of-date relative to the pubspec or to source files in `lib/` or `bin/`.
///
/// When using this in multiple tests, consider calling [setUpAll] with
/// [ensureExecutableUpToDate] to avoid having many redundant test failures for
/// an out-of-date executable.
Future<TestProcess> start(String executable, Iterable<String> arguments,
        {bool node = false,
        String? workingDirectory,
        Map<String, String>? environment,
        bool includeParentEnvironment = true,
        bool runInShell = false,
        String? description,
        required Encoding encoding,
        bool forwardStdio = false}) async =>
    await TestProcess.start(executableRunner(executable, node: node),
        [...executableArgs(executable, node: node), ...arguments],
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: includeParentEnvironment,
        runInShell: runInShell,
        description: description,
        encoding: encoding,
        forwardStdio: forwardStdio);

/// Returns an executable that can be passed to [Process.start] and similar APIs
/// along with the arguments returned by [executableArgs] to run [executable],
/// which is the name of the executable as listed in the pubspec (or in
/// `pkg.executables`).
///
/// If [node] is `true`, this and [executableArgs] will run a NodeJS process
/// using the executable compiled by `pkg-npm-dev`. Otherwise, they'll run a
/// Dart VM process using the executable compiled by `pkg-standalone-dev` if one
/// exists and running from source otherwise.
///
/// For example:
///
/// ```dart
/// import 'dart:io';
///
/// import 'package:cli_pkg/testing.dart' as pkg;
/// import 'package:test/test.dart';
///
/// void main() {
///   test("hello-world prints a message", () async {
///     var result = await Process.run(
///         pkg.executableRunner("hello-world"),
///         pkg.executableArgs("hello-world"));
///     expect(result.stdout, equals("Hello, world!\n");
///   });
/// }
/// ```
///
/// Note that in practice it's usually easier to use [start].
String executableRunner(String executable, {bool node = false}) =>
    // We take the [executable] argument because it's likely that we'll need to
    // choose between `dart` and `dartaotrunner` once dart-lang/sdk#39973 is
    // fixed.
    node ? "node" : Platform.executable;

/// Arguments that can be passed to [Process.start] and similar APIs along with
/// the executable returned by [executableRunner] to run [executable], which is
/// the basename of an executable in `bin` (without ".dart").
///
/// If [node] is `true`, this and [executableRunner] will run a NodeJS process
/// using the executable compiled by `pkg-npm-dev`. Otherwise, they'll run a
/// Dart VM process using the executable compiled by `pkg-standalone-dev` if one
/// exists and running from source otherwise.
///
/// This throws a [TestFailure] if it would run a compiled executable that's
/// out-of-date relative to the pubspec or to source files in `lib/` or `bin/`.
///
/// For example:
///
/// ```dart
/// import 'dart:io';
///
/// import 'package:cli_pkg/testing.dart' as pkg;
/// import 'package:test/test.dart';
///
/// void main() {
///   test("hello-world prints a message", () async {
///     var result = await Process.run(
///         pkg.executableRunner("hello-world"),
///         pkg.executableArgs("hello-world"));
///     expect(result.stdout, equals("Hello, world!\n");
///   });
/// }
/// ```
///
/// Note that in practice it's usually easier to use [start].
///
/// When using this in multiple tests, consider calling [setUpAll] with
/// [ensureExecutableUpToDate] to avoid having many redundant test failures for
/// an out-of-date executable.
List<String> executableArgs(String executable, {bool node = false}) {
  ensureExecutableUpToDate(executable, node: node);

  if (node) return [p.absolute("build/npm/$executable.js")];

  var snapshot = p.absolute("build/$executable.snapshot");
  if (File(snapshot).existsSync()) return [snapshot];

  return [
    "-Dversion=$version",
    "--enable-asserts",
    p.absolute("bin/$executable.dart")
  ];
}

/// Throws a [TestFailure] if [executable]'s compiled output isn't up-to-date
/// relative to the pubspec or to source files in `lib/` or `bin/`.
///
/// This is automatically run by [start] and [executableArgs]. However, it's
/// presented as a separate function so that users can run it in [setUpAll] to
/// get only a single error per file rather than many.
void ensureExecutableUpToDate(String executable, {bool node = false}) {
  String path;
  if (node) {
    path = p.absolute("build/npm/$executable.js");
  } else {
    path = p.absolute("build/$executable.snapshot");
    if (!File(path).existsSync()) return;
  }

  if (!_executableUpToDateCache.contains(path)) {
    ensureUpToDate(
        path, "pub run grinder pkg-${node ? 'npm' : 'standalone'}-dev",
        dependencies: [executables.value[executable]]);

    // Only add this after ensuring that the executable is up-to-date, so that
    // running it multiple times for out-of-date inputs will cause multiple
    // errors.
    _executableUpToDateCache.add(path);
  }
}

/// Ensures that [path] (usually a compilation artifact) has been modified more
/// recently than all this package's source files.
///
/// By default, this checks files in the `lib/` directory as well as
/// `pubspec.lock`. Additional files or directories to check can be passed in
/// [dependencies].
///
/// If [path] doesn't exist or is out of date, throws a [TestFailure]
/// encouraging the user to run [commandToRun].
void ensureUpToDate(String path, String commandToRun,
    {Iterable<String?>? dependencies}) {
  // Ensure path is relative so the error messages are more readable.
  path = p.relative(path);
  if (!File(path).existsSync()) {
    throw TestFailure("$path does not exist. Run $commandToRun.");
  }

  var entriesToCheck = [
    for (var dependency in [...?dependencies, "lib"])
      if (Directory(dependency!).existsSync())
        ...Directory(dependency).listSync(recursive: true)
      else if (File(dependency).existsSync())
        File(dependency),
    _hasPathDependency ? File("pubspec.yaml") : File("pubspec.lock")
  ];

  var lastModified = File(path).lastModifiedSync();
  for (var entry in entriesToCheck) {
    if (entry is File) {
      var entryLastModified = entry.lastModifiedSync();
      if (lastModified.isBefore(entryLastModified)) {
        throw TestFailure(
            "${entry.path} was modified after ${p.prettyUri(p.toUri(path))} "
            "was generated.\n"
            "Run $commandToRun.");
      }
    }
  }
}

/// Returns whether any of the dependencies in [dependencies] is a path
/// dependency.
bool _dependenciesHasPath(Map<String, Dependency> dependencies) =>
    dependencies.values.any((dependency) => dependency is PathDependency);
