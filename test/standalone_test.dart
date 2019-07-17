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

import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'descriptor.dart' as d;
import 'utils.dart';

/// The operating system/architecture combination for the current machine.
///
/// We build this for most tests so we can avoid downloading SDKs from the Dart
/// server.
final _target = Platform.operatingSystem +
    "-" +
    (Platform.version.contains("x64") ? "x64" : "ia32");

/// The archive suffix for the current platform.
final _archiveSuffix = _target + (Platform.isWindows ? ".zip" : ".tar.gz");

/// The extension for executable scripts on the current platform.
final _dotBat = Platform.isWindows ? ".bat" : "";

/// The contents of a `grind.dart` file that just exports
/// `package:cli_pkg/standalone.dart`.
final _exportStandalone = """
  export 'package:cli_pkg/standalone.dart';

  void main(List<String> args) => grind(args);
""";

void main() {
  group("directory and archive name", () {
    var pubspec = {
      "name": "my_app",
      "version": "1.2.3",
      "executables": {"foo": "foo"}
    };

    test("default to pkgDartName", () async {
      await d.package("my_app", pubspec, _exportStandalone).create();

      await (await grind(["pkg-standalone-$_target"])).shouldExit(0);

      await d.archive("my_app/build/my_app-1.2.3-$_archiveSuffix",
          [d.dir("my_app")]).validate();
    });

    test("prefer pkgName to pkgDartName", () async {
      await d.package("my_app", pubspec, """
        export 'package:cli_pkg/standalone.dart';

        void main(List<String> args) {
          pkgName = "my-app";
          grind(args);
        }
      """).create();

      await (await grind(["pkg-standalone-$_target"])).shouldExit(0);

      await d.archive("my_app/build/my-app-1.2.3-$_archiveSuffix",
          [d.dir("my-app")]).validate();
    });

    test("prefer pkgStandaloneName to pkgName", () async {
      await d.package("my_app", pubspec, """
        import 'package:cli_pkg/standalone.dart';
        export 'package:cli_pkg/standalone.dart';

        void main(List<String> args) {
          pkgName = "my-app";
          pkgStandaloneName = "my-sa-app";
          grind(args);
        }
      """).create();

      await (await grind(["pkg-standalone-$_target"])).shouldExit(0);

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
      await d.package("my_app", pubspec, _exportStandalone).create();
      await (await grind(["pkg-standalone-$_target"])).shouldExit(0);

      await d.archive("my_app/build/my_app-1.2.3-$_archiveSuffix", [
        d.dir("my_app", [
          d.file("foo$_dotBat", anything),
          d.file("bar$_dotBat", anything),
          d.file("qux$_dotBat", anything),
          d.dir("src", [
            d.file("foo.dart.snapshot", anything),
            d.file("bar.dart.snapshot", anything),
            d.nothing("qux.dart.snapshot")
          ])
        ])
      ]).validate();
    });

    test("can be removed by the user", () async {
      await d.package("my_app", pubspec, """
        export 'package:cli_pkg/standalone.dart';

        void main(List<String> args) {
          pkgExecutables.remove("foo");
          grind(args);
        }
      """).create();

      await (await grind(["pkg-standalone-$_target"])).shouldExit(0);

      await d.archive("my_app/build/my_app-1.2.3-$_archiveSuffix", [
        d.dir("my_app", [
          d.nothing("foo$_dotBat"),
          d.file("bar$_dotBat", anything),
          d.file("qux$_dotBat", anything),
          d.dir("src", [
            d.nothing("foo.dart.snapshot"),
            d.file("bar.dart.snapshot", anything)
          ])
        ])
      ]).validate();
    });

    test("can be added by the user", () async {
      await d.package("my_app", pubspec, """
        export 'package:cli_pkg/standalone.dart';

        void main(List<String> args) {
          pkgExecutables["zip"] = "bin/foo.dart";
          grind(args);
        }
      """).create();

      await (await grind(["pkg-standalone-$_target"])).shouldExit(0);

      await d.archive("my_app/build/my_app-1.2.3-$_archiveSuffix", [
        d.dir("my_app", [
          d.file("foo$_dotBat", anything),
          d.file("bar$_dotBat", anything),
          d.file("qux$_dotBat", anything),
          d.file("zip$_dotBat", anything),
          d.dir("src", [
            d.file("foo.dart.snapshot", anything),
            d.file("bar.dart.snapshot", anything),
            d.nothing("zip.dart.snapshot")
          ])
        ])
      ]).validate();
    });

    // Normally each of these would be separate test cases, but running grinder
    // takes so long that we collapse them for efficiency.
    test("can be invoked", () async {
      await d.package("my_app", pubspec, _exportStandalone).create();
      await (await grind(["pkg-standalone-$_target"])).shouldExit(0);
      await extract("my_app/build/my_app-1.2.3-$_archiveSuffix", "out");

      // Directly
      var executable = await TestProcess.start(
          d.path("out/my_app/foo$_dotBat"), [],
          workingDirectory: d.sandbox);
      expect(executable.stdout, emits("in foo"));
      await executable.shouldExit(0);

      // Through a redirect
      executable = await TestProcess.start(d.path("out/my_app/qux$_dotBat"), [],
          workingDirectory: d.sandbox);
      expect(executable.stdout, emits("in bar"));
      await executable.shouldExit(0);

      // Through a relative symlink
      Link(d.path("foo-relative")).createSync("out/my_app/foo$_dotBat");
      executable = await TestProcess.start(d.path("foo-relative"), [],
          workingDirectory: d.sandbox);
      expect(executable.stdout, emits("in foo"));
      await executable.shouldExit(0);

      // Through an absolute symlink
      Link(d.path("foo-absolute")).createSync(d.path("out/my_app/foo$_dotBat"));
      executable = await TestProcess.start(d.path("foo-absolute"), [],
          workingDirectory: d.sandbox);
      expect(executable.stdout, emits("in foo"));
      await executable.shouldExit(0);

      // Through a nested symlink
      Link(d.path("foo-nested")).createSync(d.path("foo-relative"));
      executable = await TestProcess.start(d.path("foo-nested"), [],
          workingDirectory: d.sandbox);
      expect(executable.stdout, emits("in foo"));
      await executable.shouldExit(0);
    });
  });

  test("includes the package's license and Dart's license", () async {
    await d
        .package(
            "my_app",
            {
              "name": "my_app",
              "version": "1.2.3",
              "executables": {"foo": "foo"}
            },
            _exportStandalone,
            [d.file("LICENSE", "Please use my code")])
        .create();
    await (await grind(["pkg-standalone-$_target"])).shouldExit(0);

    await d.archive("my_app/build/my_app-1.2.3-$_archiveSuffix", [
      d.dir("my_app/src", [
        d.file("LICENSE", "Please use my code"),
        d.file("DART_LICENSE", contains("Dart project authors"))
      ])
    ]).validate();
  });

  group("creates a package for", () {
    setUp(() => d
        .package(
            "my_app",
            {
              "name": "my_app",
              "version": "1.2.3",
              "executables": {"foo": "foo"}
            },
            _exportStandalone)
        .create());

    d.Descriptor archive(String name, {bool windows = false}) =>
        d.archive(name, [
          d.dir("my_app", [
            d.file("foo${windows ? '.bat' : ''}", anything),
            d.dir("src", [
              d.file("DART_LICENSE", anything),
              d.file("dart${windows ? '.exe' : ''}", anything),
              d.file("foo.dart.snapshot", anything)
            ])
          ])
        ]);

    group("Mac OS", () {
      test("32-bit", () async {
        await (await grind(["pkg-standalone-mac-os-ia32"])).shouldExit(0);
        await archive("my_app/build/my_app-1.2.3-macos-ia32.tar.gz").validate();
      });

      test("64-bit", () async {
        await (await grind(["pkg-standalone-mac-os-x64"])).shouldExit(0);
        await archive("my_app/build/my_app-1.2.3-macos-x64.tar.gz").validate();
      });
    });

    group("Linux", () {
      test("32-bit", () async {
        await (await grind(["pkg-standalone-linux-ia32"])).shouldExit(0);
        await archive("my_app/build/my_app-1.2.3-linux-ia32.tar.gz").validate();
      });

      test("64-bit", () async {
        await (await grind(["pkg-standalone-linux-x64"])).shouldExit(0);
        await archive("my_app/build/my_app-1.2.3-linux-x64.tar.gz").validate();
      });
    });

    group("Windows", () {
      test("32-bit", () async {
        await (await grind(["pkg-standalone-windows-ia32"])).shouldExit(0);
        await archive("my_app/build/my_app-1.2.3-windows-ia32.zip",
                windows: true)
            .validate();
      });

      test("64-bit", () async {
        await (await grind(["pkg-standalone-windows-x64"])).shouldExit(0);
        await archive("my_app/build/my_app-1.2.3-windows-x64.zip",
                windows: true)
            .validate();
      });
    });

    test("all platforms", () async {
      await (await grind(["pkg-standalone-all"])).shouldExit(0);

      await Future.wait([
        archive("my_app/build/my_app-1.2.3-macos-ia32.tar.gz").validate(),
        archive("my_app/build/my_app-1.2.3-macos-x64.tar.gz").validate(),
        archive("my_app/build/my_app-1.2.3-linux-ia32.tar.gz").validate(),
        archive("my_app/build/my_app-1.2.3-linux-x64.tar.gz").validate(),
        archive("my_app/build/my_app-1.2.3-windows-ia32.zip", windows: true)
            .validate(),
        archive("my_app/build/my_app-1.2.3-windows-x64.zip", windows: true)
            .validate()
      ]);
    });
  });
}
