// Copyright 2019 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:convert';
import 'dart:io';

import 'package:grinder/grinder.dart';
import 'package:meta/meta.dart';
import 'package:node_preamble/preamble.dart' as preamble;
import 'package:path/path.dart' as p;

import 'info.dart';
import 'utils.dart';

/// A modifiable list of additional flags to pass to `dart2js` when compiling
/// executables.
var jsFlags = <String>[];

/// A modifiable list of flags to pass to `dart2js` only when compiling
/// executables in development mode.
var jsDevFlags = <String>[];

/// A modifiable list of flags to pass to `dart2js` only when compiling
/// executables in release mode.
///
/// By default, this contains `-O4`, `--no-minify`, and `--fast-startup`. This
/// doesn't minify by default because download size isn't especially important
/// server-side and it's nice to get readable stack traces from bug reports.
var jsReleaseFlags = ["-O4", "--no-minify", "--fast-startup"];

/// A modifiable map of JavaScript packages to `require()` at the beginning of
/// the generated JS file.
///
/// Each map value is the string to pass to `require()`, and its corresponding
/// key is the name of the global variable to which to assign the resulting
/// module.
///
/// For example, `jsRequires["sass"] = "dart-sass"` would produce `self.sass =
/// require("dart-sass")`.
///
/// If an executable passes a literal string to `require()` through Dart's JS
/// interop, that's automatically converted to a `require()` at the beginning of
/// the generated JS file.
var jsRequires = <String, String>{};

/// The path to a Dart library whose `main()` method will be called when the
/// compiled JavaScript module is loaded.
///
/// All the package's executables are compiled into a single JS file. The
/// `main()` method of the given library will be invoked when that JS file is
/// first imported. It should take no arguments.
///
/// This is most commonly used to export functions so that the npm package is
/// usable as a JS library. For example, to export a `sayHello()` function, this
/// library might look like:
///
/// ```dart
/// import 'package:js/js.dart';
///
/// @JS()
/// class _Exports {
///   external set sayHello(function);
/// }
///
/// @JS()
/// external get _Exports exports;
///
/// void main() {
///   exports.sayHello = allowInterop(() => print("Hello, world!"));
/// }
/// ```
///
/// This path is relative to the root of the package. It defaults to `null`,
/// which means no user-defined code will run when the module is loaded.
String jsModuleMainLibrary;

/// The decoded contents of the npm package's `package.json` file.
///
/// By default, this is loaded from `package.json` at the root of the
/// repository. It's modifiable.
///
/// `cli_pkg` will automatically add `"version"` and `"bin"` fields when
/// building the `npm` package. If [jsModuleMainLibrary] is set, it will also
/// add a `"main"` field.
Map<String, Object> get npmPackageJson {
  if (_npmPackageJson != null) return _npmPackageJson;
  if (!File("package.json").existsSync()) {
    fail("pkg.npmPackageJson must be set to build an npm package.");
  }

  _npmPackageJson = jsonDecode(File("package.json").readAsStringSync())
      as Map<String, Object>;
  return _npmPackageJson;
}

set npmPackageJson(Map<String, Object> value) => _npmPackageJson = value;
Map<String, Object> _npmPackageJson;

/// The name of the npm package, from `package.json`.
String get _npmName {
  var name = npmPackageJson["name"];
  if (name is String) return name;

  if (name == null) fail("package.json must have a name field.");
  fail("package.json's name field must be a string.");
}

/// The Markdown-formatted text of the README to include in the npm package.
///
/// By default, this loads the contents of the `README.md` file at the root of
/// the repository.
String get npmReadme {
  if (_npmReadme != null) return _npmReadme;
  if (!File("README.md").existsSync()) return null;

  _npmReadme = File("README.md").readAsStringSync();
  return _npmReadme;
}

set npmReadme(String value) => _npmReadme = value;
String _npmReadme;

