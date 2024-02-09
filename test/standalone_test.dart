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
import 'dart:convert';

import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'package:cli_pkg/src/standalone/architecture.dart';
import 'package:cli_pkg/src/standalone/cli_platform.dart';
import 'package:cli_pkg/src/standalone/operating_system.dart';
import 'package:cli_pkg/src/utils.dart';

import 'descriptor.dart' as d;
import 'utils.dart';

/// The archive suffix for the current platform.
final _archiveSuffix =
    CliPlatform.current.toString() + CliPlatform.current.archiveExtension;

/// The contents of a `grind.dart` file that just enables standalone tasks.
final _enableStandalone = """
  void main(List<String> args) {
    pkg.addStandaloneTasks();
    grind(args);
  }
""";

void main() {
  var pubspec = {
    "name": "my_app",
    "version": "1.2.3",
    "executables": {"foo": "foo"}
  };

  group("directory and archive name", () {
    test("default to pkg.dartName", () async {
      await d.package(pubspec, _enableStandalone).create();

      await (await grind(["pkg-standalone-${CliPlatform.current}"]))
          .shouldExit(0);

      await d.archive("my_app/build/my_app-1.2.3-$_archiveSuffix",
          [d.dir("my_app")]).validate();
    });

    test("prefer pkg.name to pkg.dartName", () async {
      await d.package(pubspec, """
        void main(List<String> args) {
          pkg.name.value = "my-app";
          pkg.addStandaloneTasks();
          grind(args);
        }
      """).create();

      await (await grind(["pkg-standalone-${CliPlatform.current}"]))
          .shouldExit(0);

      await d.archive("my_app/build/my-app-1.2.3-$_archiveSuffix",
          [d.dir("my-app")]).validate();
    });

    test("prefer pkg.standaloneName to pkg.name", () async {
      await d.package(pubspec, """
        void main(List<String> args) {
          pkg.name.value = "my-app";
          pkg.standaloneName.value = "my-sa-app";
          pkg.addStandaloneTasks();
          grind(args);
        }
      """).create();

      await (await grind(["pkg-standalone-${CliPlatform.current}"]))
          .shouldExit(0);

      await d.archive("my_app/build/my-sa-app-1.2.3-$_archiveSuffix",
          [d.dir("my-sa-app")]).validate();
    });
  });

  group("executables", () {
    var pubspec = {
      "name": "my_app",
      "version": "1.2.3",
      "executables": {"foo": "foo", "bar": "bar", "qux": "bar"}
    };

    test("default to the pubspec's executables", () async {
      await d.package(pubspec, _enableStandalone).create();
      await (await grind(["pkg-standalone-${CliPlatform.current}"]))
          .shouldExit(0);

      await d.archive("my_app/build/my_app-1.2.3-$_archiveSuffix", [
        d.dir("my_app", [
          d.file("foo$dotBat", anything),
          d.file("bar$dotBat", anything),
          d.file("qux$dotBat", anything),
          if (!CliPlatform.current.useExe)
            d.dir("src", [
              d.file("foo.snapshot", anything),
              d.file("bar.snapshot", anything),
              d.file("qux.snapshot", anything),
            ])
        ])
      ]).validate();
    });

    test("can be removed by the user", () async {
      await d.package(pubspec, """
        void main(List<String> args) {
          pkg.executables.value.remove("foo");
          pkg.addStandaloneTasks();
          grind(args);
        }
      """).create();

      await (await grind(["pkg-standalone-${CliPlatform.current}"]))
          .shouldExit(0);

      await d.archive("my_app/build/my_app-1.2.3-$_archiveSuffix", [
        d.dir("my_app", [
          d.nothing("foo$dotBat"),
          d.file("bar$dotBat", anything),
          d.file("qux$dotBat", anything),
          if (!CliPlatform.current.useExe)
            d.dir("src",
                [d.nothing("foo.snapshot"), d.file("bar.snapshot", anything)])
        ])
      ]).validate();
    });

    test("can be added by the user", () async {
      await d.package(pubspec, """
        void main(List<String> args) {
          pkg.executables.value["zip"] = "bin/foo.dart";
          pkg.addStandaloneTasks();
          grind(args);
        }
      """).create();

      await (await grind(["pkg-standalone-${CliPlatform.current}"]))
          .shouldExit(0);

      await d.archive("my_app/build/my_app-1.2.3-$_archiveSuffix", [
        d.dir("my_app", [
          d.file("foo$dotBat", anything),
          d.file("bar$dotBat", anything),
          d.file("qux$dotBat", anything),
          d.file("zip$dotBat", anything),
          if (!CliPlatform.current.useExe)
            d.dir("src", [
              d.file("foo.snapshot", anything),
              d.file("bar.snapshot", anything),
              d.file("zip.snapshot", anything),
            ])
        ])
      ]).validate();
    });

    // Normally each of these would be separate test cases, but running grinder
    // takes so long that we collapse them for efficiency.
    test("can be invoked", () async {
      await d.package({
        "name": "my_app",
        "version": "1.2.3",
        "executables": {
          "foo": "foo",
          "bar": "bar",
          "qux": "bar",
          "const": "const"
        },
      }, """
          void main(List<String> args) {
            // TODO(nweiz): Test spaces and commas when dart-lang/sdk#46050 and
            // #44995 are fixed.
            pkg.environmentConstants.value["my-const"] =
                ${riskyArgStringLiteral(invokedByDart: true, dartCompileExe: true)};

            pkg.addStandaloneTasks();
            grind(args);
          }
        """).create();

      await d.dir("my_app/bin", [
        d.file("const.dart",
            "void main() => print(const String.fromEnvironment('my-const'));")
      ]).create();

      await (await grind(["pkg-standalone-${CliPlatform.current}"]))
          .shouldExit(0);
      await extract("my_app/build/my_app-1.2.3-$_archiveSuffix", "out");

      // Directly
      var executable = await TestProcess.start(
          d.path("out/my_app/foo$dotBat"), [],
          workingDirectory: d.sandbox);
      expect(executable.stdout, emits("in foo 1.2.3"));
      await executable.shouldExit(0);

      // Through a redirect
      executable = await TestProcess.start(d.path("out/my_app/qux$dotBat"), [],
          workingDirectory: d.sandbox);
      expect(executable.stdout, emits("in bar 1.2.3"));
      await executable.shouldExit(0);

      // We don't currently support resolving scripts through symlinks on
      // Windows. Although `%~dp0` refers to the symlink's location rather than
      // the script's, it's theoretically possible to determine the original
      // location by parsing the output of `dir /a %0`. However, that would
      // involve a lot of complex batch scripting, soif someone wants it they'll
      // need to add it themself.
      if (!Platform.isWindows) {
        // Through a relative symlink
        Link(d.path("foo-relative$dotBat")).createSync("out/my_app/foo$dotBat");
        executable = await TestProcess.start(d.path("foo-relative$dotBat"), [],
            workingDirectory: d.sandbox);
        expect(executable.stdout, emits("in foo 1.2.3"));
        await executable.shouldExit(0);

        // Through an absolute symlink
        Link(d.path("foo-absolute$dotBat"))
            .createSync(d.path("out/my_app/foo$dotBat"));
        executable = await TestProcess.start(d.path("foo-absolute$dotBat"), [],
            workingDirectory: d.sandbox);
        expect(executable.stdout, emits("in foo 1.2.3"));
        await executable.shouldExit(0);

        // Through a nested symlink
        Link(d.path("foo-nested$dotBat"))
            .createSync(d.path("foo-relative$dotBat"));
        executable = await TestProcess.start(d.path("foo-nested$dotBat"), [],
            workingDirectory: d.sandbox);
        expect(executable.stdout, emits("in foo 1.2.3"));
        await executable.shouldExit(0);
      }

      // Escapes environment constants
      executable = await TestProcess.start(
          d.path("out/my_app/const$dotBat"), [],
          workingDirectory: d.sandbox);
      expect(executable.stdout,
          emits(riskyArg(invokedByDart: true, dartCompileExe: true)));
      await executable.shouldExit(0);
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
              _enableStandalone,
              [d.file("LICENSE", "Please use my code")])
          .create();
      await (await grind(["pkg-standalone-${CliPlatform.current}"]))
          .shouldExit(0);

      await d.archive("my_app/build/my_app-1.2.3-$_archiveSuffix", [
        d.dir("my_app/src", [
          d.file(
              "LICENSE",
              allOf([
                contains("Please use my code"),
                contains("Copyright 2012, the Dart project authors."),
                contains("Direct dependency license"),
                contains("Indirect dependency license")
              ]))
        ])
      ]).validate();
    });

    test("is still generated if the package doesn't have a license", () async {
      await d.package(pubspec, _enableStandalone).create();
      await (await grind(["pkg-standalone-${CliPlatform.current}"]))
          .shouldExit(0);

      await d.archive("my_app/build/my_app-1.2.3-$_archiveSuffix", [
        d.dir("my_app/src", [
          d.file(
              "LICENSE", contains("Copyright 2012, the Dart project authors."))
        ])
      ]).validate();
    });
  });

  group("creates a package for", () {
    setUp(() => d.package({
          "name": "my_app",
          "version": "1.2.3",
          "executables": {"foo": "foo"}
        }, _enableStandalone).create());

    d.Descriptor archive(String os, String arch, {bool musl = false}) {
      var platform = CliPlatform(
          OperatingSystem.parse(os), Architecture.parse(arch),
          musl: musl);
      var name =
          "my_app/build/my_app-1.2.3-$os-$arch${platform.archiveExtension}";

      return d.archive(name, [
        d.dir("my_app", [
          d.file(
              "foo" +
                  (platform.os.isWindows
                      ? (platform.useExe ? '.exe' : '.bat')
                      : ''),
              anything),
          if (!platform.useExe)
            d.dir("src", [
              d.file("LICENSE", anything),
              d.file("dart${platform.binaryExtension}", anything),
              d.file("foo.snapshot", anything)
            ])
        ])
      ]);
    }

    group("Mac OS", () {
      test("64-bit x86", () async {
        await (await grind(["pkg-standalone-macos-x64"])).shouldExit(0);
        await archive("macos", "x64").validate();
      });

      test("64-bit ARM", () async {
        await (await grind(["pkg-standalone-macos-arm64"])).shouldExit(0);
        await archive("macos", "arm64").validate();
      });
    });

    group("Linux", () {
      for (var musl in [false, true]) {
        group(musl ? "musl" : "glibc", () {
          test("32-bit x86", () async {
            await (await grind(["pkg-standalone-linux-ia32"])).shouldExit(0);
            await archive("linux", "ia32", musl: musl).validate();
          });

          test("64-bit x86", () async {
            await (await grind(["pkg-standalone-linux-x64"])).shouldExit(0);
            await archive("linux", "x64", musl: musl).validate();
          });

          test("32-bit ARM", () async {
            await (await grind(["pkg-standalone-linux-arm"])).shouldExit(0);
            await archive("linux", "arm", musl: musl).validate();
          });

          test("64-bit ARM", () async {
            await (await grind(["pkg-standalone-linux-arm64"])).shouldExit(0);
            await archive("linux", "arm64", musl: musl).validate();
          });

          test("64-bit RISCV", () async {
            await (await grind(["pkg-standalone-linux-riscv64"])).shouldExit(0);
            await archive("linux", "riscv64", musl: musl).validate();
          });
        });
      }
    });

    group("Windows", () {
      test("32-bit x86", () async {
        await (await grind(["pkg-standalone-windows-ia32"])).shouldExit(0);
        await archive("windows", "ia32").validate();
      });

      test("64-bit x86", () async {
        await (await grind(["pkg-standalone-windows-x64"])).shouldExit(0);
        await archive("windows", "x64").validate();
      });

      test("64-bit ARM", () async {
        await (await grind(["pkg-standalone-windows-arm64"])).shouldExit(0);
        await archive("windows", "arm64").validate();
      });
    });

    group("Android", () {
      test("32-bit x86", () async {
        await (await grind(["pkg-standalone-android-ia32"])).shouldExit(0);
        await archive("android", "ia32").validate();
      });

      test("64-bit x86", () async {
        await (await grind(["pkg-standalone-android-x64"])).shouldExit(0);
        await archive("android", "x64").validate();
      });

      test("32-bit ARM", () async {
        await (await grind(["pkg-standalone-android-arm"])).shouldExit(0);
        await archive("android", "arm").validate();
      });

      test("64-bit ARM", () async {
        await (await grind(["pkg-standalone-android-arm64"])).shouldExit(0);
        await archive("android", "arm64").validate();
      });
    });

    group("iOS", () {
      test("64-bit ARM", () async {
        await (await grind(["pkg-standalone-ios-arm64"])).shouldExit(0);
        await archive("ios", "arm64").validate();
      });

      test("64-bit x86", () async {
        await (await grind(["pkg-standalone-ios-x64"])).shouldExit(0);
        await archive("ios", "x64").validate();
      });
    });
  });

  group("pkg-standalone-dev creates an executable", () {
    test("that can be invoked", () async {
      await d.package(pubspec, _enableStandalone).create();
      await (await grind(["pkg-standalone-dev"])).shouldExit(0);

      var executable = await TestProcess.start(
          d.path("my_app/build/foo$dotBat"), [],
          workingDirectory: d.sandbox);
      expect(executable.stdout, emits("in foo 1.2.3"));
      await executable.shouldExit(0);
    });

    test("that runs with asserts enabled", () async {
      await d.package(pubspec, _enableStandalone).create();
      await d
          .file("my_app/bin/foo.dart", "void main() { assert(false); }")
          .create();

      await (await grind(["pkg-standalone-dev"])).shouldExit(0);

      var executable = await TestProcess.start(
          d.path("my_app/build/foo$dotBat"), [],
          workingDirectory: d.sandbox);
      expect(executable.stderr, emitsThrough(contains("Failed assertion")));
      await executable.shouldExit(255);
    });

    test("and escapes a custom environment constants", () async {
      await d.package({
        "name": "my_app",
        "version": "1.2.3",
        "executables": {"const": "const"}
      }, """
          void main(List<String> args) {
            pkg.environmentConstants.value["my-const"] =
                ${riskyArgStringLiteral(invokedByDart: true, dartCompileExe: true)};

            pkg.addStandaloneTasks();
            grind(args);
          }
        """).create();

      await d.dir("my_app/bin", [
        d.file("const.dart",
            "void main() => print(const String.fromEnvironment('my-const'));")
      ]).create();

      await (await grind(["pkg-standalone-dev"])).shouldExit(0);

      var executable = await TestProcess.start(
          d.path("my_app/build/const$dotBat"), [],
          workingDirectory: d.sandbox);
      expect(executable.stdout,
          emits(riskyArg(invokedByDart: true, dartCompileExe: true)));
      await executable.shouldExit(0);
    });
  });
}
