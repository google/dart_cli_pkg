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

import 'package:grinder/grinder.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' hide parse;

import 'config_variable.dart';
import 'info.dart';
import 'standalone.dart';
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
final chocolateyToken = InternalConfigVariable.fn<String>(() =>
    Platform.environment["CHOCOLATEY_TOKEN"] ??
    fail("pkg.chocolateyToken must be set to deploy to Chocolatey."));

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

/// The version of the Dart SDK, formatted for Chocolatey which doesn't allow
/// dots in prerelease versions.
///
/// The Dart SDK doesn't use the same logic for Chocolatifying pre-release
/// versions that Sass does. Instead it transforms `A.B.C-X.Y-dev` into
/// `A.B.C.X-c-Y.dev`.
@visibleForTesting
String get chocolateyDartVersion {
  if (!dartVersion.isPreRelease) return dartVersion.toString();

  var result = StringBuffer(
      "${dartVersion.major}.${dartVersion.minor}.${dartVersion.patch}");

  var prerelease = List.of(dartVersion.preRelease);
  if (prerelease.first is int) {
    // New style of version for Dart prereleases >=2.9 (e.g. 2.9.0-9.0.dev)
    var major = prerelease.first;
    var minor = prerelease[1].toString();
    var type = prerelease[2];
    result.write('.$major-c-${"0" * (3 - minor.length)}$minor-$type');
  } else {
    // Old style of version for Dart prereleases <2.9 (e.g. 2.8.0-dev.20.0)
    var firstInt = prerelease.indexWhere((value) => value is int);
    if (firstInt != -1) result.write(".${prerelease.removeAt(firstInt)}");
    result.write("-${prerelease.join('-')}");
  }
  return result.toString();
}

/// The set of files to include directly in the Chocolatey package.
///
/// This should be at least enough files to compile the package's executables.
/// It defaults to all files in `lib/` and `bin/`, as well as `pubspec.lock`.
///
/// The `pubspec.yaml` file is always included regardless of the contents of
/// this field.
final chocolateyFiles = InternalConfigVariable.fn<List<String>>(() => [
      ...['lib', 'bin']
          .where((dir) => Directory(dir).existsSync())
          .expand((dir) => Directory(dir).listSync(recursive: true))
          .whereType<File>()
          .map((entry) => entry.path),
      'pubspec.lock'
    ]);

/// The text contents of the Chocolatey package's [`.nuspec` file][].
///
/// [`.nuspec` file]: https://chocolatey.org/docs/create-packages#nuspec
///
/// By default, this is loaded from a file ending in `.nuspec` at the root of
/// the repository, if a single such file exists.
///
/// `cli_pkg` will automatically add a `"version"` field and a dependency on the
/// Dart SDK when building the Chocolatey package.
final chocolateyNuspec = InternalConfigVariable.fn<String>(() {
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
});

