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
import 'package:node_preamble/preamble.dart' as preamble;
import 'package:path/path.dart' as p;

import 'config_variable.dart';
import 'info.dart';
import 'utils.dart';

/// A modifiable list of additional flags to pass to `dart2js` when compiling
/// executables.
final jsFlags = InternalConfigVariable.value<List<String>>([],
    freeze: (list) => List.unmodifiable(list));

/// A modifiable list of flags to pass to `dart2js` only when compiling
/// executables in development mode.
final jsDevFlags = InternalConfigVariable.value<List<String>>([],
    freeze: (list) => List.unmodifiable(list));

/// A modifiable list of flags to pass to `dart2js` only when compiling
/// executables in release mode.
///
/// By default, this contains `-O4`, `--no-minify`, and `--fast-startup`. This
/// doesn't minify by default because download size isn't especially important
/// server-side and it's nice to get readable stack traces from bug reports.
final jsReleaseFlags = InternalConfigVariable.value<List<String>>(
    ["-O4", "--no-minify", "--fast-startup"],
    freeze: (list) => List.unmodifiable(list));

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
final jsRequires = InternalConfigVariable.value(<String, String>{},
    freeze: (map) => Map.unmodifiable(map));

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
final jsModuleMainLibrary = InternalConfigVariable.value<String>(null);

/// The decoded contents of the npm package's `package.json` file.
///
/// By default, this is loaded from `package.json` at the root of the
/// repository. It's modifiable.
///
/// `cli_pkg` will automatically add `"version"` and `"bin"` fields when
/// building the npm package. If [jsModuleMainLibrary] is set, it will also add
/// a `"main"` field.
final npmPackageJson = InternalConfigVariable.fn<Map<String, Object>>(
    () => File("package.json").existsSync()
        ? jsonDecode(File("package.json").readAsStringSync())
            as Map<String, Object>/*!*/
        : fail("pkg.npmPackageJson must be set to build an npm package."),
    freeze: freezeJsonMap);

/// The name of the npm package, from `package.json`.
String get _npmName {
  var name = npmPackageJson.value["name"];
  if (name is String) return name;

  if (name == null) fail("package.json must have a name field.");
  fail("package.json's name field must be a string.");
}

/// The Markdown-formatted text of the README to include in the npm package.
///
/// By default, this loads the contents of the `README.md` file at the root of
/// the repository.
final npmReadme = InternalConfigVariable.fn<String>(() =>
    File("README.md").existsSync()
        ? File("README.md").readAsStringSync()
        : null);

/// The npm [authentication token][] to use when creating releases and making
/// other changes.
///
/// [authentication token]: https://docs.npmjs.com/about-authentication-tokens
///
/// **Do not check this in directly.** This should only come from secure
/// sources.
///
/// By default this comes from the `NPM_TOKEN` environment variable.
final npmToken = InternalConfigVariable.fn<String>(() =>
    Platform.environment["NPM_TOKEN"] ??
    fail("pkg.npmToken must be set to deploy to npm."));

/// The [distribution tag][] to use when publishing the current `npm` package.
///
/// [distribution tag]: https://docs.npmjs.com/cli/dist-tag
///
/// By default this returns:
///
/// * For non-prerelease versions, `"latest"`.
///
/// * For prerelease versions with initial identifiers, that identifier. For
///   example, for `1.0.0-beta.1` this will return `"beta"`.
///
/// * For other prerelease versions, `"pre"`.
final npmDistTag = InternalConfigVariable.fn<String>(() {
  if (version.preRelease.isEmpty) return "latest";
  var firstComponent = version.preRelease[0];
  return firstComponent is String ? firstComponent : "pre";
});

/// Whether [addNpmTasks] has been called yet.
var _addedNpmTasks = false;

