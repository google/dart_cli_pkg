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

import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:test_process/test_process.dart';
import 'package:xml/xml.dart' hide parse;

import 'package:cli_pkg/src/chocolatey.dart';
import 'package:cli_pkg/src/utils.dart';

import 'descriptor.dart' as d;
import 'utils.dart';

void main() {
  var pubspec = {
    "name": "my_app",
    "version": "1.2.3",
    "executables": {"foo": "foo", "bar": "baz"}
  };

  group("version", () {
    Future<void> assertVersion(String original, String expected) async {
      await d
          .package({...pubspec, "version": original}, _enableChocolatey(),
              [_nuspec()])
          .create();

      await (await grind(["pkg-chocolatey"])).shouldExit(0);

      // `d.archive` requires a file with a known extension.
      await d
          .file("my_app/build/chocolatey/my_app_choco.nuspec",
              contains("<version>$expected</version>"))
          .validate();
    }

    test("is unchanged for release versions",
        () => assertVersion("1.2.3", "1.2.3"));

    test("is unchanged for prerelease versions without dots",
        () => assertVersion("1.2.3-beta", "1.2.3-beta"));

    test("removes the first dot in a prerelease version",
        () => assertVersion("1.2.3-beta.5", "1.2.3-beta5"));

    test("converts further dots in prerelease versions to dashes",
        () => assertVersion("1.2.3-beta.5.six.7", "1.2.3-beta5-six-7"));
  });

  group("in the package", () {
    group("nuspec", () {
      group("throws an error if", () {
        Future<void> assertNuspecError(
            String nuspec, String errorFragment) async {
          await d.package(pubspec, _enableChocolatey(),
              [d.file("my_app_choco.nuspec", nuspec)]).create();

          var grinder = await grind(["pkg-chocolatey"]);
          expect(grinder.stdout, emitsThrough(contains(errorFragment)));
          await grinder.shouldExit(1);
        }

        test("it's invalid XML",
            () => assertNuspecError("<package>", "Invalid nuspec: "));

        test("it's empty", () => assertNuspecError("", "Invalid nuspec: "));

        test(
            "it doesn't contain a <metadata>",
            () => assertNuspecError("<package></package>",
                "The nuspec must have a package > metadata element."));

        test(
            "it contains multiple <metadata>s",
            () => assertNuspecError(
                "<package><metadata></metadata><metadata></metadata></package>",
                "The nuspec may not have multiple package > metadata elements."));

        test(
            "it contains a <version>",
            () => assertNuspecError(
                "<package><metadata><version>1.2.3</version></metadata></package>",
                "The nuspec must not have a package > metadata > version "
                    "element. One will be added automatically."));

        test(
            "it contains multiple <dependencies>s",
            () => assertNuspecError(
                """
                <package>
                  <metadata>
                    <dependencies></dependencies>
                    <dependencies></dependencies>
                  </metadata>
                </package>
              """,
                "The nuspec may not have multiple package > metadata > "
                    "dependencies elements."));
      });

      test("adds <version> and a dependency on the Dart SDK", () async {
        await d.package(pubspec, _enableChocolatey(), [_nuspec()]).create();

        await (await grind(["pkg-chocolatey"])).shouldExit(0);

        await d
            .file("my_app/build/chocolatey/my_app_choco.nuspec", _equalsXml("""
            <?xml version="1.0" encoding="utf-8"?>
            <package
                xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
              <metadata>
                <id>my_app_choco</id>
                <description>A good app</description>
                <authors>Natalie Weizenbaum</authors>
                <version>1.2.3</version>
                <dependencies>
                  <dependency id="dart-sdk" version="[$chocolateyDartVersion]"/>
                </dependencies>
              </metadata>
            </package>
          """))
            .validate();
      });

      test("adds a dependency on the Dart SDK to existing dependencies",
          () async {
        await d.package(pubspec, _enableChocolatey(), [
          _nuspec("""
            <dependencies>
              <dependency id="something" version="[1.2.3]"/>
            </dependencies>
          """)
        ]).create();

        await (await grind(["pkg-chocolatey"])).shouldExit(0);

        await d
            .file("my_app/build/chocolatey/my_app_choco.nuspec", _equalsXml("""
          <?xml version="1.0" encoding="utf-8"?>
          <package
              xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
            <metadata>
              <id>my_app_choco</id>
              <description>A good app</description>
              <authors>Natalie Weizenbaum</authors>
              <dependencies>
                <dependency id="something" version="[1.2.3]"/>
                <dependency id="dart-sdk" version="[$chocolateyDartVersion]"/>
              </dependencies>
              <version>1.2.3</version>
            </metadata>
          </package>
        """))
            .validate();
      });
    });

    group("the LICENSE file", () {
      // Normally each of these would be separate test cases, but running
      // grinder takes so long that we collapse them for efficiency.
      test(
          "includes the license for the package, Dart, direct dependencies, "
          "and transitive dependencies", () async {
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
                _enableChocolatey(),
                [_nuspec(), d.file("LICENSE", "Please use my code")])
            .create();
        await (await grind(["pkg-chocolatey"])).shouldExit(0);

        await d
            .file(
                "my_app/build/chocolatey/tools/LICENSE",
                allOf([
                  contains("Please use my code"),
                  contains("Copyright 2012, the Dart project authors."),
                  contains("Direct dependency license"),
                  contains("Indirect dependency license")
                ]))
            .validate();
      });

      test("is still generated if the package doesn't have a license",
          () async {
        await d.package(pubspec, _enableChocolatey(), [_nuspec()]).create();
        await (await grind(["pkg-chocolatey"])).shouldExit(0);

        await d
            .file("my_app/build/chocolatey/tools/LICENSE",
                contains("Copyright 2012, the Dart project authors."))
            .validate();
      });
    });

    test("includes an installation script", () async {
      await d.package(pubspec, _enableChocolatey(), [_nuspec()]).create();

      await (await grind(["pkg-chocolatey"])).shouldExit(0);

      await d
          .file(
              "my_app/build/chocolatey/tools/chocolateyInstall.ps1",
              allOf([
                contains(r'Generate-BinFile "foo" $ExePath'),
                contains(r'Generate-BinFile "bar" $ExePath')
              ]))
          .validate();
    });

    test("includes an uninstallation script", () async {
      await d.package(pubspec, _enableChocolatey(), [_nuspec()]).create();

      await (await grind(["pkg-chocolatey"])).shouldExit(0);

      await d
          .file(
              "my_app/build/chocolatey/tools/chocolateyUninstall.ps1",
              allOf([
                contains(r'Remove-BinFile "foo" "$PackageFolder\bin\foo.exe"'),
                contains(r'Remove-BinFile "bar" "$PackageFolder\bin\bar.exe"')
              ]))
          .validate();
    });
  });

  // Note: this test requires an administrative shell to run.
  test("can be installed and run", () async {
    // Chocolatey doesn't allow release versions to depend on pre-release
    // versions.
    var version = dartVersion.isPreRelease ? "1.2.3-beta" : "1.2.3";
    await d
        .package(
            {...pubspec, "version": version}, _enableChocolatey(), [_nuspec()])
        .create();

    await (await grind(["pkg-chocolatey-pack"])).shouldExit(0);

    await (await TestProcess.start("choco", [
      "install",
      // We already have Dart installed, and sometimes this fails to find it.
      "--ignore-dependencies",
      d.path("my_app/build/my_app_choco.$version.nupkg")
    ]))
        .shouldExit(0);

    var foo = await TestProcess.start("foo", []);
    expect(foo.stdout, emits("in foo $version"));
    await foo.shouldExit(0);

    var bar = await TestProcess.start("bar", []);
    expect(bar.stdout, emits("in baz $version"));
    await bar.shouldExit(0);
  }, testOn: "windows");
}

