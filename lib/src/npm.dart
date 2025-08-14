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

// The way we handle imports and requires is moderately complicated, due to the
// conflux of requirements from Node.js and browsers. If there are no
// [jsEsmExports], it's easy: we don't need to support anything but Node, so we
// just make everything CJS with the `.js` extension. But once ESM is in play,
// things get much harder. We're under the following constraints:
//
// * For MIME type reasons, browsers can _only_ load files with extension `.js`,
//   not `.mjs` or `.cjs`.
//
// * This means we need the dart2js output to be named `.js`, which in turn
//   means we can't use `"type": "module"` in the package.json because otherwise
//   our CJS libraries wouldn't be able to `require()` the `.dart.js` file
//   (since Node.js would consider it a module).
//
// * Because we can't use `"type": "module"`, we need ESM files that are
//   consumed by Node.js to use the extension `.mjs`, while CJS files that are
//   consumed by Node.js need to use the extension `.js`.
//
// * On the other hand, ESM files that can be consumed by the browser need to
//   use the extension `.js` as above. But we still want to provide
//   browser-capable CJS alternatives because many browser users go through
//   bundlers first rather than directly loading files, so to disambiguate we
//   use the extension `.cjs` for those.
//
// To summarize, we use the following extensions:
//
// * `.js`: The dart2js-generated `.dart.js` file which has no imports or
//   requires, CJS wrappers consumed by node, ESM files consumed by non-Node.
//
// * `.cjs`: CJS wrappers consumed by non-Node.
//
// * `.mjs`: ESM files consumed by Node.

/// A list of member names to export from ESM library entrypoints, since ESM
/// exports must be explicitly listed in each wrapper library.
///
/// ESM library entrypoints will be generated if and only if this is set.
///
/// **Warning:** When JS code is loaded as ESM in a browser, it automatically
/// runs in [strict mode]. Dart has [an outstanding bug] where primitive types
/// such as strings thrown by JS will cause Dart code that catches them to crash
/// in strict mode specifically. To work around this bug, wrap all calls to JS
/// callbacks in [`wrapJSExceptions`].
///
/// [strict mode]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Strict_mode
/// [an outstanding bug]: https://github.com/dart-lang/sdk/issues/53105
/// [`wrapJSExceptions`]: https://pub.dev/documentation/cli_pkg/latest/js/wrapJSExceptions.html
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
/// import 'dart:js_interop';
///
/// extension type _Exports._(JSObject _) implements JSObjcet {
///   external set sayHello(JSFunction function);
/// }
///
/// external get _Exports exports;
///
/// void main() {
///   exports.sayHello = (() => print("Hello, world!")).toJS;
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

/// Whether to force [strict mode] for the generated JS code.
///
/// [strict mode]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Strict_mode
///
/// If the generated JS is loaded as a library in the browser without bundling,
/// it will _unavoidably_ be loaded in strict mode, so even if this is `false`
/// (the default) it's not a guarantee that the code will always run in sloppy
/// mode. Setting it to `true` can make it easier to surface strict mode bugs
/// early.
final jsForceStrictMode = InternalConfigVariable.value<bool>(false);

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

