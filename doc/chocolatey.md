These tasks build and upload packages to the [Chocolatey][] package manager for
Windows. They're enabled by calling [`pkg.addChocolateyTasks()`][], which
automatically calls [`pkg.addStandaloneTasks()`][].

[Chocolatey]: https://chocolatey.org
[`pkg.addChocolateyTasks()`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/addChocolateyTasks.html
[`pkg.addStandaloneTasks()`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/addStandaloneTasks.html

**Most of these tasks require the `choco` command line application to run.**
It's easiest to run Chocolatey on Windows (it comes pre-installed on Travis CI's
Windows VMs), but it's also possible to [run it on other platforms][] using
Mono.

[run it on other platforms]: https://github.com/chocolatey/choco#other-platforms

## `pkg-chocolatey`

Uses configuration: [`pkg.version`][], [`pkg.executables`][],
[`pkg.chocolateyNuspec`][], [`pkg.chocolateyFiles`][]

[`pkg.version`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/version.html
[`pkg.executables`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/executables.html
[`pkg.chocolateyNuspec`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/chocolateyNuspec.html
[`pkg.chocolateyFiles`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/chocolateyFiles.html

Output: `build/choco`

Creates an un-archived directory that contains the package in a format that
matches Chocolatey's layout expectations.

This does not require the `choco` command-line executable.

## `pkg-chocolatey-pack`

Depends on: [`pkg-chocolatey`][]

[`pkg-chocolatey`]: #pkg-chocolatey

Uses configuration: [`pkg.chocolateyNuspec`][]

Output: `build/${name}.${version}.nupkg`

Builds a Chocolatey-formatted `.nupkg` file.

## `pkg-chocolatey-deploy`

Depends on: [`pkg-chocolatey-pack`][]

[`pkg-chocolatey-pack`]: #pkg-chocolatey-pack

Uses configuration: [`pkg.version`][], [`pkg.chocolateyNuspec`][],
[`pkg.chocolateyToken`][]

[`pkg.chocolateyToken`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/chocolateyToken.html

Releases the package to Chocolatey.
