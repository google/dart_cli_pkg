These tasks compile the package to JavaScript, build [npm][] packages, and
upload them to the npm registry. They're enabled by calling
[`pkg.addNpmTasks()`][].

[npm]: https://www.npmjs.com
[`pkg.addNpmTasks()`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/addNpmTasks.html

Note that all JS compilation requires that a `package.json` file exist at the
root of your package, *or* that you set the [`pkg.npmPackageJson`][] field.
Either way, you must at least include the `"name"` field.

[`pkg.npmPackageJson`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/npmPackageJson.html

When compiled to JS, the package has access to the `version` and `dartVersion`
environment declarations, which provide the package's version and the version of
Dart that it was compiled with, respectively. They can be accessed with
[`String.fromEnvironment()`][]. It also sets the `node` environment declaration
to `true`, which can be accessed through [`bool.fromEnvironment()`][].

[`String.fromEnvironment()`]: https://api.dartlang.org/stable/dart-core/String/String.fromEnvironment.html
[`bool.fromEnvironment()`]: https://api.dartlang.org/stable/dart-core/String/bool.fromEnvironment.html

The package is built with the `--server-mode` option, which allows [conditional
imports][] to be used to load different libraries when compiling for JavaScript
than you do when running on the VM:

[conditional imports]: https://github.com/dart-lang/site-www/issues/1569

```dart
// lib/src/io.dart

// Export a Dart-VM-compatible IO library by default, and a Node.js-compatible
// one when compiling to JavaScript.
export 'io/vm.dart' 
    if (dart.library.js) 'io/node.dart';
```

You can export JavaScript functions from your package so it can be loaded as a
library in addition to having its executables invoked. See
[`pkg.jsModuleMainLibrary`][] for more details.

[`pkg.jsModuleMainLibrary`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/jsModuleMainLibrary.html

## `pkg-js-dev`

Uses configuration: [`pkg.executables`][], [`pkg.version`][], [`pkg.jsFlags`][],
[`pkg.jsDevFlags`][], [`pkg.jsRequires`][], [`pkg.jsModuleMainLibrary`][],
[`pkg.npmPackageJson`][]

[`pkg.executables`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/executables.html
[`pkg.version`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/version.html
[`pkg.jsFlags`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/jsFlags.html
[`pkg.jsDevFlags`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/jsDevFlags.html
[`pkg.jsRequires`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/jsRequires.html

Output: `build/$name.dart.js`

Compiles all this package's executables to a single JavaScript file, in
development mode. By default, development mode has all optimizations disabled.

## `pkg-js-release`

Uses configuration: [`pkg.executables`][], [`pkg.version`][], [`pkg.jsFlags`][],
[`pkg.jsReleaseFlags`][], [`pkg.jsRequires`][], [`pkg.jsModuleMainLibrary`][],
[`pkg.npmPackageJson`][]

[`pkg.jsReleaseFlags`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/jsReleaseFlags.html

Output: `build/$name.dart.js`

Compiles all this package's executables to a single JavaScript file, in release
mode. By default, release mode uses dart2js's `-O4` flag, with minification
disabled.

## `pkg-npm-dev`

Depends on: [`pkg-js-dev`][]

[`pkg-js-dev`]: #pkg-js-dev

Uses configuration: [`pkg.executables`][], [`pkg.version`][], [`pkg.npmPackageJson`][], [`pkg.jsModuleMainLibrary`][], [`pkg.npmReadme`][], [`pkg.npmDistTag`][], [`pkg.npmAdditionalFiles`]

[`pkg.npmReadme`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/npmReadme.html
[`pkg.npmDistTag`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/npmDistTag.html
[`pkg.npmAdditionalFiles`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/npmAdditionalFilesTag.html

Output: `build/npm/*`

Creates an npm-compatible package directory containing this package's compiled
dev-mode JavaScript, shims to invoke each executable's `main()` method, and its
`package.json`.

It will also include a README if [`pkg.npmReadme`][] isn't null, and a LICENSE
if one exists at the top level of the package.

Executables from this package can be invoked using testing APIs such as
[`pkg.start()`][], [`pkg.executableRunner()`][], and [`pkg.executableArgs()`][].

[`pkg.start()`]: https://pub.dev/documentation/cli_pkg/latest/testing/version.html
[`pkg.executableRunner()`]: https://pub.dev/documentation/cli_pkg/latest/testing/executableRunner.html
[`pkg.executableArgs()`]: https://pub.dev/documentation/cli_pkg/latest/testing/executableArgs.html

## `pkg-npm-release`

Depends on: [`pkg-js-release`][]

[`pkg-js-release`]: #pkg-js-release

Uses configuration: [`pkg.executables`][], [`pkg.version`][], [`pkg.npmPackageJson`][], [`pkg.jsModuleMainLibrary`][], [`pkg.npmReadme`][], [`pkg.npmAdditionalFiles`]

Output: `build/npm/*`

Creates an npm-compatible package directory containing this package's compiled
release-mode JavaScript, shims to invoke each executable's `main()` method, and
its `package.json`.

It will also include a README if [`pkg.npmReadme`][] isn't null, and a LICENSE
if one exists at the top level of the package.

## `pkg-npm-deploy`

Depends on: [`pkg-npm-release`][]

[`pkg-npm-release`]: #pkg-npm-release

Uses configuration: [`pkg.npmToken`][]

[`pkg.npmToken`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/npmToken.html

Publishes the package to the npm registry.
