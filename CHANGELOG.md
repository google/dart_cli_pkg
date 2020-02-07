# 1.0.0-beta.4

* Add a `pkg.npmDistTag` getter that controls the distribution tag for an npm
  release.

* Add a `pkg.homebrewCreateVersionedFormula` getter that controls whether the
  Homebrew release creates a new formula or updates an existing one.

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
