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
import 'package:grinder/grinder.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;
import 'package:xml/xml.dart' hide parse;

import 'info.dart';
import 'standalone.dart';
import 'template.dart';
import 'utils.dart';

/// The Chocolatey API key (available from [the Chocolatey website][] and the
/// `choco apikey` command) to use when creating releases and making other
/// changes.
///
/// [the Chocolatey website]: https://chocolatey.org/account
///
/// **Do not check this in directly.** This should only come from secure
/// sources.
///
/// By default this comes from the `CHOCOLATEY_TOKEN` environment variable.
String get chocolateyToken {
  _chocolateyToken ??= Platform.environment["CHOCOLATEY_TOKEN"];
  if (_chocolateyToken != null) return _chocolateyToken;

  fail("pkg.chocolateyToken must be set to deploy to Chocolatey.");
}

set chocolateyToken(String value) => _chocolateyToken = value;
String _chocolateyToken;

/// The package version, formatted for Chocolatey which doesn't allow dots in
/// prerelease versions.
String get _chocolateyVersion {
  var components = version.toString().split("-");
  if (components.length == 1) return components.first;
  assert(components.length == 2);

  var first = true;
  var prerelease = components.last.replaceAllMapped('.', (_) {
    if (first) {
      first = false;
      return '';
    } else {
      return '-';
    }
  });
  return "${components.first}-$prerelease";
}

/// The text contents of the Chocolatey package's [`.nuspec` file][].
///
/// [`.nuspec` file]: https://chocolatey.org/docs/create-packages#nuspec
///
/// By default, this is loaded from a file ending in `.nuspec` at the root of
/// the repository, if a single such file exists.
///
/// `cli_pkg` will automatically add a `"version"` field and a dependency on the
/// Dart SDK when building the Chocolatey package.
String get chocolateyNuspec {
  if (_chocolateyNuspec != null) return _chocolateyNuspec;

  var possibleNuspecs = [
    for (var entry in Directory(".").listSync())
      if (entry is File && entry.path.endsWith(".nuspec")) entry.path
  ];

  if (possibleNuspecs.isEmpty) {
    fail("pkg.chocolateyNuspec must be set to build a Chocolatey package.");
  } else if (possibleNuspecs.length > 1) {
    fail("pkg.chocolateyNuspec found multiple .nuspec files: " +
        possibleNuspecs.join(", "));
  }

  return File(possibleNuspecs.single).readAsStringSync();
}

set chocolateyNuspec(String value) => _chocolateyNuspec = value;
String _chocolateyNuspec;

/// Returns the XML-decoded contents of [chocolateyNuspecText], with a
/// `"version"` field and a dependency on the Dart SDK automatically added.
XmlDocument get _nuspec {
  if (__nuspec != null) return __nuspec;

  try {
    __nuspec = xml.parse(chocolateyNuspec);
  } on XmlParserException catch (error) {
    fail("Invalid nuspec: $error");
  }

  var metadata = _nuspecMetadata;
  if (metadata.findElements("version").isNotEmpty) {
    fail("The nuspec must not have a package > metadata > version element. One "
        "will be added automatically.");
  }

  metadata.children
      .add(XmlElement(XmlName("version"), [], [XmlText(_chocolateyVersion)]));

  var dependencies = _findElement(metadata, "dependencies", allowNone: true);
  if (dependencies == null) {
    dependencies = XmlElement(XmlName("dependencies"));
    metadata.children.add(dependencies);
  }

  dependencies.children.add(XmlElement(XmlName("dependency"), [
    XmlAttribute(XmlName("id"), "dart-sdk"),
    // Unfortunately we need the exact same Dart version as we built with,
    // since we ship a snapshot which isn't cross-version compatible. Once
    // we switch to native compilation this won't be an issue.
    XmlAttribute(XmlName("version"), "[$dartVersion]")
  ]));

  return __nuspec;
}

XmlDocument __nuspec;

/// The `metadata` element in [_nuspec].
XmlElement get _nuspecMetadata => _findElement(_nuspec.rootElement, "metadata");

/// The name of the Chocolatey package.
String get _chocolateyName => _findElement(_nuspecMetadata, "id").text;

/// Returns the contents of the `properties.psmdcp` file, computed from the
/// nuspec's XML.
String get _nupkgProperties {
  var metadata = _nuspecMetadata;

  var builder = XmlBuilder();
  builder.processing("xml", 'version="1.0"');
  builder.element("coreProperties", nest: () {
    builder.namespace(
        "http://schemas.openxmlformats.org/package/2006/metadata/core-properties");
    builder.namespace("http://purl.org/dc/elements/1.1/", "dc");
    builder.element("dc:creator", nest: _findElement(metadata, "authors").text);
    builder.element("dc:description",
        nest: _findElement(metadata, "description").text);
    builder.element("dc:identifier", nest: _chocolateyName);
    builder.element("version", nest: _chocolateyVersion);

    var tags = _findElement(metadata, "tags", allowNone: true);
    if (tags != null) builder.element("keywords", nest: tags.text);

    var title = _findElement(metadata, "title", allowNone: true);
    if (title != null) builder.element("dc:title", nest: title.text);
  });
  return builder.build().toString();
}