/// Enables tasks for building packages for npm.
void addNpmTasks() {
  if (_addedNpmTasks) return;
  _addedNpmTasks = true;

  freezeSharedVariables();
  jsFlags.freeze();
  jsDevFlags.freeze();
  jsReleaseFlags.freeze();
  jsRequires.freeze();
  jsModuleMainLibrary.freeze();
  npmPackageJson.freeze();
  npmReadme.freeze();
  npmToken.freeze();
  npmDistTag.freeze();

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
    ...jsFlags.value,
    if (release) ...jsReleaseFlags.value else ...jsDevFlags.value
  ]);

  // If the code invokes `require()`, convert that to a pre-load to avoid
  // Webpack complaining about dynamic `require()`.
  var requires = Map.of(jsRequires.value);
  var text = destination.readAsStringSync()
      // Some dependencies dynamically invoke `require()`, which makes Webpack
      // complain. We replace those with direct references to the modules, which
      // we load explicitly after the preamble.
      .replaceAllMapped(RegExp(r'self\.require\(("[^"]+")\)'), (match) {
    var package = jsonDecode(match[1]) as String/*!*/;
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

// TODO: late
/// A map from executable names in [executables] to JS- and Dart-safe
/// identifiers to use to identify those modules.
Map<String, String> get _executableIdentifiers {
  if (__executableIdentifiers != null) return __executableIdentifiers;

  var i = 0;
  __executableIdentifiers = {
    // Add a trailing underscore to indicate that the name is intended to be
    // private without making it Dart-private.
    for (var name in executables.value.keys) name: "cli_pkg_main_${i++}_"
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
  wrapper.writeln("import 'package:node_interop/node_interop.dart';");
  wrapper.writeln("import 'package:node_interop/util.dart';");

  // Dart-import each executable library so we can JS-export their `main()`
  // methods and call them from individual files in the npm package.
  executables.value.forEach((name, path) {
    var import = jsonEncode(p.toUri(p.join('..', path)).toString());
    wrapper.writeln("import $import as ${_executableIdentifiers[name]};");
  });
  if (jsModuleMainLibrary.value != null) {
    var target =
        jsonEncode(p.toUri(p.join('..', jsModuleMainLibrary.value)).toString());
    wrapper.writeln("import $target as module_main;");
  }

  // Define a JS-interop Future to Promise translator so that we can export
  // a Promise-based API
  wrapper.writeln("""
Object _translateReturnValue(Object val) {
  if (val is Future) {
    return futureToPromise(val);
  } else {
    return val;
  }
}
""");

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
  if (jsModuleMainLibrary.value != null) wrapper.writeln("module_main.main();");
  for (var identifier in _executableIdentifiers.values) {
    wrapper.writeln("exports.$identifier = _wrapMain($identifier.main);");
  }
  wrapper.writeln("}");

  // Add a wrapper function that convert the untyped JS argument list to a typed
  // Dart list, if `main()` takes arguments.
  wrapper.writeln("""
Function _wrapMain(Function main) {
  if (main is Object Function()) {
    return allowInterop((_) => _translateReturnValue(main()));
  } else {
    return allowInterop(
        (args) => _translateReturnValue(
            main(List<String>.from(args as List<Object>))));
  }
}""");

  return wrapper.toString();
}

/// Converts [package] to a valid JS identifier based on its name.
String _packageNameToIdentifier(String package) => package
    .replaceFirst(RegExp(r'^@'), '')
    .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');

/// Builds a pure-JS npm package.
Future<void> _buildPackage() async {
  var dir = Directory('build/npm');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);

  writeString(
      p.join('build', 'npm', 'package.json'),
      jsonEncode({
        ...npmPackageJson.value,
        "version": version.toString(),
        "bin": {for (var name in executables.value.keys) name: "${name}.js"},
        if (jsModuleMainLibrary.value != null) "main": "$_npmName.dart.js"
      }));

  safeCopy('build/$_npmName.dart.js', dir.path);
  for (var name in executables.value.keys) {
    writeString(p.join('build', 'npm', '$name.js'), """
#!/usr/bin/env node

var module = require('./$_npmName.dart.js');
module.${_executableIdentifiers[name]}(process.argv.slice(2));
""");
  }

  var readme = npmReadme.value;
  if (readme != null) writeString('build/npm/README.md', readme);

  writeString(p.join(dir.path, "LICENSE"), await license);
}

/// Publishes the contents of `build/npm` to npm.
Future<void> _deploy() async {
  var file = File(".npmrc").openSync(mode: FileMode.writeOnlyAppend);
  file.writeStringSync("\n//registry.npmjs.org/:_authToken=$npmToken");
  file.closeSync();

  log("npm publish --tag $npmDistTag build/npm");
  var process = await Process.start(
      "npm", ["publish", "--tag", npmDistTag.value, "build/npm"]);
  LineSplitter().bind(utf8.decoder.bind(process.stdout)).listen(log);
  LineSplitter().bind(utf8.decoder.bind(process.stderr)).listen(log);
  if (await process.exitCode != 0) fail("npm publish failed");
}
