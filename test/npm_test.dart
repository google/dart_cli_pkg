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

import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'package:cli_pkg/src/utils.dart';

import 'descriptor.dart' as d;
import 'utils.dart';

/// The contents of a `grind.dart` file that just enables npm tasks.
final _enableNpm = """
  void main(List<String> args) {
    pkg.addNpmTasks();
    grind(args);
  }
""";

/// A minimal package.json file.
final _packageJson = d.file("package.json", jsonEncode({"name": "my_app"}));

void main() {
  var pubspec = {
    "name": "my_app",
    "version": "1.2.3",
    "executables": {"foo": "foo"}
  };

  group("JS compilation", () {
    // Unfortunately, there's no reliable way to test dart2js flags without
    // tightly coupling these tests to specific details of dart2js output that
    // might change in the future.

    test("replaces dynamic require()s with eager require()s", () async {
      await d.package(pubspec, _enableNpm, [_packageJson]).create();

      await d.dir("my_app/bin", [
        d.file("foo.dart", """
          import 'package:js/js.dart';

          @JS()
          class FS {
            external void rmdirSync(String path);
          }

          @JS()
          external FS require(String name);

          void main(List<String> args) {
            require("fs").rmdirSync(args.first);
          }
        """)
      ]).create();

      await (await grind(["pkg-js-dev"])).shouldExit();

      // Test that the only occurrence of `require("fs")` is the one assigning
      // it to a global variable.
      await d
          .file(
              "my_app/build/my_app.dart.js",
              allOf([
                contains('self.fs = require("fs");'),
                predicate((string) =>
                    RegExp(r'require\("fs"\);')
                        .allMatches(string as String)
                        .length ==
                    1)
              ]))
          .validate();
    });

    test("includes a source map comment in dev mode", () async {
      await d.package(pubspec, _enableNpm, [_packageJson]).create();
      await (await grind(["pkg-js-dev"])).shouldExit();

      await d
          .file("my_app/build/my_app.dart.js",
              contains("\n//# sourceMappingURL="))
          .validate();
    });

    test("doesn't include a source map comment in release mode", () async {
      await d.package(pubspec, _enableNpm, [_packageJson]).create();
      await (await grind(["pkg-js-release"])).shouldExit();

      await d
          .file("my_app/build/my_app.dart.js",
              isNot(contains("\n//# sourceMappingURL=")))
          .validate();
    });

    test("exports from jsModuleMainLibrary can be imported", () async {
      await d.package(pubspec, """
        void main(List<String> args) {
          pkg.jsModuleMainLibrary.value = "lib/src/exports.dart";

          pkg.addNpmTasks();
          grind(args);
        }
      """, [
        _packageJson,
        d.dir("lib/src", [
          d.file("exports.dart", """
            import 'package:js/js.dart';

            @JS()
            class Exports {
              external set hello(String value);
            }

            @JS()
            external Exports get exports;

            void main() {
              exports.hello = "Hi, there!";
            }
          """)
        ])
      ]).create();

      await (await grind(["pkg-js-dev"])).shouldExit();

      await d.file("test.js", """
        var my_app = require("./my_app/build/my_app.dart.js");

        console.log(my_app.hello);
      """).create();

      var process = await TestProcess.start("node$dotExe", [d.path("test.js")]);
      expect(process.stdout, emitsInOrder(["Hi, there!", emitsDone]));
      await process.shouldExit(0);
    });

    test("takes its name from the package.json name field", () async {
      await d.package(pubspec, _enableNpm, [
        d.file("package.json", jsonEncode({"name": "mine-owne-app"}))
      ]).create();
      await (await grind(["pkg-js-dev"])).shouldExit();

      await d.file("my_app/build/mine-owne-app.dart.js", anything).validate();
    });
  });

  group("generates executables", () {
    test("that can be invoked", () async {
      await d
          .package(
              {
                "name": "my_app",
                "version": "1.2.3",
                "executables": {"foo": "foo", "bar": "bar", "qux": "zang"}
              },
              _enableNpm,
              [_packageJson])
          .create();
      await (await grind(["pkg-npm-dev"])).shouldExit();

      var process = await TestProcess.start(
          "node$dotExe", [d.path("my_app/build/npm/foo.js")]);
      expect(process.stdout, emitsInOrder(["in foo 1.2.3", emitsDone]));
      await process.shouldExit(0);

      process = await TestProcess.start(
          "node$dotExe", [d.path("my_app/build/npm/bar.js")]);
      expect(process.stdout, emitsInOrder(["in bar 1.2.3", emitsDone]));
      await process.shouldExit(0);

      process = await TestProcess.start(
          "node$dotExe", [d.path("my_app/build/npm/qux.js")]);
      expect(process.stdout, emitsInOrder(["in zang 1.2.3", emitsDone]));
      await process.shouldExit(0);
    });

    test("with access to the node, version, and dart-version constants",
        () async {
      await d.package(pubspec, _enableNpm, [_packageJson]).create();

      await d.dir("my_app/bin", [
        d.file("foo.dart", r"""
          void main() {
            print("node: ${const bool.fromEnvironment('node')}");
            print("version: ${const String.fromEnvironment('version')}");
            print("dart-version: "
                "${const String.fromEnvironment('dart-version')}");
          }
        """)
      ]).create();

      await (await grind(["pkg-npm-dev"])).shouldExit();

      var process = await TestProcess.start(
          "node$dotExe", [d.path("my_app/build/npm/foo.js")]);
      expect(
          process.stdout,
          emitsInOrder([
            "node: true",
            "version: 1.2.3",
            "dart-version: $dartVersion",
            emitsDone
          ]));
      await process.shouldExit(0);
    });

    test("with access to command-line args", () async {
      await d.package(pubspec, _enableNpm, [_packageJson]).create();

      await d.dir("my_app/bin", [
        d.file("foo.dart", r"""
          void main(List<String> args) {
            print("args is List<String>: ${args is List<String>}");
            print("args: $args");
          }
        """)
      ]).create();

      await (await grind(["pkg-npm-dev"])).shouldExit();

      var process = await TestProcess.start("node$dotExe",
          [d.path("my_app/build/npm/foo.js"), "foo", "bar", "baz"]);
      expect(
          process.stdout,
          emitsInOrder([
            "args is List<String>: true",
            "args: [foo, bar, baz]",
            emitsDone
          ]));
      await process.shouldExit(0);
    });

    test("with the ability to do conditional imports", () async {
      await d.package(pubspec, _enableNpm, [
        _packageJson,
        d.dir("lib", [
          d.file("input_vm.dart", "final value = 'vm';"),
          d.file("input_js.dart", "final value = 'js';")
        ])
      ]).create();

      await d.dir("my_app/bin", [
        d.file("foo.dart", r"""
          import 'package:my_app/input_vm.dart'
              if (dart.library.js) 'package:my_app/input_js.dart';

          void main(List<String> args) {
            print(value);
          }
        """)
      ]).create();

      await (await grind(["pkg-npm-dev"])).shouldExit();

      var process = await TestProcess.start(
          "node$dotExe", [d.path("my_app/build/npm/foo.js")]);
      expect(process.stdout, emitsInOrder(["js", emitsDone]));
      await process.shouldExit(0);
    });
  });

  group("package.json", () {
    test("throws an error if it doesn't exist on disk", () async {
      await d.package(pubspec, _enableNpm).create();

      var process = await grind(["pkg-npm-dev"]);
      expect(
          process.stdout,
          emitsThrough(contains(
              "pkg.npmPackageJson must be set to build an npm package.")));
      await process.shouldExit(1);
    });

    test("is loaded from disk by default", () async {
      await d.package(pubspec, _enableNpm, [
        d.file(
            "package.json", jsonEncode({"name": "my_app", "some": "attribute"}))
      ]).create();

      await (await grind(["pkg-npm-dev"])).shouldExit();

      await d
          .file("my_app/build/npm/package.json",
              after(jsonDecode, containsPair("some", "attribute")))
          .validate();
    });

    test("prefers an explicit package.json to one from disk", () async {
      await d.package(pubspec, """
        void main(List<String> args) {
          pkg.npmPackageJson.value = {
            "name": "my_app",
            "another": "attribute"
          };

          pkg.addNpmTasks();
          grind(args);
        }
      """, [
        d.file(
            "package.json", jsonEncode({"name": "my_app", "some": "attribute"}))
      ]).create();

      await (await grind(["pkg-npm-dev"])).shouldExit();

      await d
          .file(
              "my_app/build/npm/package.json",
              after(
                  jsonDecode,
                  allOf([
                    containsPair("another", "attribute"),
                    isNot(containsPair("some", "attribute"))
                  ])))
          .validate();
    });

    test("automatically adds the version", () async {
      await d.package(pubspec, _enableNpm, [_packageJson]).create();
      await (await grind(["pkg-npm-dev"])).shouldExit();

      await d
          .file("my_app/build/npm/package.json",
              after(jsonDecode, containsPair("version", "1.2.3")))
          .validate();
    });

    test("automatically adds executables", () async {
      await d
          .package(
              {
                "name": "my_app",
                "version": "1.2.3",
                "executables": {"foo": "foo", "bar": "bar", "qux": "zang"}
              },
              _enableNpm,
              [_packageJson])
          .create();
      await (await grind(["pkg-npm-dev"])).shouldExit();

      await d
          .file(
              "my_app/build/npm/package.json",
              after(
                  jsonDecode,
                  containsPair("bin",
                      {"foo": "foo.js", "bar": "bar.js", "qux": "qux.js"})))
          .validate();
    });

    test("doesn't add main if jsModuleMainLibrary isn't set", () async {
      await d.package(pubspec, _enableNpm, [_packageJson]).create();
      await (await grind(["pkg-npm-dev"])).shouldExit();

      await d
          .file("my_app/build/npm/package.json",
              after(jsonDecode, isNot(contains("main"))))
          .validate();
    });

    test("automatically adds main if jsModuleMainLibrary is set", () async {
      await d.package(pubspec, """
        void main(List<String> args) {
          pkg.jsModuleMainLibrary.value = "lib/src/module_main.dart";

          pkg.addNpmTasks();
          grind(args);
        }
      """, [
        _packageJson,
        d.dir("lib/src", [d.file("module_main.dart", "void main() {}")])
      ]).create();
      await (await grind(["pkg-npm-dev"])).shouldExit();

      await d
          .file("my_app/build/npm/package.json",
              after(jsonDecode, containsPair("main", "my_app.dart.js")))
          .validate();
    });
  });

  group("npmDistTag", () {
    test('defaults to "latest" for a non-prerelease', () async {
      await d.package(pubspec, """
        void main(List<String> args) {
          print(pkg.npmDistTag);
        }
      """, [_packageJson]).create();

      var grinder = await grind(["pkg-npm-dev"]);
      await expect(grinder.stdout, emitsThrough("latest"));
      await grinder.shouldExit();
    });

    test("defaults to a prerelease identifier", () async {
      await d.package({...pubspec, "version": "1.2.3-foo.4.bar"}, """
        void main(List<String> args) {
          print(pkg.npmDistTag);
        }
      """, [_packageJson]).create();

      var grinder = await grind(["pkg-npm-dev"]);
      await expect(grinder.stdout, emitsThrough("foo"));
      await grinder.shouldExit();
    });

    test('defaults to "pre" for a prerelease without an identifier', () async {
      await d.package({...pubspec, "version": "1.2.3-4.foo"}, """
        void main(List<String> args) {
          print(pkg.npmDistTag);
        }
      """, [_packageJson]).create();

      var grinder = await grind(["pkg-npm-dev"]);
      await expect(grinder.stdout, emitsThrough("pre"));
      await grinder.shouldExit();
    });

    test("can be overridden", () async {
      await d.package(pubspec, """
        void main(List<String> args) {
          pkg.npmDistTag.value = "qux";
          print(pkg.npmDistTag);
        }
      """, [_packageJson]).create();

      var grinder = await grind(["pkg-npm-dev"]);
      await expect(grinder.stdout, emitsThrough("qux"));
      await grinder.shouldExit();
    });
  });

  group("README.md", () {
    test("isn't added if it doesn't exist on disk", () async {
      await d.package(pubspec, _enableNpm, [_packageJson]).create();
      await (await grind(["pkg-npm-dev"])).shouldExit();

      await d.nothing("my_app/build/npm/README.md").validate();
    });

    test("is loaded from disk by default", () async {
      await d.package(pubspec, _enableNpm,
          [_packageJson, d.file("README.md", "Some README text")]).create();

      await (await grind(["pkg-npm-dev"])).shouldExit();

      await d.file("my_app/build/npm/README.md", "Some README text").validate();
    });

    test("prefers an explicit npmReadme to one from disk", () async {
      await d.package(pubspec, """
        void main(List<String> args) {
          pkg.npmReadme.value = "Other README text";

          pkg.addNpmTasks();
          grind(args);
        }
      """, [_packageJson, d.file("README.md", "Some README text")]).create();

      await (await grind(["pkg-npm-dev"])).shouldExit();

      await d
          .file("my_app/build/npm/README.md", "Other README text")
          .validate();
    });
  });

  group("the LICENSE file", () {
    // Normally each of these would be separate test cases, but running grinder
    // takes so long that we collapse them for efficiency.
    test(
        "includes the license for the package, Dart, direct dependencies, and "
        "transitive dependencies", () async {
      await d.dir("direct_dep", [
        d.file(
            "pubspec.yaml",
            json.encode({
              "name": "direct_dep",
              "version": "1.0.0",
              "environment": {"sdk": ">=2.0.0 <3.0.0"},
              "dependencies": {
                "indirect_dep": {"path": "../indirect_dep"}
              }
            })),
        d.file("LICENSE.md", "Direct dependency license")
      ]).create();

      await d.dir("indirect_dep", [
        d.file(
            "pubspec.yaml",
            json.encode({
              "name": "indirect_dep",
              "version": "1.0.0",
              "environment": {"sdk": ">=2.0.0 <3.0.0"}
            })),
        d.file("COPYING", "Indirect dependency license")
      ]).create();

      await d
          .package(
              {
                ...pubspec,
                "dependencies": {
                  "direct_dep": {"path": "../direct_dep"}
                }
              },
              _enableNpm,
              [_packageJson, d.file("LICENSE", "Please use my code")])
          .create();
      await (await grind(["pkg-npm-dev"])).shouldExit(0);

      await d
          .file(
              "my_app/build/npm/LICENSE",
              allOf([
                contains("Please use my code"),
                contains("Copyright 2012, the Dart project authors."),
                contains("Direct dependency license"),
                contains("Indirect dependency license")
              ]))
          .validate();
    });

    test("is still generated if the package doesn't have a license", () async {
      await d.package(pubspec, _enableNpm, [_packageJson]).create();
      await (await grind(["pkg-npm-dev"])).shouldExit(0);

      await d
          .file("my_app/build/npm/LICENSE",
              contains("Copyright 2012, the Dart project authors."))
          .validate();
    });
  });
}