/// Whether [addChocolateyTasks] has been called yet.
var _addedChocolateyTasks = false;

/// Enables tasks for building and uploading packages to Chocolatey.
void addChocolateyTasks() {
  if (_addedChocolateyTasks) return;
  _addedChocolateyTasks = true;

  addStandaloneTasks();

  // TODO(nweiz): Rather than publishing a snapshot, publish a script that
  // downloads the tagged source and builds an executable at install-time. This
  // will ensure that 64-bit Chocolatey users get native executable performance
  // even if the package isn't built on Windows.
  addTask(GrinderTask('pkg-chocolatey-build',
      taskFunction: () => _build(),
      description: 'Build a package to upload to Chocolatey.',
      depends: ['pkg-compile-snapshot']));

  addTask(GrinderTask('pkg-chocolatey-deploy',
      taskFunction: () => _deploy(),
      description: 'Deploy the Chocolatey package to Chocolatey.',
      depends: ['pkg-chocolatey-build']));
}

/// Builds a package to upload to Chocolatey.
Future<void> _build() async {
  ensureBuild();

  var archive = Archive()
    ..addFile(fileFromString("$_chocolateyName.nuspec", _nuspec.toString()))
    ..addFile(file("[Content_Types].xml",
        p.join(await cliPkgSrc, "assets/chocolatey/[Content_Types].xml")))
    ..addFile(fileFromString("_rels/.rels",
        renderTemplate("chocolatey/rels.xml", {"name": _chocolateyName})))
    ..addFile(fileFromString(
        "package/services/metadata/core-properties/properties.psmdcp",
        _nupkgProperties));

  if (File("LICENSE").existsSync()) {
    archive.addFile(file("tools/LICENSE", "LICENSE"));
  }

  for (var entrypoint in entrypoints) {
    var snapshot = "${p.basename(entrypoint)}.snapshot";
    archive.addFile(file("tools/$snapshot", "build/$snapshot"));
  }

  var install = StringBuffer();
  var uninstall = StringBuffer();
  executables.forEach((name, path) {
    // Write PoewrShell code to install/uninstall each batch script. Note that
    // `$packageFolder` here is a PowerShell variable, not a Dart variable.
    var args = '"$name" "\$packageFolder\\tools\\$name.bat"';
    install.writeln("Generate-BinFile $args");
    uninstall.writeln("Remove-BinFile $args");

    archive.addFile(fileFromString(
        "tools/$name.bat",
        renderTemplate("chocolatey/executable.bat", {
          "name": _chocolateyName,
          "version": version.toString(),
          "executable": p.basename(path)
        }),
        executable: true));
  });

  archive.addFile(
      fileFromString("tools/chocolateyInstall.ps1", install.toString()));
  archive.addFile(
      fileFromString("tools/chocolateyUninstall.ps1", uninstall.toString()));

  writeBytes("build/$_chocolateyName.$_chocolateyVersion.nupkg",
      ZipEncoder().encode(archive));
}

// Deploy the Chocolatey package to Chocolatey.
Future<void> _deploy() async {
  // For some reason, although Chrome is able to access it just fine,
  // command-line tools don't seem to be able to verify the certificate for
  // Chocolatey, so we need to manually add the intermediate GoDaddy certificate
  // to the security context.
  SecurityContext.defaultContext.setTrustedCertificates(
      p.join(await cliPkgSrc, "assets/chocolatey/godaddy.pem"));

  var request = http.MultipartRequest(
      "PUT", url("https://chocolatey.org/api/v2/package"));
  request.headers["X-NuGet-Protocol-Version"] = "4.1.0";
  request.headers["X-NuGet-ApiKey"] = chocolateyToken;
  request.files.add(await http.MultipartFile.fromPath(
      "package", "build/$_chocolateyName.$_chocolateyVersion.nupkg"));

  var response = await request.send();
  if (response.statusCode ~/ 100 != 2) {
    fail("${response.statusCode} error creating release:\n"
        "${await response.stream.bytesToString()}");
  } else {
    log("Released $_chocolateyName $_chocolateyVersion to Chocolatey.");
    await response.stream.listen(null).cancel();
  }
}

/// Returns the single child of [parent] named [name], or throws an error.
///
/// If [allowNone] is `true`, this returns `null` if there are no children of
/// [parent] named [name]. Otherwise, it throws an error.
XmlElement _findElement(XmlParent parent, String name,
    {bool allowNone = false}) {
  var elements = parent.findElements(name);
  if (elements.length == 1) return elements.single;
  if (allowNone && elements.isEmpty) return null;

  var nesting = [name];
  while (parent is XmlElement) {
    nesting.add((parent as XmlElement).name.qualified);
    parent = parent.parent as XmlParent; // renggli/dart-xml#63
  }

  var path = nesting.reversed.join(" > ");
  fail(elements.isEmpty
      ? "The nuspec must have a $path element."
      : "The nuspec may not have multiple $path elements.");
}
