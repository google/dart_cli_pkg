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

import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'package:cli_pkg/src/utils.dart';

import 'descriptor.dart' as d;
import 'utils.dart';

void main() {
  var pubspec = {
    "name": "my_app",
    "version": "1.2.3",
    "executables": {"foo": "foo"}
  };

  setUp(() async {
    await d.package(pubspec, """
      void main(List<String> args) {
        pkg.addNpmTasks();
        pkg.addStandaloneTasks();
        grind(args);
      }
    """, [
      d.file("package.json", json.encode({"name": "my_app"}))
    ]).create();
  });

  group("start()", () {
    group("in standalone source mode", () {
      test("runs an executable", () async {
        await pubGet();

        await _testCase("""
          var process = await pkg.start("foo", [], encoding: utf8);
          expect(process.stdout, emits("in foo 1.2.3"));
          await process.shouldExit(0);
        """).create();

        await (await _test()).shouldExit(0);
      });

      test("runs an executable with a different filename", () async {
        await d.package({
          ...pubspec,
          "executables": {"bar": "foo"}
        }, """
          void main(List<String> args) {
            pkg.addNpmTasks();
            pkg.addStandaloneTasks();
            grind(args);
          }
        """).create();

        await pubGet();

        await _testCase("""
          var process = await pkg.start("bar", [], encoding: utf8);
          expect(process.stdout, emits("in foo 1.2.3"));
          await process.shouldExit(0);
        """).create();

        await (await _test()).shouldExit(0);
      });

      test("runs with asserts enabled", () async {
        await d
            .file("my_app/bin/foo.dart", "void main() { assert(false); }")
            .create();
        await pubGet();

        await _testCase("""
          var process = await pkg.start("foo", [], encoding: utf8);
          expect(process.stderr, emitsThrough(contains("Failed assertion")));
          await process.shouldExit(255);
        """).create();

        await (await _test()).shouldExit(0);
      });
    });

    group("in standalone compiled mode", () {
      test("runs an executable", () async {
        await (await grind(["pkg-standalone-dev"])).shouldExit(0);

        await _testCase("""
          var process = await pkg.start("foo", [], encoding: utf8);
          expect(process.stdout, emits("in foo 1.2.3"));
          await process.shouldExit(0);
        """).create();

        await (await _test()).shouldExit(0);
      });

      test("refuses to run if a modification was made to the executable",
          () async {
        await (await grind(["pkg-standalone-dev"])).shouldExit(0);
        await _touch("my_app/bin/foo.dart");

        await _testCase("""
          expect(pkg.start('foo', [], encoding: utf8),
            throwsA(isA<TestFailure>()));
        """).create();
        await (await _test()).shouldExit(0);
      });
    });

    group("in Node.js mode", () {
      test("runs an executable", () async {
        await (await grind(["pkg-npm-dev"])).shouldExit(0);

        await _testCase("""
          var process = await pkg.start("foo", [], node: true, encoding: utf8);
          expect(process.stdout, emits("in foo 1.2.3"));
          await process.shouldExit(0);
        """).create();

        await (await _test()).shouldExit(0);
      });

      test("refuses to run if a modification was made to the executable",
          () async {
        await (await grind(["pkg-npm-dev"])).shouldExit(0);
        await _touch("my_app/bin/foo.dart");

        await _testCase("""
          expect(pkg.start('foo', [], node: true, encoding: utf8),
            throwsA(isA<TestFailure>()));
        """).create();
        await (await _test()).shouldExit(0);
      });
    });
  });

  group("ensureUpToDate()", () {
    setUp(() async {
      await pubGet();
      await d.file("my_app/to-check").create();
    });

    group("fails if a modification was made to", () {
      test("the lib directory", () async {
        await Future<void>.delayed(Duration(seconds: 1));
        await d.dir("my_app/lib", [d.file("something.dart")]).create();

        await _testCase("""
          expect(() => pkg.ensureUpToDate('to-check', ''),
              throwsA(isA<TestFailure>()));
        """).create();
        await (await _test()).shouldExit(0);
      });

      test("the pubspec", () async {
        await _touch("my_app/pubspec.yaml");

        await _testCase("""
          expect(() => pkg.ensureUpToDate('to-check', ''),
              throwsA(isA<TestFailure>()));
        """).create();
        await (await _test()).shouldExit(0);
      });

      test("a file listed in dependencies", () async {
        await _touch("my_app/bin/foo.dart");

        await _testCase("""
          expect(() => pkg.ensureUpToDate(
                  'to-check', '', dependencies: ['bin/foo.dart']),
              throwsA(isA<TestFailure>()));
        """).create();
        await (await _test()).shouldExit(0);
      });

      test("a directory listed in dependencies", () async {
        await _touch("my_app/bin/foo.dart");

        await _testCase("""
          expect(() => pkg.ensureUpToDate(
                  'to-check', '', dependencies: ['bin']),
              throwsA(isA<TestFailure>()));
        """).create();
        await (await _test()).shouldExit(0);
      });
    });

    group("succeeds if", () {
      test("no changes were made", () async {
        await _testCase("pkg.ensureUpToDate('to-check', '');").create();
        await (await _test()).shouldExit(0);
      });

      test("changes were made to the tool directory", () async {
        await d.file("my_app/tool/something.dart").create();
        await _testCase("pkg.ensureUpToDate('to-check', '');").create();
        await (await _test()).shouldExit(0);
      });

      test("changes were made to the test directory", () async {
        await d.dir("my_app/test", [d.file("something.dart")]).create();
        await _testCase("pkg.ensureUpToDate('to-check', '');").create();
        await (await _test()).shouldExit(0);
      });

      test("changes were made to the bin directory", () async {
        _touch("my_app/bin/foo.dart");
        await _testCase("pkg.ensureUpToDate('to-check', '');").create();
        await (await _test()).shouldExit(0);
      });

      test("changes were made to the package root", () async {
        await d.file("my_app/something.dart").create();
        await _testCase("pkg.ensureUpToDate('to-check', '');").create();
        await (await _test()).shouldExit(0);
      });
    });
  });

  group("executableRunner and executableArgs", () {
    test("in standalone source mode can be used to manually run an executable",
        () async {
      await pubGet();
      await _testCase("""
          var result = Process.runSync(
              pkg.executableRunner("foo"), pkg.executableArgs("foo"));
          expect(result.stdout, startsWith("in foo 1.2.3"));
          expect(result.exitCode, equals(0));
        """).create();

      await (await _test()).shouldExit(0);
    });

    group("in standalone compiled mode", () {
      test("can be used to manually run an executable", () async {
        await (await grind(["pkg-standalone-dev"])).shouldExit(0);

        await _testCase("""
          var result = Process.runSync(
              pkg.executableRunner("foo"), pkg.executableArgs("foo"));
          expect(result.stdout, startsWith("in foo 1.2.3"));
          expect(result.exitCode, equals(0));
        """).create();

        await (await _test()).shouldExit(0);
      });

      test("fails if a modification was made to the executable", () async {
        await (await grind(["pkg-standalone-dev"])).shouldExit(0);
        _touch("my_app/bin/foo.dart");

        await _testCase("""
          expect(
              () => pkg.executableArgs("foo"), throwsA(isA<TestFailure>()));
        """).create();
        await (await _test()).shouldExit(0);
      });
    });

    group("in Node.js mode", () {
      test("can be used to manually run an executable", () async {
        await (await grind(["pkg-npm-dev"])).shouldExit(0);

        await _testCase("""
          var result = Process.runSync(
              pkg.executableRunner("foo", node: true),
              pkg.executableArgs("foo", node: true));
          expect(result.stdout, startsWith("in foo 1.2.3"));
          expect(result.exitCode, equals(0));
        """).create();

        await (await _test()).shouldExit(0);
      });

      test("fails if a modification was made to the executable", () async {
        await (await grind(["pkg-npm-dev"])).shouldExit(0);
        _touch("my_app/bin/foo.dart");

        await _testCase("""
          expect(
              () => pkg.executableArgs("foo", node: true),
              throwsA(isA<TestFailure>()));
        """).create();
        await (await _test()).shouldExit(0);
      });
    });
  });

  group("ensureExecutableUpToDate", () {
    test("in standalone source mode doesn't throw", () async {
      await pubGet();
      // This just shouldn't throw an error.
      await _testCase("pkg.ensureExecutableUpToDate('foo');").create();

      await (await _test()).shouldExit(0);
    });

    test("fails multiple times", () async {
      await (await grind(["pkg-standalone-dev"])).shouldExit(0);
      _touch("my_app/bin/foo.dart");

      await _testCase("""
        expect(
            () => pkg.ensureExecutableUpToDate('foo'),
            throwsA(isA<TestFailure>()));

        // This caches results but that shouldn't prevent future failures.
        expect(
            () => pkg.ensureExecutableUpToDate('foo'),
            throwsA(isA<TestFailure>()));
      """).create();
      await (await _test()).shouldExit(0);
    });

    group("in standalone compiled mode", () {
      test("doesn't throw if the snapshot is up-to-date", () async {
        await (await grind(["pkg-standalone-dev"])).shouldExit(0);

        // This just shouldn't throw an error.
        await _testCase("pkg.ensureExecutableUpToDate('foo');").create();

        await (await _test()).shouldExit(0);
      });

      test("fails if a modification was made to the executable", () async {
        await (await grind(["pkg-standalone-dev"])).shouldExit(0);
        _touch("my_app/bin/foo.dart");

        await _testCase("""
          expect(
              () => pkg.ensureExecutableUpToDate('foo'),
              throwsA(isA<TestFailure>()));
        """).create();
        await (await _test()).shouldExit(0);
      });
    });

    group("in Node.js mode", () {
      test("can be used to manually run an executable", () async {
        await (await grind(["pkg-npm-dev"])).shouldExit(0);

        // This just shouldn't throw an error.
        await _testCase("pkg.ensureExecutableUpToDate('foo', node: true);")
            .create();

        await (await _test()).shouldExit(0);
      });

      test("fails if a modification was made to the executable", () async {
        await (await grind(["pkg-npm-dev"])).shouldExit(0);
        _touch("my_app/bin/foo.dart");

        await _testCase("""
          expect(
              () => pkg.ensureExecutableUpToDate('foo', node: true),
              throwsA(isA<TestFailure>()));
        """).create();
        await (await _test()).shouldExit(0);
      });
    });
  });
}

/// Returns a descriptor for a test file in `test.dart` that contains a single
/// test case that runs [code].
d.FileDescriptor _testCase(String code) {
  return d.file("my_app/test.dart", """
    import 'dart:convert';
    import 'dart:io';

    import 'package:test/test.dart';

    import 'package:cli_pkg/testing.dart' as pkg;

    void main() {
      test("inner test", () async {
        $code;
      });
    }
  """);
}

/// Starts a [TestProcess] running `pub run test` on the `test.dart` file in the
/// sandbox app.
Future<TestProcess> _test() =>
    TestProcess.start("pub$dotBat", ["run", "test", "test.dart"],
        workingDirectory: appDir);

/// Updates the modification time of the file at [path], within [d.sandbox].
Future<void> _touch(String path) async {
  var file = File(d.path(path));

  // Wait 1s so that filesystems with coarse-grained modification times will see
  // a difference.
  await Future<void>.delayed(Duration(seconds: 1));
  file.writeAsStringSync(file.readAsStringSync());
}
