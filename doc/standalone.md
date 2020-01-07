These tasks create self-contained archives containing the Dart VM and snapshots
of the package's executables, which can then be easily distributed. They're the
basis for many other tasks that upload the packages to various package managers.
They're enabled by calling [`pkg.addStandaloneTasks()`][].

[`pkg.addStandaloneTasks()`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/addStandaloneTasks.html

Standalone executables are built and executed in a context with the `version`
environment declaration set to the package's version. This can be accessed with
[`String.fromEnvironment()`][].

[`String.fromEnvironment()`]: https://api.dartlang.org/stable/dart-core/String/String.fromEnvironment.html

## `pkg-compile-snapshot`

Uses configuration: [`pkg.executables`][]

[`pkg.executables`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/executables.html

Output: `build/$entrypoint.snapshot`

Compiles each executable in the package to a [kernel snapshot][snapshot].

[snapshot]: https://github.com/dart-lang/sdk/wiki/Snapshots

## `pkg-compile-native`

Uses configuration: [`pkg.executables`][], [`pkg.version`][]

[`pkg.version`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/version.html

Output: `build/$entrypoint.native`

Compiles each executable in the package to a native code snapshot (what Dart
calls an ["AOT Application snapshot"][snapshot]). This is unavailable on 32-bit
host systems.

Defines an environment constant named `version` set to [`pkg.version`][] that
can be accessed from within each entrypoint via [`String.fromEnvironment()`][].

[`String.fromEnvironment()`]: https://api.dartlang.org/stable/dart-core/String/String.fromEnvironment.html

## `pkg-standalone-dev`

Depends on: [`pkg-compile-snapshot`][]

Uses configuration: [`pkg.executables`][], [`pkg.version`][]

[`pkg.version`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/version.html

Output: `build/$executable` (on Linux and Mac OS) or `build/$executable.bat` (on
Windows)

Creates scripts for each of this package's executables that executes them with
asserts enabled. The details of how the executables are compiled may change over
time or from platform to platform for increased efficiency, but they'll always
be invoked through the same scripts. This makes it easy to run executable
integration tests as efficiently as possible across platforms.

## `pkg-standalone-$os-$arch`

Depends on: [`pkg-compile-snapshot`][] or [`pkg-compile-native`][]

[`pkg-compile-snapshot`]: #pkg-compile-snapshot
[`pkg-compile-native`]: #pkg-compile-native

Uses configuration: [`pkg.version`][], [`pkg.standaloneName`][], [`pkg.executables`][]

[`pkg.standaloneName`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/standaloneName.html

Output: `build/$standaloneName-$version-$os-$arch.(tar.gz|zip)`

Creates an archive that contains all this package's entrypoints along with the
Dart VM for the given operating system and architecture, with top-level scripts
that can be used to invoke them.

Any OS's packages can be built regardless of the OS running the task, but if the
host OS matches the target OS *and* the architecture is 64-bit, executables will
be built as native (["AOT"][snapshot]) executables, which are substantially
faster and smaller than the kernel snapshots that are generated otherwise.

This produces a ZIP file in Windows, and a gzipped TAR file on Linux and Mac OS.

## `pkg-standalone-all`

Depends on: [`pkg-standalone-linux-ia32`, `pkg-standalone-linux-x64`,
`pkg-standalone-macos-ia32`, `pkg-standalone-macos-x64`,
`pkg-standalone-windows-ia32`, `pkg-standalone-windows-x64`][]

[`pkg-standalone-linux-ia32`, `pkg-standalone-linux-x64`, `pkg-standalone-macos-ia32`, `pkg-standalone-macos-x64`, `pkg-standalone-windows-ia32`, `pkg-standalone-windows-x64`]: #pkg-standalone-os-arch

A utility task for creating a packages for all operating systems in the same
step.
