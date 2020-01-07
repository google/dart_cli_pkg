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
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_test_handler/shelf_test_handler.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';
import 'package:xml/xml.dart' as xml;

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

      await (await grind(["pkg-chocolatey-build"])).shouldExit(0);

      var path = [
        for (var entry in Directory(d.path("my_app/build/")).listSync())
          if (entry.path.endsWith(".nupkg")) entry.path
      ].single;

      expect(p.basename(path), equals("my_app_choco.$expected.nupkg"));

      // `d.archive` requires a file with a known extension.
      await _nupkg(path, [
        d.file("my_app_choco.nuspec", contains("<version>$expected</version>"))
      ]).validate();
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

  group("in the nupkg", () {
    group("nuspec", () {
      group("throws an error if", () {
        Future<void> assertNuspecError(
            String nuspec, String errorFragment) async {
          await d.package(pubspec, _enableChocolatey(),
              [d.file("my_app_choco.nuspec", nuspec)]).create();

          var grinder = await grind(["pkg-chocolatey-build"]);
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

        await (await grind(["pkg-chocolatey-build"])).shouldExit(0);

        await _nupkg("my_app/build/my_app_choco.1.2.3.nupkg", [
          d.file("my_app_choco.nuspec", _equalsXml("""
            <?xml version="1.0" encoding="utf-8"?>
            <package
                xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
              <metadata>
                <id>my_app_choco</id>
                <description>A good app</description>
                <authors>Natalie Weizenbaum</authors>
                <version>1.2.3</version>
                <dependencies>
                  <dependency id="dart-sdk" version="[$dartVersion]"/>
                </dependencies>
              </metadata>
            </package>
          """))
        ]).validate();
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

        await (await grind(["pkg-chocolatey-build"])).shouldExit(0);

        await _nupkg("my_app/build/my_app_choco.1.2.3.nupkg", [
          d.file("my_app_choco.nuspec", _equalsXml("""
          <?xml version="1.0" encoding="utf-8"?>
          <package
              xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
            <metadata>
              <id>my_app_choco</id>
              <description>A good app</description>
              <authors>Natalie Weizenbaum</authors>
              <dependencies>
                <dependency id="something" version="[1.2.3]"/>
                <dependency id="dart-sdk" version="[$dartVersion]"/>
              </dependencies>
              <version>1.2.3</version>
            </metadata>
          </package>
        """))
        ]).validate();
      });
    });

    test("[Content_Types] is copied in", () async {
      await d.package(pubspec, _enableChocolatey(), [_nuspec()]).create();

      await (await grind(["pkg-chocolatey-build"])).shouldExit(0);

      await _nupkg("my_app/build/my_app_choco.1.2.3.nupkg", [
        // No reason to duplicate the entire asset here, so we just test for a
        // distinctive substring.
        d.file(
            "[Content_Types].xml",
            contains(
                "http://schemas.openxmlformats.org/package/2006/content-types"))
      ]);
    });

    test(".rels.xml is copied in", () async {
      await d.package(pubspec, _enableChocolatey(), [_nuspec()]).create();

      await (await grind(["pkg-chocolatey-build"])).shouldExit(0);

      await _nupkg("my_app/build/my_app_choco.1.2.3.nupkg", [
        d.file("_rels/.rels.xml", contains('Target="/my_app_choco.nuspec"'))
      ]);
    });

    group("properties.psmdcp", () {
      test("is created from required nuspec entries", () async {
        await d.package(pubspec, _enableChocolatey(), [_nuspec()]).create();

        await (await grind(["pkg-chocolatey-build"])).shouldExit(0);

        await _nupkg("my_app/build/my_app_choco.1.2.3.nupkg", [
          d.file("package/services/metadata/core-properties/properties.psmdcp",
              _equalsXml("""
                <?xml version="1.0">
                <coreProperties
                    xmlns="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
                    dc="http://purl.org/dc/elements/1.1/">
                  <dc:creator>Natalie Weizenbaum</dc:creator>
                  <dc:description>A good app</dc:description>
                  <dc:identifier>my_app_choco</dc:identifier>
                  <version>1.2.3</version>
                </coreProperties>
              """))
        ]);
      });

      test("gets extra information from <tags>", () async {
        await d.package(pubspec, _enableChocolatey(),
            [_nuspec("<tags>foo, bar, baz</tags>")]).create();

        await (await grind(["pkg-chocolatey-build"])).shouldExit(0);

        await _nupkg("my_app/build/my_app_choco.1.2.3.nupkg", [
          d.file("package/services/metadata/core-properties/properties.psmdcp",
              contains("<keywords>foo, bar, baz</keywords>"))
        ]);
      });

      test("gets extra information from <title>", () async {
        await d.package(pubspec, _enableChocolatey(),
            [_nuspec("<title>My App</title>")]).create();

        await (await grind(["pkg-chocolatey-build"])).shouldExit(0);

        await _nupkg("my_app/build/my_app_choco.1.2.3.nupkg", [
          d.file("package/services/metadata/core-properties/properties.psmdcp",
              contains("<dc:title>My App</title>"))
        ]);
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
        await (await grind(["pkg-chocolatey-build"])).shouldExit(0);

        await _nupkg("my_app/build/my_app_choco.1.2.3.nupkg", [
          d.file(
              "tools/LICENSE",
              allOf([
                contains("Please use my code"),
                contains("Copyright 2012, the Dart project authors."),
                contains("Direct dependency license"),
                contains("Indirect dependency license")
              ]))
        ]).validate();
      });

      test("is still generated if the package doesn't have a license",
          () async {
        await d.package(pubspec, _enableChocolatey(), [_nuspec()]).create();
        await (await grind(["pkg-chocolatey-build"])).shouldExit(0);

        await _nupkg("my_app/build/my_app_choco.1.2.3.nupkg", [
          d.file("tools/LICENSE",
              contains("Copyright 2012, the Dart project authors."))
        ]).validate();
      });
    });

    test("includes an installation script", () async {
      await d.package(pubspec, _enableChocolatey(), [_nuspec()]).create();

      await (await grind(["pkg-chocolatey-build"])).shouldExit(0);

      await _nupkg("my_app/build/my_app_choco.1.2.3.nupkg", [
        d.file(
            "tools/chocolateyInstall.ps1",
            allOf([
              contains(
                  r'Generate-BinFile "foo" "$packageFolder\tools\foo.bat"'),
              contains(r'Generate-BinFile "bar" "$packageFolder\tools\bar.bat"')
            ]))
      ]).validate();
    });

    test("includes an uninstallation script", () async {
      await d.package(pubspec, _enableChocolatey(), [_nuspec()]).create();

      await (await grind(["pkg-chocolatey-build"])).shouldExit(0);

      await _nupkg("my_app/build/my_app_choco.1.2.3.nupkg", [
        d.file(
            "tools/chocolateyUninstall.ps1",
            allOf([
              contains(r'Remove-BinFile "foo" "$packageFolder\tools\foo.bat"'),
              contains(r'Remove-BinFile "bar" "$packageFolder\tools\bar.bat"')
            ]))
      ]).validate();
    });

    test("includes executables that can be invoked", () async {
      await d.package(pubspec, _enableChocolatey(), [_nuspec()]).create();

      await (await grind(["pkg-chocolatey-build"])).shouldExit(0);
      await extract("my_app/build/my_app_choco.1.2.3.nupkg", "out");

      var executable = await TestProcess.start(d.path("out/tools/foo.bat"), [],
          workingDirectory: d.sandbox);
      expect(executable.stdout, emits("in foo 1.2.3"));
      await executable.shouldExit(0);
    }, testOn: "windows");
  });

  group("token", () {
    Future<void> assertToken(String expected,
        {Map<String, String> environment}) async {
      await _deploy(
          verify: (request) {
            expect(request.headers, containsPair("X-NuGet-ApiKey", expected));
          },
          environment: environment);
    }

    test("throws an error if it's not set anywhere", () async {
      await d.package(
          pubspec, _enableChocolatey(token: false), [_nuspec()]).create();

      var process = await grind(["pkg-chocolatey-deploy"]);
      expect(
          process.stdout,
          emitsThrough(contains(
              "pkg.chocolateyToken must be set to deploy to Chocolatey.")));
      await process.shouldExit(1);
    });

    test("parses from the CHOCOLATEY_TOKEN environment variable", () async {
      await d.package(
          pubspec, _enableChocolatey(token: false), [_nuspec()]).create();
      await assertToken("secret", environment: {"CHOCOLATEY_TOKEN": "secret"});
    });

    test(
        "prefers an explicit username to the CHOCOLATEY_TOKEN environment variable",
        () async {
      await d.package(pubspec, _enableChocolatey(), [_nuspec()]).create();
      await assertToken("tkn", environment: {"CHOCOLATEY_TOKEN": "wrong"});
    });
  });

  // TODO(nweiz): Test the contents of package uploads when dart-lang/shelf#119
  // is fixed.
}

