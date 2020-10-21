# 1.0.0-beta.11

* Properly load the Dart SDK license when it's in the directory above the SDK,
  as in a Homebrew installation.

* Use the latest version of the `xml` package.

# 1.0.0-beta.10

* **Breaking change:** All configurable variables are now defined as
  `ConfigVariable` objects rather than top-level fields. These objects make it
  possible to configure variables with callback functions and to freeze those
  variables once execution has begun.

* Properly handle git repositories that use branch names other than `master`.

# 1.0.0-beta.9

* Improve error messages if release notes can't be extracted from
  `CHANGELOG.md`.

# 1.0.0-beta.8

* Fixes a bug when reading a `CHANGELOG.md` with Windows-style line endings.

# 1.0.0-beta.7

* **Breaking change:** Dart snapshots are now named based on the executable name
  (specified in the pubspec or in `pkg.executables`) instead of the name of the
  Dart file in `bin`.

# 1.0.0-beta.6

* **Breaking change:** Chocolatey now uses the `choco` CLI to build and deploy
  packages, rather than re-implementing its logic in Dart. In particular:

  * The `pkg-chocolatey-build` task has been renamed to `pkg-chocolatey-pack` to
    match the CLI's naming scheme.

  * The `pkg-chocolatey-pack` and `pkg-chocolatey-deploy` tasks must be run in
    an environment with the `choco` command available.

* Add a `pkg-chocolatey` command that builds an un-archived Chocolatey package
  directory.

* Rather than releasing binary snapshots on Chocolatey, compile the source code
  to compile native executables on users' machines.

* Add a `chocolateyFiles` getter that returns the files that should be included
  in the Chocolatey package.

* Depend on the correct version of pre-release Dart SDKs from Chocolatey
  packages.

# 1.0.0-beta.5

* Use the correct URL when fetching GitHub release metadata.

# 1.0.0-beta.4

* Add a `pkg.npmDistTag` getter that controls the distribution tag for an npm
  release.

* Add a `pkg.homebrewCreateVersionedFormula` getter that controls whether the
  Homebrew release creates a new formula or updates an existing one.

* Run `pub publish --force` so it doesn't hang forever.

* Properly parse GitHub repositories from HTTP URLs ending in `.git`.

* Drop support for Mac OS ia32 packages, since Dart 2.7 doesn't support them
  anymore.

# 1.0.0-beta.3

* Add a `cli_pkg/testing.dart` library to make it easier for users to
  efficiently and reliably test their executables.

# 1.0.0-beta.2

* Add a `pkg-standalone-dev` task for building a script that can be invoked for
  testing.

* Fix a bug where the version variable wouldn't be set for certain executables.

# 1.0.0-beta.1

* Initial beta release.
