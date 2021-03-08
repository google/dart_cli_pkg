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

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:shelf_test_handler/shelf_test_handler.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';

import 'package:cli_pkg/src/utils.dart';

/// The directory in which the main application exists.
String get appDir => d.path("my_app");

/// Runs [grinder] in the application directory with the given [arguments].
///
/// Runs `pub get` first if necessary.
///
/// If [server] is passed, redirectable HTTP requests from the grinder tasks
/// will be made to it instead of to the default host.
///
/// The [environment] and [forwardStdio] arguments have the same meanings as for
/// [TestProcess.start].
Future<TestProcess> grind(List<String> arguments,
    {ShelfTestServer? server,
    Map<String, String>? environment,
    bool forwardStdio = false}) async {
  if (!File(d.path(p.join(appDir, ".packages"))).existsSync()) {
    await pubGet(forwardStdio: forwardStdio);
  }

  return await TestProcess.start("pub$dotBat", ["run", "grinder", ...arguments],
      forwardStdio: forwardStdio,
      workingDirectory: appDir,
      environment: {
        ...?environment,
        "_CLI_PKG_TESTING": "true",
        if (server != null) "_CLI_PKG_TEST_HOST": server.url.toString()
      });
}

/// Runs `pub get` in [appDir].
Future<void> pubGet({bool forwardStdio = false}) async {
  await (await TestProcess.start(
          "pub$dotBat", ["get", "--offline", "--no-precompile"],
          forwardStdio: forwardStdio, workingDirectory: appDir))
      .shouldExit(0);
}

/// Runs Git in the application directory with the given [arguments].
///
/// The Git process is run in [workingDirectory], which should be relative to
/// [d.sandbox]. If it's not passed, [appDir] is used instead.
Future<void> git(List<String> arguments, {String? workingDirectory}) async {
  await (await TestProcess.start("git", arguments,
          workingDirectory: d.path(workingDirectory ?? appDir)))
      .shouldExit(0);
}

/// Extracts the contents of [archive] to [destination], both within `d.sandbox`.
Future<void> extract(String path, String destination) async {
  var bytes = File(d.path(path)).readAsBytesSync();
  var archive = path.endsWith(".zip") || path.endsWith(".nupkg")
      ? ZipDecoder().decodeBytes(bytes)
      : TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));

  for (var file in archive.files) {
    var filePath = p.join(d.path(destination), file.name);
    Directory(p.dirname(filePath)).createSync(recursive: true);
    File(filePath).writeAsBytesSync(file.content as List<int>);

    // Mark the file executable if necessary.
    if (!Platform.isWindows && file.mode & 1 == 1) {
      await (await TestProcess.start("chmod", ["a+x", filePath])).shouldExit(0);
    }
  }
}

/// Returns a matcher that asserts that [matcher] matches the given value after
/// it's been passed through the [transformation] function.
///
/// If [description] is passed
Matcher after<T>(Object? Function(T) transformation, Object matcher) =>
    predicate((value) {
      expect(value, isA<T>());
      expect(transformation(value as T), matcher);
      return true;
    });

/// Like [Future.wait] with `eagerError: true`, but reports errors after the
/// first using [registerException] rather than silently ignoring them.
Future<List<T>> waitAndReportErrors<T>(Iterable<Future<T>> futures) {
  var errored = false;
  return Future.wait(futures.map((future) {
    // Avoid async/await so that we synchronously add error handlers for the
    // futures to keep them from top-leveling.
    return future.catchError((Object error, StackTrace stackTrace) {
      if (!errored) {
        errored = true;
        throw error; // ignore: only_throw_errors
      } else {
        registerException(error, stackTrace);
      }
    });
  }));
}
