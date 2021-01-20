These tasks upload [standalone packages][] to GitHub releases. They're enabled
by calling [`pkg.addGithubTasks()`][], which automatically calls
[`pkg.addStandaloneTasks()`][].

[standalone packages]: standalone.md
[`pkg.addGithubTasks()`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/addGithubTasks.html
[`pkg.addStandaloneTasks()`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/addStandaloneTasks.html

## `pkg-github-release`

Uses configuration: [`pkg.humanName`][], [`pkg.version`][],
[`pkg.githubRepo`][], [`pkg.githubUser`][], [`pkg.githubPassword`][],
[`pkg.githubBearerToken`][], [`pkg.githubReleaseNotes`][]

[`pkg.humanName`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/humanName.html
[`pkg.version`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/version.html
[`pkg.githubRepo`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/githubRepo.html
[`pkg.githubUser`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/githubUser.html
[`pkg.githubPassword`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/githubPassword.html
[`pkg.githubBearerToken`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/githubBearerToken.html
[`pkg.githubReleaseNotes`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/githubReleaseNotes.html

Creates a GitHub release for the current version of this package, without any
files uploaded to it.

## `pkg-github-$os`

Depends on: [`pkg-standalone-$os-ia32`, `pkg-standalone-$os-x64`][]

[`pkg-standalone-$os-ia32`, `pkg-standalone-$os-x64`]: standalone.md#pkg-standalone-os-arch

Uses configuration: [`pkg.version`][], [`pkg.githubRepo`][],
[`pkg.githubUser`][], [`pkg.githubPassword`][], [`pkg.githubBearerToken`][],
[`pkg.standaloneName`][]

[`pkg.standaloneName`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/standaloneName.html

Uploads 32- and 64-bit executable packages for the given operating system
(`linux`, `windows`, or `macos`) to the GitHub release for the current version.

Any OS's packages can be built and uploaded regardless of the OS running the
task, but if the host OS matches the target OS the 64-bit executable will be
built as a native executable, which is substantially faster.

This must be invoked after [`pkg-github-release`][], but it doesn't have a
built-in dependency so that different OSs' packages can be built in different
build steps.

[`pkg-github-release`]: #pkg-github-release

## `pkg-github-all`

Depends on: [`pkg-github-release`][], [`pkg-github-linux`, `pkg-github-macos`,
`pkg-github-windows`][]

[`pkg-github-linux`, `pkg-github-macos`, `pkg-github-windows`]: #pkg-github-os

A utility task for creating a release and uploading packages for all operating
systems in the same step.
