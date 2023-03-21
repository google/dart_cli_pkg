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

import 'package:collection/collection.dart' show IterableExtension;
import 'package:grinder/grinder.dart';
import 'package:node_preamble/preamble.dart' as preamble;
import 'package:path/path.dart' as p;

import 'config_variable.dart';
import 'info.dart';
import 'js_require.dart';
import 'js_require_target.dart';
import 'js_require_set.dart';
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
/// By default, this contains `-O4`, `--no-minify`, `--no-source-maps`, and
/// `--fast-startup`. This doesn't minify by default because download size isn't
/// especially important server-side and it's nice to get readable stack traces
/// from bug reports.
final jsReleaseFlags = InternalConfigVariable.value<List<String>>(
    ["-O4", "--no-minify", "--no-source-maps", "--fast-startup"],
    freeze: (list) => List.unmodifiable(list));

/// A modifiable list of JavaScript packages to `require()` at the beginning of
/// the generated JS file.
///
/// The same identifier may be used for multiple requires. If so, the require
/// with the most specific [JSRequireTarget] will be used for a given identifier
/// on a given platform. If there are multiple requires with the same
/// [JSRequireTarget], the last one will be used.
///
/// If an executable passes a literal string to `require()` through Dart's JS
/// interop and a [JSRequire] is specified for that package, the interop
/// `require()` will be converted to a reference to the [JSRequire]. If there is
/// no [JSRequire], one will be added automatically.
///
/// If any requires have a target other than [JSRequireTarget.cli] or
/// [JSRequireTarget.all], [jsModuleMainLibrary] must also be set, since
/// otherwise there's no reason to split requires up by target.
final jsRequires = InternalConfigVariable.value<List<JSRequire>>([],
    freeze: (list) => List.unmodifiable(list));

/// A list of member names to export from ESM library entrypoints, since ESM
/// exports must be explicitly listed in each wrapper library.
///
/// ESM library entrypoints will be generated if and only if this is set.
///
/// If this is set, [jsModuleMainLibrary] must also be set.
final jsEsmExports = InternalConfigVariable.value<Set<String>?>(null,
    freeze: (set) => set == null ? null : Set.unmodifiable(set));

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
final jsModuleMainLibrary = InternalConfigVariable.value<String?>(null);

/// The decoded contents of the npm package's `package.json` file.
///
/// By default, this is loaded from `package.json` at the root of the
/// repository. It's modifiable.
///
/// `cli_pkg` will automatically add `"version"` and `"bin"` fields when
/// building the npm package. If [jsModuleMainLibrary] is set, it will also add
/// a `"main"` field.
final npmPackageJson = InternalConfigVariable.fn<Map<String, dynamic>>(
    () => File("package.json").existsSync()
        ? jsonDecode(File("package.json").readAsStringSync())
            as Map<String, dynamic>
        : fail("pkg.npmPackageJson must be set to build an npm package."),
    freeze: freezeJsonMap);

