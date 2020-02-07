This task updates an existing Homebrew formula to point to the latest source
archive for this package. It's enabled by calling [`pkg.addHomebrewTasks()`][].

[`pkg.addHomebrewTasks()`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/addHomebrewTasks.html

The Homebrew task treats the package's Homebrew repository as the source of
truth for all configuration and metadata. This means that it's the user's
responsibility to set up a reasonable installation formula ([Dart Sass's
formula][] is a good starting point). All this task does is update the formula's
`url` and `sha256` fields to the appropriate values for the latest version.

[Dart Sass's formula]: https://github.com/sass/homebrew-sass/blob/master/sass.rb

This task assumes that the package is published on GitHub (specifically to
[`pkg.githubRepo`][]), and that the task is running in a clone of that GitHub
repo.

[`pkg.githubRepo`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/githubRepo.html

## `pkg-homebrew-update`

Uses configuration: [`pkg.version`][], [`pkg.humanName`][], [`pkg.botName`][],
[`pkg.botEmail`][], [`pkg.githubRepo`][], [`pkg.githubUser`][],
[`pkg.githubPassword`][], [`pkg.homebrewRepo`][], [`pkg.homebrewFormula`][],
[`pkg.homebrewTag`][], [`pkg.homebrewCreateVersionedFormula`][]

[`pkg.version`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/version.html
[`pkg.humanName`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/humanName.html
[`pkg.botName`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/botName.html
[`pkg.botEmail`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/botEmail.html
[`pkg.githubUser`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/githubUser.html
[`pkg.githubPassword`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/githubPassword.html
[`pkg.homebrewRepo`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/homebrewRepo.html
[`pkg.homebrewFormula`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/homebrewFormula.html
[`pkg.homebrewTag`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/homebrewTag.html
[`pkg.homebrewCreateVersionedFormula`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/homebrewCreateVersionedFormula.html

Checks out [`pkg.homebrewRepo`][] and pushes a commit updating
[`pkg.homebrewFormula`][]'s `url` and `sha256` fields to point to the
appropriate values for [`pkg.version`][].