/// The contents of a `grind.dart` file that just enables Chocolatey tasks.
///
/// If [token] is `true`, this sets a default value for `pkg.chocolateyToken`.
String _enableChocolatey({bool token = true}) {
  var buffer = StringBuffer("""
    void main(List<String> args) {
  """);

  if (token) buffer.writeln('pkg.chocolateyToken = "tkn";');
  buffer.writeln("pkg.addChocolateyTasks();");
  buffer.writeln("grind(args);");
  buffer.writeln("}");

  return buffer.toString();
}

/// Returns a [d.FileDescriptor] describing a basic `nuspec` file.
///
/// If [extraMetadata] is passed, it's added to the nuspec's `<metadata>`tag.

d.FileDescriptor _nuspec([String extraMetadata]) {
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

/// Like [d.archiveDescriptor], but works even though [name] has the extension
/// `.nupkg`.
///
/// Can only be used to validate a file.
d.ArchiveDescriptor _nupkg(String name, Iterable<d.Descriptor> contents) {
  var fullPath = d.path(name);
  var zipName = p.withoutExtension(fullPath) + ".zip";
  File(fullPath).copySync(zipName);
  return d.archive(zipName, contents);
}

/// A [Matcher] that asserts that a string has the same XML structure as
/// [expected], ignoring whitespace.
Matcher _equalsXml(String expected) => predicate((actual) {
      expect(actual, isA<String>());
      expect(xml.parse(actual as String).toXmlString(pretty: true),
          equals(xml.parse(expected).toXmlString(pretty: true)));
      return true;
    });

/// Runs the deployment process, asserts that a PUT is made to the correct URL,
/// passes that PUT request to [verify], and returns a 201 CREATED response.
Future<void> _deploy(
    {FutureOr<void> verify(shelf.Request request),
    Map<String, String> environment}) async {
  var server = await ShelfTestServer.create();
  server.handler.expect("PUT", "/api/v2/package", expectAsync1((request) async {
    if (verify != null) await verify(request);
    return shelf.Response(201);
  }));

  var grinder = await grind(["pkg-chocolatey-deploy"],
      server: server, environment: environment);
  await grinder.shouldExit(0);
  await server.close();
}