/// The contents of a `grind.dart` file that just enables Chocolatey tasks.
///
/// If [token] is `true`, this sets a default value for `pkg.chocolateyToken`.
String _enableChocolatey({bool token = true}) {
  var buffer = StringBuffer("""
    void main(List<String> args) {
  """);

  if (token) buffer.writeln('pkg.chocolateyToken.value = "tkn";');
  buffer.writeln("pkg.addChocolateyTasks();");
  buffer.writeln("grind(args);");
  buffer.writeln("}");

  return buffer.toString();
}

/// Returns a [d.FileDescriptor] describing a basic `nuspec` file.
///
/// If [extraMetadata] is passed, it's added to the nuspec's `<metadata>`tag.

d.FileDescriptor _nuspec([String? extraMetadata]) {
  return d.file("my_app_choco.nuspec", """
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
  <metadata>
    <id>my_app_choco</id>
    <description>A good app</description>
    <authors>Natalie Weizenbaum</authors>
    ${extraMetadata ?? ""}
  </metadata>
</package>
""");
}

/// A [Matcher] that asserts that a string has the same XML structure as
/// [expected], ignoring whitespace.
Matcher _equalsXml(String expected) => predicate((dynamic actual) {
      expect(actual, isA<String>());
      expect(XmlDocument.parse(actual as String).toXmlString(pretty: true),
          equals(XmlDocument.parse(expected).toXmlString(pretty: true)));
      return true;
    });