/// Whether we're generating a package that supports ESM imports.
bool get _supportsEsm => jsEsmExports.value != null;

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
    } else if (_supportsEsm) {
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
  wrapper.writeln("import 'dart:js_interop';");

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
JSAny? _translateReturnValue(dynamic val) {
  if (val is Future<JSAny?>) {
    return val.toJS;
  } else {
    return val as JSAny?;
  }
}
""");

  // Define a JS-interop "exports" field that we can use to export the various
  // main methods.
  wrapper.writeln("""
@JS()
external _Exports get exports;

extension type _Exports._(JSObject _) implements JSObject {""");
  for (var identifier in _executableIdentifiers.values) {
    wrapper.writeln("external set $identifier(JSFunction function);");
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
JSFunction _wrapMain(Function main) {
  if (main is dynamic Function()) {
    return ((JSAny? _) => _translateReturnValue(main())).toJS;
  } else {
    return (
      (JSArray<JSString> args) => _translateReturnValue(main(args.toDart))
    ).toJS;
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
          "main": "$_npmName.${nodeRequires.isEmpty ? 'default' : 'node'}.js",
        if (npmPackageJson.value["exports"] is Map ||
            nodeRequires.isNotEmpty ||
            browserRequires.isNotEmpty ||
            _supportsEsm)
          "exports": {
            if (npmPackageJson.value["exports"] is Map)
              ...npmPackageJson.value["exports"] as Map,
            if (browserRequires.isNotEmpty)
              "browser": _exportSpecifier("browser"),
            if (nodeRequires.isNotEmpty || _supportsEsm)
              "node": _exportSpecifier("node", node: true),
            if (jsModuleMainLibrary.value != null)
              "default": _exportSpecifier("default"),
          },
      }));

  for (var name in executables.value.keys) {
    var buffer = StringBuffer("""
#!/usr/bin/env node

""");

    if (_supportsEsm) {
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
    if (nodeRequires.isNotEmpty || _supportsEsm) {
      _writePlatformWrapper(p.join('build', 'npm', '$_npmName.node'),
          nodeRequires.union(allRequires),
          node: true);
    }
    if (browserRequires.isNotEmpty) {
      _writePlatformWrapper(p.join('build', 'npm', '$_npmName.browser'),
          browserRequires.union(allRequires));
    }

    _writePlatformWrapper(p.join('build', 'npm', '$_npmName.default'),
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

  if (jsForceStrictMode.value) buffer.writeln('"use strict";');

  var exportsVariable = "exports";
  if (_supportsEsm) {
    buffer.writeln("""
// Because of vitejs/vite#12340, there's no way to reliably detect whether we're
// running as a (possibly bundled/polyfilled) ESM module or as a CommonJS
// module. In order to work everywhere, we have to provide the load function via
// a side channel on the global object. We write it as a stack so that multiple
// cli_pkg packages can depend on one another without clobbering their exports.
if (!globalThis._cliPkgExports) {
  globalThis._cliPkgExports = [];
}
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
      // Allow library wrappers to pass in an explicit export variable.
      .replaceFirst("""
if (typeof exports !== "undefined") {
  self.exports = exports;
}""", "self.exports = _cliPkgExportParam || $exportsVariable;"));

  for (var require in [...jsRequires.value, ...extractedRequires]) {
    // Rather than defining a module directly, a lazy require defines a function
    // that loads a module, so we need to expose those functions as getters.
    if (require.lazy) {
      buffer.writeln("Object.defineProperty(self, '${require.identifier}', "
          "{ get: _cliPkgRequires.${require.identifier} });");
    } else {
      buffer.writeln("self.${require.identifier} = "
          "_cliPkgRequires.${require.identifier};");
    }
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
///
/// See the note above [jsEsmExports] for details on the file extensions here.
Object _exportSpecifier(String name, {bool node = false}) => _supportsEsm
    ? {
        "require": "./$_npmName.$name.${node ? 'js' : 'cjs'}",
        "default": "./$_npmName.$name.${node ? 'mjs' : 'js'}"
      }
    : "./$_npmName.$name.js";

/// Writes one or two wrappers that loads and re-exports `$_npmName.dart.[c]js`
/// with [requires] injected.
///
/// The [requires] should not have the final `.[cm]js` extension. See the note
/// before [jsEsmExports] for more detail on the file extensions at play here.
///
/// This writes both an ESM and a CJS wrapper if [jsEsmExports] is set.
void _writePlatformWrapper(String path, JSRequireSet requires,
    {bool node = false}) {
  var exports = jsEsmExports.value;
  if (exports != null) {
    if (node) {
      _writeNodeImportWrapper('$path.mjs', exports);
    } else {
      _writeImportWrapper('$path.${node ? 'mjs' : 'js'}', requires, exports);
    }
    _writeRequireWrapper('$path.${node ? 'js' : 'cjs'}', requires);
  } else {
    _writeRequireWrapper('$path.js', requires);
  }
}

/// Writes a wrapper to [path] that loads and re-exports `$_npmName.dart.js`
/// with [requires] injected.
void _writeRequireWrapper(String path, JSRequireSet requires) {
  writeString(
      path,
      (_supportsEsm
              ? "require('./$_npmName.dart.js');\n"
                  "const library = globalThis._cliPkgExports.pop();\n"
                  "if (globalThis._cliPkgExports.length === 0) delete "
                  "globalThis._cliPkgExports;\n"
              : "const library = require('./$_npmName.dart.js');\n") +
          "${_loadRequires(requires)}\n"
              "module.exports = library;\n");
}

/// Returns the text of a `library.load()` call that loads [requires].
String _loadRequires(JSRequireSet requires) {
  var buffer = StringBuffer("library.load({");
  if (requires.isNotEmpty) buffer.writeln();
  for (var require in requires) {
    // The functions returned by lazy requires will be wrapped in getters.
    var requireFn = switch (require) {
      JSRequire(lazy: true, optional: true) => "(function(i){"
          "let r;"
          "return function ${require.identifier}(){"
          "if(void 0!==r)return r;"
          "try{"
          "r=require(i)"
          "}catch(e){"
          "if('MODULE_NOT_FOUND'!==e.code)console.error(e);"
          "r=null"
          "}"
          "return r"
          "}"
          "})",
      JSRequire(lazy: true) => "(function(i){"
          "return function ${require.identifier}(){"
          "return require(i)"
          "}"
          "})",
      JSRequire(optional: true) => "(function(i){"
          "try{"
          "return require(i)"
          "}catch(e){"
          "if('MODULE_NOT_FOUND'!==e.code)console.error(e);"
          "return null"
          "}"
          "})",
      _ => "require"
    };

    buffer.writeln(
        "  ${require.identifier}: $requireFn(${json.encode(require.package)}),");
  }
  buffer.writeln("});");
  return buffer.toString();
}

/// Writes a wrapper to [path] that loads and re-exports `$_npmName.node.js`
/// using ESM imports.
///
/// Rather than having a totally separate ESM wrapper, for Node we load ESM
/// exports *through* the require wrapper. This ensures that we don't run into
/// issues like sass/dart-sass#2017 if both are loaded in the same Node process.
///
/// [exports] is the value of [jsEsmExports].
void _writeNodeImportWrapper(String path, Set<String> exports) {
  var cjsUrl = './' + p.setExtension(p.basename(path), '.js');
  var buffer = StringBuffer("import cjs from ${json.encode(cjsUrl)};\n\n");

  for (var export in exports) {
    buffer.writeln("export const $export = cjs.$export;");
  }

  writeString(path, buffer.toString());
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