// TODO: late
/// Returns the XML-decoded contents of [chocolateyNuspecText], with a
/// `"version"` field and a dependency on the Dart SDK automatically added.
XmlDocument get _nuspec {
  if (__nuspec != null) return __nuspec;

  try {
    __nuspec = XmlDocument.parse(chocolateyNuspec.value);
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

  var dependencies = _findElementAllowNone(metadata, "dependencies");
  if (dependencies == null) {
    dependencies = XmlElement(XmlName("dependencies"));
    metadata.children.add(dependencies);
  }

  dependencies.children.add(XmlElement(XmlName("dependency"), [
    XmlAttribute(XmlName("id"), "dart-sdk"),
    // Unfortunately we need the exact same Dart version as we built with,
    // since we ship a snapshot which isn't cross-version compatible. Once
    // we switch to native compilation this won't be an issue.
    XmlAttribute(XmlName("version"), "[$chocolateyDartVersion]")
  ]));

  return __nuspec;
}

XmlDocument __nuspec;

/// The `metadata` element in [_nuspec].
XmlElement get _nuspecMetadata => _findElement(_nuspec.rootElement, "metadata");

/// The name of the Chocolatey package.
String get _chocolateyName => _findElement(_nuspecMetadata, "id").text;

/// Whether [addChocolateyTasks] has been called yet.
var _addedChocolateyTasks = false;

/// Enables tasks for building and uploading packages to Chocolatey.
void addChocolateyTasks() {
  if (_addedChocolateyTasks) return;
  _addedChocolateyTasks = true;

  freezeSharedVariables();
  chocolateyToken.freeze();
  chocolateyFiles.freeze();
  chocolateyNuspec.freeze();

  addStandaloneTasks();

  addTask(GrinderTask('pkg-chocolatey',
      taskFunction: () => _build(),
      description: 'Build a Chocolatey package directory.'));

  addTask(GrinderTask('pkg-chocolatey-pack',
      taskFunction: () => _nupkg(),
      description: 'Build a nupkg archive to upload to Chocolatey.',
      depends: ['pkg-chocolatey']));

  addTask(GrinderTask('pkg-chocolatey-deploy',
      taskFunction: () => _deploy(),
      description: 'Deploy the Chocolatey package to Chocolatey.',
      depends: ['pkg-chocolatey-pack']));
}

/// Builds a package to upload to Chocolatey.
Future<void> _build() async {
  ensureBuild();

  var dir = Directory('build/chocolatey');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);

  writeString("build/chocolatey/$_chocolateyName.nuspec", _nuspec.toString());
  Directory("build/chocolatey/tools/source").createSync(recursive: true);

  writeString("build/chocolatey/tools/LICENSE", await license);

  writeString(
      'build/chocolatey/tools/source/pubspec.yaml',
      json.encode(Map.of(rawPubspec)
        ..remove('dev_dependencies')
        ..remove('dependency_overrides')));

  for (var path in chocolateyFiles.value) {
    var relative = p.relative(path);
    if (relative == 'pubspec.yaml') continue;

    safeCopy(
        relative, p.join('build/chocolatey/tools/source', p.dirname(path)));
  }

  var install = StringBuffer("""
\$ToolsDir = (Split-Path -parent \$MyInvocation.MyCommand.Definition)
Write-Host "Fetching Dart dependencies..."
\$SourceDir = "\$ToolsDir\\source"
Push-Location -Path \$SourceDir
pub get --no-precompile | Out-Null
Pop-Location

New-Item -Path \$PackageFolder -Name "bin" -ItemType "directory" | Out-Null
Write-Host "Building executable${executables.value.length == 1 ? '' : 's'}..."
""");
  var uninstall = StringBuffer();
  executables.value.forEach((name, path) {
    install.write("""
\$ExePath = "\$PackageFolder\\bin\\$name.exe"
dart2native "-Dversion=$version" "\$SourceDir\\$path" -o \$ExePath
Generate-BinFile "$name" \$ExePath
""");
    uninstall
        .writeln('Remove-BinFile "$name" "\$PackageFolder\\bin\\$name.exe"');
  });

  writeString(
      "build/chocolatey/tools/chocolateyInstall.ps1", install.toString());
  writeString(
      "build/chocolatey/tools/chocolateyUninstall.ps1", uninstall.toString());
}

/// Builds a nupkg file to deploy to chocolatey.
Future<void> _nupkg() async {
  await runAsync("choco",
      arguments: [
        "pack",
        "--yes",
        "build/chocolatey/$_chocolateyName.nuspec",
        "--out=build"
      ],
      quiet: false);
}

/// Deploys the Chocolatey package to Chocolatey.
Future<void> _deploy() async {
  var nupkgPath = p.join("build", "$_chocolateyName.$_chocolateyVersion.nupkg");
  log("choco push --source https://chocolatey.org --key=... $nupkgPath");
  var process = await Process.start("choco", [
    "push",
    nupkgPath,
    "--source",
    "https://chocolatey.org",
    "--key",
    "$chocolateyToken"
  ]);
  LineSplitter().bind(utf8.decoder.bind(process.stdout)).listen(log);
  LineSplitter().bind(utf8.decoder.bind(process.stderr)).listen(log);
  if (await process.exitCode != 0) fail("choco push failed");
}

/// Returns the single child of [parent] named [name], or throws an error.
XmlElement _findElement(XmlNode parent, String name) {
  var elements = parent.findElements(name);
  if (elements.length == 1) return elements.single;

  var path = _pathToElement(parent, name);
  fail(elements.isEmpty
      ? "The nuspec must have a $path element."
      : "The nuspec may not have multiple $path elements.");
}

/// Like [findElement], but returns `null` if there are no children of [parent]
/// named [name].
XmlElement _findElementAllowNone(XmlNode parent, String name) {
  var elements = parent.findElements(name);
  if (elements.length == 1) return elements.single;
  if (elements.isEmpty) return null;

  var path = _pathToElement(parent, name);
  fail("The nuspec may not have multiple $path elements.");
}

/// Returns a human-readable CSS-formatted path to the element named [name]
/// within [parent].
String _pathToElement(XmlNode/*!*/ parent, String name) {
  var nesting = [name];
  while (parent is XmlElement) {
    nesting.add((parent as XmlElement).name.qualified);
    parent = parent.parent;
  }

  return nesting.reversed.join(" > ");
}