/// The npm [authentication token][] to use when creating releases and making
/// other changes.
///
/// [authentication token]: https://docs.npmjs.com/about-authentication-tokens
///
/// **Do not check this in directly.** This should only come from secure
/// sources.
///
/// By default this comes from the `NPM_TOKEN` environment variable.
String get npmToken {
  _npmToken ??= Platform.environment["NPM_TOKEN"];
  if (_npmToken != null) return _npmToken;

  fail("pkg.npmToken must be set to deploy to npm.");
}

set npmToken(String value) => _npmToken = value;
String _npmToken;

/// Whether [addNpmTasks] has been called yet.
var _addedNpmTasks = false;

/// Enables tasks for building packages for npm.
void addNpmTasks() {
  if (_addedNpmTasks) return;
  _addedNpmTasks = true;

  addTask(GrinderTask('pkg-js-dev',
      taskFunction: () => _js(release: false),
      description: 'Compile executable(s) to JS in dev mode.'));

  addTask(GrinderTask('pkg-js-release',
      taskFunction: () => _js(release: true),
      description: 'Compile executable(s) to JS in release mode.'));

  addTask(GrinderTask('pkg-npm-dev',
      taskFunction: () => _buildPackage(),
      description: 'Build a pure-JS dev-mode package.',
      depends: ['pkg-js-dev']));

  addTask(GrinderTask('pkg-npm-release',
      taskFunction: () => _buildPackage(),
      description: 'Build a pure-JS release-mode package.',
      depends: ['pkg-js-release']));

  addTask(GrinderTask('pkg-npm-deploy',
      taskFunction: () => _deploy(),
      description: 'Deploy the release-mode JS package to npm.',
      depends: ['pkg-npm-release']));
}

/// Compiles the package to JavaScript.
///
/// If [release] is `true`, this compiles with [jsReleaseFlags]. Otherwise it
/// compiles with [jsDevFlags].
void _js({@required bool release}) {
  ensureBuild();

  var source = File("build/${_npmName}_npm.dart");
  source.writeAsStringSync(_wrapperLibrary);

  var destination = File('build/$_npmName.dart.js');

  Dart2js.compile(source, outFile: destination, extraArgs: [
    '--server-mode',
    '-Dnode=true',
    '-Dversion=$version',
    '-Ddart-version=$dartVersion',
    ...jsFlags,
    if (release) ...jsReleaseFlags else ...jsDevFlags
  ]);

  // If the code invokes `require()`, convert that to a pre-load to avoid
  // Webpack complaining about dynamic `require()`.
  var requires = Map.of(jsRequires);
  var text = destination.readAsStringSync()
      // Some dependencies dynamically invoke `require()`, which makes Webpack
      // complain. We replace those with direct references to the modules, which
      // we load explicitly after the preamble.
      .replaceAllMapped(RegExp(r'self\.require\(("[^"]+")\)'), (match) {
    var package = jsonDecode(match[1]) as String;
    var identifier = requires.entries
        .firstWhere((entry) => entry.value == package, orElse: () => null)
        ?.key;

    if (identifier == null) {
      identifier = _packageNameToIdentifier(package);
      requires[identifier] = package;
    }

    return "self.$identifier";
  });

  if (release) {
    // We don't ship the source map, so remove the source map comment.
    text =
        text.replaceFirst(RegExp(r"\n*//# sourceMappingURL=[^\n]+\n*$"), "\n");
  }

  var buffer = StringBuffer();

  // Reassigning require() makes Webpack complain.
  buffer.writeln(
      preamble.getPreamble().replaceFirst("self.require = require;\n", ""));

  requires.forEach((identifier, package) {
    buffer.writeln("self.$identifier = require(${jsonEncode(package)});");
  });

  buffer.write(text);

  destination.writeAsStringSync(buffer.toString());
}

/// A map from executable names in [executables] to JS- and Dart-safe
/// identifiers to use to identify those modules.
Map<String, String> get _executableIdentifiers {
  if (__executableIdentifiers != null) return __executableIdentifiers;

  var i = 0;
  __executableIdentifiers = {
    // Add a trailing underscore to indicate that the name is intended to be
    // private without making it Dart-private.
    for (var name in executables.keys) name: "cli_pkg_main_${i++}_"
  };
  return __executableIdentifiers;
}