/// A set of additional files to include in the npm package.
///
/// This is a map from paths (relative to the root of the package) to the
/// contents of those files. It defaults to an empty map.
final npmAdditionalFiles = InternalConfigVariable.fn<Map<String, String>>(
    () => {},
    freeze: (map) => Map.unmodifiable(map));

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
final npmReadme = InternalConfigVariable.fn<String?>(() =>
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
  jsEsmExports.freeze();
  jsModuleMainLibrary.freeze();
  npmPackageJson.freeze();
  npmReadme.freeze();
  npmToken.freeze();
  npmDistTag.freeze();

  var hasNonCliRequires = jsRequires.value.any((require) =>
      require.target != JSRequireTarget.cli &&
      require.target != JSRequireTarget.all);
  if (jsModuleMainLibrary.value == null) {
    if (hasNonCliRequires) {
      fail("If jsModuleMainLibrary isn't set, all jsRequires must have "
          "JSRequireTarget.cli or JSRequireTarget.all.");
    } else if (jsEsmExports.value != null) {
      fail("If jsEsmExports is set, jsModuleMainLibrary must be set as well.");
    }
  }

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
void _js({required bool release}) {
  ensureBuild();
  verifyEnvironmentConstants(forSubprocess: true);

  var source = File("build/${_npmName}_npm.dart");
  source.writeAsStringSync(_wrapperLibrary);

  var destination = File('build/$_npmName.dart.js');

  Dart2js.compile(source, outFile: destination, extraArgs: [
    '--server-mode',
    '-Dnode=true',
    for (var entry in environmentConstants.value.entries)
      '-D${entry.key}=${entry.value}',
    ...jsFlags.value,
    if (release) ...jsReleaseFlags.value else ...jsDevFlags.value
  ]);
}

/// A map from executable names in [executables] to JS- and Dart-safe
/// identifiers to use to identify those modules.
final Map<String, String> _executableIdentifiers = () {
  var i = 0;
  return {
    // Add a trailing underscore to indicate that the name is intended to be
    // private without making it Dart-private.
    for (var name in executables.value.keys) name: "cli_pkg_main_${i++}_"
  };
}();

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
dynamic _translateReturnValue(dynamic val) {
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
  if (main is dynamic Function()) {
    return allowInterop((_) => _translateReturnValue(main()));
  } else {
    return allowInterop(
        (args) => _translateReturnValue(
            main(List<String>.from(args as List<dynamic>))));
  }
}""");

  return wrapper.toString();
}

/// Builds a pure-JS npm package.
Future<void> _buildPackage() async {
  var dir = Directory('build/npm');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);

  var extractedRequires = _copyJSAndInjectDependencies(
      'build/$_npmName.dart.js', p.join(dir.path, '$_npmName.dart.js'));
  var allRequires =
      _requiresForTarget(JSRequireTarget.all).union(extractedRequires);

  var nodeRequires = _requiresForTarget(JSRequireTarget.node);
  var cliRequires = _requiresForTarget(JSRequireTarget.cli).union(nodeRequires);
  var browserRequires = _requiresForTarget(JSRequireTarget.browser);
  var defaultRequires = _requiresForTarget(JSRequireTarget.defaultTarget);

  writeString(
      p.join('build', 'npm', 'package.json'),
      jsonEncode({
        ...npmPackageJson.value,
        "version": version.toString(),
        "bin": {for (var name in executables.value.keys) name: "$name.js"},
        if (jsModuleMainLibrary.value != null)
          "main": "$_npmName.${nodeRequires.isEmpty ? 'default' : 'node'}"
              ".${jsEsmExports.value == null ? 'js' : 'cjs'}",
        if (npmPackageJson.value["exports"] is Map ||
            nodeRequires.isNotEmpty ||
            browserRequires.isNotEmpty ||
            jsEsmExports.value != null)
          "exports": {
            if (npmPackageJson.value["exports"] is Map)
              ...npmPackageJson.value["exports"],
            if (browserRequires.isNotEmpty)
              "browser": _exportSpecifier("browser"),
            if (nodeRequires.isNotEmpty) "node": _exportSpecifier("node"),
            if (jsModuleMainLibrary.value != null)
              "default": _exportSpecifier("default"),
          },
      }));

  for (var name in executables.value.keys) {
    var buffer = StringBuffer("""
#!/usr/bin/env node

""");

    if (jsEsmExports.value != null) {
      buffer.writeln("""
require('./$_npmName.dart.js');
var library = globalThis._cliPkgExports.pop();
if (globalThis._cliPkgExports.length === 0) delete globalThis._cliPkgExports;
""");
    } else {
      buffer.writeln("var library = require('./$_npmName.dart.js');");
    }

    buffer.writeln(_loadRequires(cliRequires.union(allRequires)));
    buffer.writeln(
        "library.${_executableIdentifiers[name]}(process.argv.slice(2));");
    writeString(p.join('build', 'npm', '$name.js'), buffer.toString());
  }

  if (jsModuleMainLibrary.value != null) {
    if (nodeRequires.isNotEmpty) {
      _writePlatformWrapper(p.join('build', 'npm', '$_npmName.node.js'),
          nodeRequires.union(allRequires));
    }
    if (browserRequires.isNotEmpty) {
      _writePlatformWrapper(p.join('build', 'npm', '$_npmName.browser.js'),
          browserRequires.union(allRequires));
    }

    _writePlatformWrapper(p.join('build', 'npm', '$_npmName.default.js'),
        defaultRequires.union(allRequires));
  }

  var readme = npmReadme.value;
  if (readme != null) writeString('build/npm/README.md', readme);

  writeString(p.join(dir.path, "LICENSE"), await license);

  for (var entry in npmAdditionalFiles.value.entries) {
    if (!p.isRelative(entry.key)) {
      fail('pkg.npmAdditionalFiles keys must be relative paths,\n'
          'but "${entry.key}" is absolute.');
    }

    var path = p.join(dir.path, entry.key);
    Directory(p.dirname(path)).createSync(recursive: true);
    File(path).writeAsStringSync(entry.value);
  }
}

/// Copies the compiled JS from [source] to [destination] while also adding
/// infrastructure to inject dependencies based on the target platform.
///
/// This returns the set of [JSRequire]s that were extracted from the compiled
/// JS and which _weren't_ defined by [jsRequires].
JSRequireSet _copyJSAndInjectDependencies(String source, String destination) {
  var extractedRequires = JSRequireSet();
  var compiledDart = File(source)
      .readAsStringSync()
      // Some dependencies dynamically invoke `require()`, which makes Webpack
      // complain. We replace those with direct references to the modules, which
      // we load explicitly after the preamble.
      .replaceAllMapped(RegExp(r'self\.require\(("[^"]+")\)'), (match) {
    var package = jsonDecode(match[1]!) as String;

    // Don't add a new require for [package] unless there isn't an explicit one
    // declared.
    var identifier = jsRequires.value.reversed
        .firstWhereOrNull((require) => require.package == package)
        ?.identifier;
    if (identifier == null) {
      var require = JSRequire(package, target: JSRequireTarget.all);
      extractedRequires.add(require);
      identifier = require.identifier;
    }
    return "self.$identifier";
  });

  var buffer = StringBuffer();

  var exportsVariable = "exports";
  if (jsEsmExports.value != null) {
    buffer.writeln("""
// Because of vitejs/vite#12340, there's no way to reliably detect whether we're
// running as a (possibly bundled/polyfilled) ESM module or as a CommonJS
// module. In order to work everywhere, we have to provide the load function via
// a side channel on the global object. We write it as a stack so that multiple
// cli_pkg packages can depend on one another without clobbering their exports.
globalThis._cliPkgExports  ||= [];
let _cliPkgExports = {};
globalThis._cliPkgExports.push(_cliPkgExports);
""");
    exportsVariable = "_cliPkgExports";
  }

  buffer.writeln(
      "$exportsVariable.load = function(_cliPkgRequires, _cliPkgExportParam)"
      " {");

  buffer.writeln(preamble
      .getPreamble()
      // Reassigning require() makes Webpack complain.
      .replaceFirst("self.require = require;\n", "")
      // Allow library wrappers to pass in an explicit export variable.
      .replaceFirst("""
if (typeof exports !== "undefined") {
  self.exports = exports;
}""", "self.exports = _cliPkgExportParam || $exportsVariable;"));

  for (var require in [...jsRequires.value, ...extractedRequires]) {
    buffer.write("self.${require.identifier} = ");
    buffer.writeln("_cliPkgRequires.${require.identifier};");
  }

  buffer.write(compiledDart);

  buffer.writeln("}");

  writeString(destination, buffer.toString());

  return extractedRequires;
}

/// Returns the subset of [jsRequires] that apply specifically to [target].
///
/// This doesn't include requires with [JSRequireTarget.all].
JSRequireSet _requiresForTarget(JSRequireTarget target) =>
    // Add requires in reverse order so later matching requires take precedence
    // over earlier ones.
    JSRequireSet.of(
        jsRequires.value.reversed.where((require) => require.target == target));

/// Returns a single string specifier for `package.exports` if [jsEsmExports]
/// isn't set, or a conditional export if it is.
Object _exportSpecifier(String name) => jsEsmExports.value == null
    ? "./$_npmName.$name.js"
    : {"require": "./$_npmName.$name.cjs", "default": "./$_npmName.$name.js"};

/// Writes one or two wrappers that loads and re-exports `$_npmName.dart.js`
/// with [requires] injected.
///
/// This writes both an ESM and a CJS wrapper if [jsEsmExports] is set.
void _writePlatformWrapper(String path, JSRequireSet requires) {
  var exports = jsEsmExports.value;
  if (exports != null) {
    _writeImportWrapper(path, requires, exports);
    _writeRequireWrapper(p.setExtension(path, '.cjs'), requires);
  } else {
    _writeRequireWrapper(path, requires);
  }
}

/// Writes a wrapper to [path] that loads and re-exports `$_npmName.dart.js`
/// with [requires] injected.
void _writeRequireWrapper(String path, JSRequireSet requires) {
  writeString(
      path,
      (jsEsmExports.value == null
              ? "const library = require('./$_npmName.dart.js');\n"
              : "require('./$_npmName.dart.js');\n"
                  "const library = globalThis._cliPkgExports.pop();\n"
                  "if (globalThis._cliPkgExports.length === 0) delete "
                  "globalThis._cliPkgExports;\n") +
          "${_loadRequires(requires)}\n"
              "module.exports = library;\n");
}

/// Returns the text of a `library.load()` call that loads [requires].
String _loadRequires(JSRequireSet requires) {
  var buffer = StringBuffer("library.load({");
  if (requires.isNotEmpty) buffer.writeln();
  for (var require in requires) {
    buffer.writeln(
        "  ${require.identifier}: require(${json.encode(require.package)}),");
  }
  buffer.writeln("});");
  return buffer.toString();
}

/// Writes a wrapper to [path] that loads and re-exports `$_npmName.dart.js`
/// using ESM imports with [requires] injected.
///
/// [exports] is the value of [jsEsmExports].
void _writeImportWrapper(
    String path, JSRequireSet requires, Set<String> exports) {
  var buffer = StringBuffer();
  for (var require in requires) {
    buffer.writeln("import * as ${require.identifier} from "
        "${json.encode(require.package)}");
  }

  buffer
    ..write("""
import ${json.encode('./$_npmName.dart.js')};

const _cliPkgLibrary = globalThis._cliPkgExports.pop();
if (globalThis._cliPkgExports.length === 0) delete globalThis._cliPkgExports;
const _cliPkgExports = {};
""")
    ..write("_cliPkgLibrary.load({")
    ..write(requires.map((require) => require.identifier).join(", "))
    ..writeln("}, _cliPkgExports);")
    ..writeln();

  for (var export in exports) {
    buffer.writeln("export const $export = _cliPkgExports.$export;");
  }

  writeString(path, buffer.toString());
}

/// Publishes the contents of `build/npm` to npm.
Future<void> _deploy() async {
  var file = File(".npmrc").openSync(mode: FileMode.writeOnlyAppend);
  file.writeStringSync("\n//registry.npmjs.org/:_authToken=$npmToken");
  file.closeSync();

  // The trailing slash in "build/npm/" is necessary to avoid NPM trying to
  // treat the path name as a GitHub repository slug.
  log("npm publish --tag $npmDistTag build/npm/");
  var process = await Process.start(
      "npm", ["publish", "--tag", npmDistTag.value, "build/npm/"]);
  LineSplitter().bind(utf8.decoder.bind(process.stdout)).listen(log);
  LineSplitter().bind(utf8.decoder.bind(process.stderr)).listen(log);
  if (await process.exitCode != 0) fail("npm publish failed");
}
