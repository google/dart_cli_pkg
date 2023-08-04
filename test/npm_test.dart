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

import 'dart:async';

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

      await (await grind(["pkg-npm-dev"])).shouldExit();

      await d
          .file("my_app/build/npm/my_app.dart.js",
              isNot(contains('require("fs")')))
          .validate();

      // Test that running the executable still works.
      await d.dir("dir").create();
      await (await TestProcess.start("node$dotExe",
              [d.path("my_app/build/npm/foo.js"), d.path("dir")]))
          .shouldExit(0);
      expect(Directory(d.path("dir")).existsSync(), isFalse);
    });

    test("includes a source map comment in dev mode", () async {
      await d.package(pubspec, _enableNpm, [_packageJson]).create();
      await (await grind(["pkg-npm-dev"])).shouldExit();

      await d
          .file("my_app/build/npm/my_app.dart.js",
              contains("\n//# sourceMappingURL="))
          .validate();
    });

    test("doesn't include a source map comment in release mode", () async {
      await d.package(pubspec, _enableNpm, [_packageJson]).create();
      await (await grind(["pkg-npm-release"])).shouldExit();

      await d
          .file("my_app/build/npm/my_app.dart.js",
              isNot(contains("\n//# sourceMappingURL=")))
          .validate();
    });

    group("exports from jsModuleMainLibrary", () {
      test("can be imported", () async {
        await d.package(pubspec, """
          void main(List<String> args) {
            pkg.jsModuleMainLibrary.value = "lib/src/exports.dart";

            pkg.addNpmTasks();
            grind(args);
          }
        """, [
          _packageJson,
          d.dir("lib/src", [_exportsHello('"Hi, there!"')])
        ]).create();

        await (await grind(["pkg-npm-dev"])).shouldExit();

        await d.file("test.js", """
          var my_app = require("./my_app/build/npm");

          console.log(my_app.hello);
        """).create();

        var process =
            await TestProcess.start("node$dotExe", [d.path("test.js")]);
        expect(process.stdout, emitsInOrder(["Hi, there!", emitsDone]));
        await process.shouldExit(0);
      });

      /// Determines whether a package that declares a `pkg.JSRequire` on the
      /// `os` package has access to that package when loaded as a Node library.
      Future<bool> hasAccessToRequire(String requireDeclarations) async {
        await d.package(pubspec, """
          void main(List<String> args) {
            pkg.jsModuleMainLibrary.value = "lib/src/exports.dart";
            pkg.jsRequires.value = [$requireDeclarations];

            pkg.addNpmTasks();
            grind(args);
          }
        """, [
          _packageJson,
          d.dir("lib/src", [_exportsHello('osLoaded')])
        ]).create();

        await (await grind(["pkg-npm-dev"])).shouldExit();

        await d.dir("depender", [
          d.file(
              "package.json",
              json.encode({
                "dependencies": {"my_app": "file:../my_app/build/npm"}
              })),
          d.file("test.js", """
            var my_app = require("my_app");

            console.log(my_app.hello);
          """)
        ]).create();

        await (await TestProcess.start("npm", ["install"],
                runInShell: true, workingDirectory: d.path("depender")))
            .shouldExit(0);

        var process = await TestProcess.start(
            "node$dotExe", [d.path("depender/test.js")]);
        var result = (await process.stdout.next) == "true";
        await process.shouldExit(0);
        return result;
      }

      test("have access to global requires", () async {
        expect(
            hasAccessToRequire(
                "pkg.JSRequire('os', target: pkg.JSRequireTarget.all)"),
            completion(isTrue));
      });

      test("have access to node requires", () async {
        expect(
            hasAccessToRequire(
                "pkg.JSRequire('os', target: pkg.JSRequireTarget.node)"),
            completion(isTrue));
      });

      test("don't have access to cli requires", () async {
        expect(
            hasAccessToRequire(
                "pkg.JSRequire('os', target: pkg.JSRequireTarget.cli)"),
            completion(isFalse));
      });

      test("don't have access to browser requires", () async {
        expect(
            hasAccessToRequire(
                "pkg.JSRequire('os', target: pkg.JSRequireTarget.browser)"),
            completion(isFalse));
      });

      test("has access to default requires without a node target", () async {
        expect(
            hasAccessToRequire(
                "pkg.JSRequire('os', target: pkg.JSRequireTarget.defaultTarget)"),
            completion(isTrue));
      });

      test("doesn't have access to default requires with a node target",
          () async {
        expect(hasAccessToRequire("""
          pkg.JSRequire('http', target: pkg.JSRequireTarget.node),
          pkg.JSRequire('os', target: pkg.JSRequireTarget.defaultTarget),
        """), completion(isFalse));
      });
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

    /// Determines whether a package that declares a `pkg.JSRequire` on the
    /// `os` package has access to that package in its CLI executables.
    Future<bool> hasAccessToRequire(String requireDeclaration) async {
      await d.package(pubspec, """
        void main(List<String> args) {
          pkg.jsModuleMainLibrary.value = "lib/src/exports.dart";
          pkg.jsRequires.value.add($requireDeclaration);

          pkg.addNpmTasks();
          grind(args);
        }
      """, [
        _packageJson,
        d.dir("lib/src", [d.file("exports.dart", "void main() {}")])
      ]).create();

      // Generate this after the package so it doesn't race the creation of the
      // default exectuable file.
      await d.file("my_app/bin/foo.dart", """
        import 'package:js/js.dart';

        @JS('os')
        external Object? os;

        void main() {
          print(os != null);
        }
      """).create();

      await (await grind(["pkg-npm-dev"])).shouldExit();

      var process = await TestProcess.start(
          "node$dotExe", [d.path("my_app/build/npm/foo.js")]);
      var result = (await process.stdout.next) == "true";
      await process.shouldExit(0);
      return result;
    }

    test("with access to global requires", () async {
      expect(hasAccessToRequire("pkg.JSRequire('os')"), completion(isTrue));
    });

    test("with access to cli requires", () async {
      expect(
          hasAccessToRequire(
              "pkg.JSRequire('os', target: pkg.JSRequireTarget.cli)"),
          completion(isTrue));
    });

    test("with access to node requires", () async {
      expect(
          hasAccessToRequire(
              "pkg.JSRequire('os', target: pkg.JSRequireTarget.node)"),
          completion(isTrue));
    });

    test("without access to browser requires", () async {
      expect(
          hasAccessToRequire(
              "pkg.JSRequire('os', target: pkg.JSRequireTarget.browser)"),
          completion(isFalse));
    });

    test("without access to default requires", () async {
      expect(
          hasAccessToRequire(
              "pkg.JSRequire('os', target: pkg.JSRequireTarget.defaultTarget)"),
          completion(isFalse));
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

    test("escapes a custom environment constant", () async {
      await d.package(pubspec, """
        void main(List<String> args) {
          pkg.environmentConstants.value["my-const"] =
              ${riskyArgStringLiteral(invokedByDart: true)};

          pkg.addNpmTasks();
          grind(args);
        }
      """, [_packageJson]).create();

      await d.dir("my_app/bin", [
        d.file("foo.dart",
            "void main() => print(const String.fromEnvironment('my-const'));")
      ]).create();

      await (await grind(["pkg-npm-dev"])).shouldExit();

      var process = await TestProcess.start(
          "node$dotExe", [d.path("my_app/build/npm/foo.js")]);
      expect(process.stdout, emits(riskyArg(invokedByDart: true)));
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

    test("when jsEsmExports is set", () async {
      await d.package({
        "name": "my_app",
        "version": "1.2.3",
      }, """
          void main(List<String> args) {
            pkg.jsModuleMainLibrary.value = "lib/src/exports.dart";
            pkg.jsEsmExports.value = {};
            pkg.executables.value = {"exec": "bin/exec.dart"};

            pkg.addNpmTasks();
            grind(args);
          }
        """, [
        _packageJson,
        d.dir("lib/src", [
          _exportsHello('"Hi, there!"'),
        ]),
        d.dir("bin", [
          d.file("exec.dart", r"""
            import '../lib/src/exports.dart' as lib;

            void main(List<String> args) {
              print("Hello from exec");
            }
          """)
        ]),
      ]).create();

      await (await grind(["pkg-npm-dev"])).shouldExit();

      var process = await TestProcess.start(
          "node$dotExe", [d.path("my_app/build/npm/exec.js")]);
      expect(process.stdout, emitsInOrder(["Hello from exec", emitsDone]));
      await process.shouldExit(0);
    });

    var strictOrSloppy = r"""
      import 'dart:js_util';

      void main(List<String> args) {
        try {
          // This shouldn't throw an error in sloppy mode.
          setProperty('', 'name', null);
          print("sloppy mode");
        } catch (_) {
          print("strict mode");
        }
      }
    """;

    test("that run in sloppy mode by default", () async {
      await d.package(pubspec, _enableNpm, [
        _packageJson,
        d.dir("bin", [d.file("foo.dart", strictOrSloppy)]),
      ]).create();

      await (await grind(["pkg-npm-dev"])).shouldExit();

      var process = await TestProcess.start(
          "node$dotExe", [d.path("my_app/build/npm/foo.js")]);
      expect(process.stdout, emitsInOrder(["sloppy mode", emitsDone]));
      await process.shouldExit(0);
    });

    test("that run in strict mode with jsForceStrictMode = true", () async {
      await d.package(pubspec, r"""
          void main(List<String> args) {
            pkg.addNpmTasks();
            pkg.jsForceStrictMode.value = true;
            grind(args);
          }
        """, [
        _packageJson,
        d.dir("bin", [d.file("foo.dart", strictOrSloppy)]),
      ]).create();

      await (await grind(["pkg-npm-dev"])).shouldExit();

      var process = await TestProcess.start(
          "node$dotExe", [d.path("my_app/build/npm/foo.js")]);
      expect(process.stdout, emitsInOrder(["strict mode", emitsDone]));
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
              after(jsonDecode, containsPair("main", "my_app.default.js")))
          .validate();
    });
  });

  group("exports", () {
    const grindDotDart = """
      void main(List<String> args) {
        pkg.jsModuleMainLibrary.value = "lib/src/module_main.dart";
        pkg.jsRequires.value = [pkg.JSRequire('util', target: pkg.JSRequireTarget.cli)];

        pkg.addNpmTasks();
        grind(args);
      }
    """;

    const grindDotDartWithExports = """
      void main(List<String> args) {
        pkg.jsModuleMainLibrary.value = "lib/src/module_main.dart";
        pkg.jsRequires.value = [
          pkg.JSRequire('util', target: pkg.JSRequireTarget.cli),
          pkg.JSRequire('other', target: pkg.JSRequireTarget.node),
        ];

        pkg.addNpmTasks();
        grind(args);
      }
    """;

    test("isn't added if there's only one main JS file", () async {
      await d.package(pubspec, grindDotDart, [
        _packageJson,
        d.dir("lib/src", [d.file("module_main.dart", "void main() {}")])
      ]).create();
      await (await grind(["pkg-npm-dev"])).shouldExit();

      await d
          .file("my_app/build/npm/package.json",
              after(jsonDecode, isNot(contains("exports"))))
          .validate();
    });

    test("adds exports if another target is set", () async {
      await d.package(pubspec, grindDotDartWithExports, [
        _packageJson,
        d.dir("lib/src", [d.file("module_main.dart", "void main() {}")])
      ]).create();
      await (await grind(["pkg-npm-dev"])).shouldExit();

      await d
          .file(
              "my_app/build/npm/package.json",
              after(
                  jsonDecode,
                  containsPair("exports", {
                    "node": "./my_app.node.js",
                    "default": "./my_app.default.js"
                  })))
          .validate();
    });

    test("generates loadable ESM files if jsEsmExports is set", () async {
      await d.package(pubspec, """
        void main(List<String> args) {
          pkg.jsModuleMainLibrary.value = "lib/src/exports.dart";
          pkg.jsRequires.value = [
            pkg.JSRequire('util', target: pkg.JSRequireTarget.cli),
            pkg.JSRequire('os', target: pkg.JSRequireTarget.node),
          ];
          pkg.jsEsmExports.value = {'hello'};

          pkg.addNpmTasks();
          grind(args);
        }
      """, [
        _packageJson,
        d.dir("lib/src", [_exportsHello('osLoaded')])
      ]).create();
      await (await grind(["pkg-npm-dev"])).shouldExit();

      await d
          .file(
              "my_app/build/npm/package.json",
              after(
                  jsonDecode,
                  containsPair("exports", {
                    "node": {
                      "require": "./my_app.node.js",
                      "default": "./my_app.node.mjs"
                    },
                    "default": {
                      "require": "./my_app.default.cjs",
                      "default": "./my_app.default.js"
                    }
                  })))
          .validate();

      await d.dir("depender", [
        d.file(
            "package.json",
            json.encode({
              "dependencies": {"my_app": "file:../my_app/build/npm"}
            })),
        d.file("test.mjs", """
          import * as myApp from "my_app";

          console.log(myApp.hello);
        """),
        d.file("test.cjs", """
          const myApp = require("my_app");

          console.log(myApp.hello);
        """),
        // Regression test for sass/dart-sass#2017
        d.file("both.mjs", """
          import "./test.mjs";
          import "./test.cjs";
        """)
      ]).create();

      await (await TestProcess.start("npm", ["install"],
              runInShell: true, workingDirectory: d.path("depender")))
          .shouldExit(0);

      var mjsProcess =
          await TestProcess.start("node$dotExe", [d.path("depender/test.mjs")]);
      expect(mjsProcess.stdout, emits("true"));
      await mjsProcess.shouldExit(0);

      var cjsProcess =
          await TestProcess.start("node$dotExe", [d.path("depender/test.cjs")]);
      expect(cjsProcess.stdout, emits("true"));
      await cjsProcess.shouldExit(0);

      var bothProcess =
          await TestProcess.start("node$dotExe", [d.path("depender/both.mjs")]);
      expect(bothProcess.stdout, emits("true"));
      expect(bothProcess.stdout, emits("true"));
      await bothProcess.shouldExit(0);
    });

    test("overwrite existing string value", () async {
      await d.package(pubspec, grindDotDartWithExports, [
        d.file(
            "package.json",
            jsonEncode({
              "name": "my_app",
              "exports": "./foo",
            })),
        d.dir("lib/src", [d.file("module_main.dart", "void main() {}")])
      ]).create();
      await (await grind(["pkg-npm-dev"])).shouldExit();

      await d
          .file(
              "my_app/build/npm/package.json",
              after(
                  jsonDecode,
                  containsPair("exports", {
                    "node": "./my_app.node.js",
                    "default": "./my_app.default.js",
                  })))
          .validate();
    });

    test("overwrite existing array value", () async {
      await d.package(pubspec, grindDotDartWithExports, [
        d.file(
            "package.json",
            jsonEncode({
              "name": "my_app",
              "exports": ["./foo", "./bar"],
            })),
        d.dir("lib/src", [d.file("module_main.dart", "void main() {}")])
      ]).create();
      await (await grind(["pkg-npm-dev"])).shouldExit();

      await d
          .file(
              "my_app/build/npm/package.json",
              after(
                  jsonDecode,
                  containsPair("exports", {
                    "node": "./my_app.node.js",
                    "default": "./my_app.default.js",
                  })))
          .validate();
    });

    test("merges with existing map/JSON values - default only", () async {
      await d.package(pubspec, grindDotDart, [
        d.file(
            "package.json",
            jsonEncode({
              "name": "my_app",
              "exports": {
                "types": "./foo",
                "node": "./bar",
                "default": "./baz",
              },
            })),
        d.dir("lib/src", [d.file("module_main.dart", "void main() {}")])
      ]).create();
      await (await grind(["pkg-npm-dev"])).shouldExit();

      await d
          .file(
              "my_app/build/npm/package.json",
              after(
                  jsonDecode,
                  containsPair("exports", {
                    "types": "./foo",
                    "node": "./bar",
                    "default": "./my_app.default.js",
                  })))
          .validate();
    });

    test("merges with existing map/JSON values - with browser", () async {
      await d.package(pubspec, grindDotDartWithExports, [
        d.file(
            "package.json",
            jsonEncode({
              "name": "my_app",
              "exports": {
                "types": "./foo",
                "node": "./bar",
                "default": "./baz",
              },
            })),
        d.dir("lib/src", [d.file("module_main.dart", "void main() {}")])
      ]).create();
      await (await grind(["pkg-npm-dev"])).shouldExit();

      await d
          .file(
              "my_app/build/npm/package.json",
              after(
                  jsonDecode,
                  containsPair("exports", {
                    "types": "./foo",
                    "node": "./my_app.node.js",
                    "default": "./my_app.default.js",
                  })))
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
      await expectLater(grinder.stdout, emitsThrough("latest"));
      await grinder.shouldExit();
    });

    test("defaults to a prerelease identifier", () async {
      await d.package({...pubspec, "version": "1.2.3-foo.4.bar"}, """
        void main(List<String> args) {
          print(pkg.npmDistTag);
        }
      """, [_packageJson]).create();

      var grinder = await grind(["pkg-npm-dev"]);
      await expectLater(grinder.stdout, emitsThrough("foo"));
      await grinder.shouldExit();
    });

    test('defaults to "pre" for a prerelease without an identifier', () async {
      await d.package({...pubspec, "version": "1.2.3-4.foo"}, """
        void main(List<String> args) {
          print(pkg.npmDistTag);
        }
      """, [_packageJson]).create();

      var grinder = await grind(["pkg-npm-dev"]);
      await expectLater(grinder.stdout, emitsThrough("pre"));
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
      await expectLater(grinder.stdout, emitsThrough("qux"));
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
              "environment": {"sdk": ">=2.0.0 <4.0.0"},
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
              "environment": {"sdk": ">=2.0.0 <4.0.0"}
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

  group("npmAdditionalFiles", () {
    test("adds a file to the generated directory", () async {
      await d.package(pubspec, """
        void main(List<String> args) {
          pkg.npmAdditionalFiles.value = {"foo/bar/baz.txt": "contents"};
          pkg.addNpmTasks();
          grind(args);
        }
      """, [_packageJson]).create();
      await (await grind(["pkg-npm-dev"])).shouldExit(0);

      await d.file("my_app/build/npm/foo/bar/baz.txt", "contents").validate();
    });

    test("throws for an absolute path", () async {
      await d.package(pubspec, """
        void main(List<String> args) {
          pkg.npmAdditionalFiles.value = {"/foo/bar/baz.txt": "contents"};
          pkg.addNpmTasks();
          grind(args);
        }
      """, [_packageJson]).create();

      var process = await grind(["pkg-npm-dev"]);
      expect(
          process.stderr,
          emitsThrough(
              contains("pkg.npmAdditionalFiles keys must be relative paths,")));
      expect(process.stderr, emits(contains("/foo/bar/baz.txt")));
      await process.shouldExit(1);
    });
  });

  group("package:cli_pkg/js.dart", () {
    group("wrapJSException in strict mode", () {
      // Asserts that the JS [expression] doesn't crash when caught by Dart code
      // after going through `wrapJSExceptions()`.
      Future<void> assertCatchesGracefully(String expression) async {
        await d.package(pubspec, r"""
            void main(List<String> args) {
              pkg.addNpmTasks();
              pkg.jsForceStrictMode.value = true;
              grind(args);
            }
          """, [
          _packageJson,
          d.dir("bin", [
            d.file("foo.dart", """
              import 'package:cli_pkg/js.dart';
              import 'package:js/js.dart';

              @JS("Function")
              class _JSFunction {
                external _JSFunction(String arguments, String body);
                external Object? call();
              }

              void main() {
                try {
                  wrapJSExceptions(() {
                    _JSFunction("error",
                        "throw \${${json.encode(expression)}};").call();
                  });
                } catch (_, stackTrace) {
                  print(stackTrace);
                }
              }
            """)
          ]),
        ]).create();

        await (await grind(["pkg-npm-dev"])).shouldExit();

        var process = await TestProcess.start(
            "node$dotExe", [d.path("my_app/build/npm/foo.js")]);
        await process.shouldExit(0);
      }

      test(
          "handles a thrown string", () => assertCatchesGracefully('"string"'));

      test("handles a thrown boolean", () => assertCatchesGracefully('true'));

      test("handles a thrown number", () => assertCatchesGracefully('123'));

      test("handles a thrown Symbol",
          () => assertCatchesGracefully('Symbol("foo")'));

      test("handles a thrown BigInt",
          () => assertCatchesGracefully('BigInt(123)'));

      test("handles a thrown null",
          () => assertCatchesGracefully('BigInt(null)'));

      test("handles a thrown undefined",
          () => assertCatchesGracefully('BigInt(undefined)'));
    });
  });
}

/// Returns a [d.FileDescriptor] named `export.dart` that exports a JS value
/// named "hello" whose value is the given Dart [expression].
///
/// The [expression] has access to an `osLoaded` field that's true if Node.js's
/// `os` core library has been loaded and `false` otherwise.
d.FileDescriptor _exportsHello(String expression) => d.file("exports.dart", """
    import 'package:js/js.dart';

    @JS()
    class Exports {
      external set hello(Object value);
    }

    @JS()
    external Exports get exports;

    @JS('os')
    external Object? os;

    final osLoaded = os != null;

    void main() {
      exports.hello = ($expression);
    }
  """);