Map<String, String> __executableIdentifiers;

/// The text of a Dart library that wraps and JS-exports all the package's
/// executables so they can be compiled as a unit.
String get _wrapperLibrary {
  var wrapper = StringBuffer();
  wrapper.writeln("import 'dart:typed_data';");
  wrapper.writeln("import 'package:js/js.dart';");

  // Dart-import each executable library so we can JS-export their `main()`
  // methods and call them from individual files in the npm package.
  executables.forEach((name, path) {
    var import = jsonEncode(p.toUri(p.join('..', path)).toString());
    wrapper.writeln("import $import as ${_executableIdentifiers[name]};");
  });
  if (jsModuleMainLibrary != null) {
    var target =
        jsonEncode(p.toUri(p.join('..', jsModuleMainLibrary)).toString());
    wrapper.writeln("import $target as module_main;");
  }

  // Define a JS-interop "exports" field that we can use to export the various
  // main methods.
  wrapper.writeln("""
@JS()
external _Exports get exports;

@JS()
class _Exports {""");
  for (var identifier in _executableIdentifiers.values) {
    wrapper.writeln("external set $identifier(function);");
  }
  wrapper.writeln("}");

  wrapper.writeln("void main() {");

  // Work around dart-lang/sdk#37716
  wrapper.writeln("Uint8List(0);");

  // JS-export all the Dart-imported main methods.
  if (jsModuleMainLibrary != null) wrapper.writeln("module_main.main();");
  for (var identifier in _executableIdentifiers.values) {
    wrapper.writeln("exports.$identifier = _wrapMain($identifier.main);");
  }
  wrapper.writeln("}");

  // Add a wrapper function that convert the untyped JS argument list to a typed
  // Dart list, if `main()` takes arguments.
  wrapper.writeln("""
Function _wrapMain(Function main) {
  if (main is Object Function()) {
    return allowInterop((_) => main());
  } else {
    return allowInterop(
        (args) => main(List<String>.from(args as List<Object>)));
  }
}""");

  return wrapper.toString();
}

/// Converts [package] to a valid JS identifier based on its name.
String _packageNameToIdentifier(String package) => package
    .replaceFirst(RegExp(r'^@'), '')
    .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');

/// Builds a pure-JS npm package.
void _buildPackage() {
  var dir = Directory('build/npm');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);

  write(
      p.join('build', 'npm', 'package.json'),
      jsonEncode({
        ...npmPackageJson,
        "version": version.toString(),
        "bin": {for (var name in executables.keys) name: "${name}.js"},
        if (jsModuleMainLibrary != null) "main": "$_npmName.dart.js"
      }));

  safeCopy('build/$_npmName.dart.js', dir.path);
  for (var name in executables.keys) {
    write(p.join('build', 'npm', '$name.js'), """
#!/usr/bin/env node

var module = require('./$_npmName.dart.js');
module.${_executableIdentifiers[name]}(process.argv.slice(2));
""");
  }

  var readme = npmReadme;
  if (readme != null) write('build/npm/README.md', readme);

  if (File("LICENSE").existsSync()) safeCopy("LICENSE", dir.path);
}

/// Publishes the contents of `build/npm` to npm.
Future<void> _deploy() async {
  var file = File(".npmrc").openSync(mode: FileMode.writeOnlyAppend);
  file.writeStringSync("\n//registry.npmjs.org/:_authToken=$npmToken");
  file.closeSync();

  log("npm publish build/npm");
  var process = await Process.start("npm", ["publish", "build/npm"]);
  LineSplitter().bind(utf8.decoder.bind(process.stdout)).listen(log);
  LineSplitter().bind(utf8.decoder.bind(process.stderr)).listen(log);
  if (await process.exitCode != 0) fail("npm publish failed");
}
