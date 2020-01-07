These tasks build and upload packages to the [Chocolatey][] package manager for
Windows. They're enabled by calling [`pkg.addChocolateyTasks()`][], which
automatically calls [`pkg.addStandaloneTasks()`][]. These tasks can be run
anywhere: they don't require Chocolatey to be installed, and they don't need to
be run on Windows.

[Chocolatey]: https://chocolatey.org
[`pkg.addChocolateyTasks()`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/addChocolateyTasks.html
[`pkg.addStandaloneTasks()`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/addStandaloneTasks.html


## `pkg-chocolatey-build`

Depends on: [`pkg-compile-snapshot`][]

[`pkg-compile-snapshot`]: standalone.md#pkg-compile-snapshot

Uses configuration: [`pkg.version`][], [`pkg.executables`][],
[`pkg.chocolateyNuspec`][]

[`pkg.version`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/version.html
[`pkg.executables`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/executables.html
[`pkg.chocolateyNuspec`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/chocolateyNuspec.html

Ouput: `build/${name}.${version}.nupkg`

Builds a package zip file in the format Chocolatey expects.

## `pkg-chocolatey-deploy`

Depends on: [`pkg-chocolatey-build`][]

[`pkg-chocolatey-build`]: standalone.md#pkg-chocolatey-build

Uses configuration: [`pkg.chocolateyToken`][]

[`pkg.chocolateyToken`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/chocolateyToken.html

Releases the package to Chocolatey.
