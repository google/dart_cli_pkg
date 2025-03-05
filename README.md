## Dart CLI Packager

This package provides a set of [Grinder][] tasks that make it easy to release a
Dart command-line application on various release channels, for both Dart and
non-Dart users alike. It also integrates with Travis CI to simplify automatic
package deployment.

[Grinder]: https://pub.dev/packages/grinder

To use this package, import `package:cli_pkg/cli_pkg.dart` and call
[`pkg.addAllTasks()`][] before calling [`grind()`][]:

[`pkg.addAllTasks()`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/addAllTasks.html
[`grind()`]: https://pub.dev/documentation/grinder/latest/grinder/grind.html

```dart
import 'package:cli_pkg/cli_pkg.dart' as pkg;
import 'package:grinder/grinder.dart';

void main(List<String> args) {
  pkg.addAllTasks();
  grind(args);
}
```

The following sets of tasks are provided, each of which can also be enabled
individually:

* [Creating standalone archives for your package.](doc/standalone.md)
* [Uploading standalone archives to GitHub releases.](doc/github.md)
* [Compiling to JavaScript and publishing to npm.](doc/npm.md)
* [Uploading standalone archives to Chocolatey.](doc/chocolatey.md)
* [Updating a Homebrew formula to download from GitHub releases.](doc/homebrew.md)
* [Publishing to pub.](doc/pub.md)

It’s strongly recommended that this package be imported with the prefix `pkg`.

### Configuration

This package is highly configurable through [`ConfigVariable`][] fields defined
[at the top level of the library][]. By default, it infers as much configuration
as possible from the package’s pubspec, but nearly all properties can be
overridden in the `main()` method:

[`ConfigVariable`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/ConfigVariable.html
[at the top level of the library]: https://pub.dev/documentation/sass/latest/sass/sass-library.html#properties

```dart
import 'package:cli_pkg/cli_pkg.dart' as pkg;
import 'package:grinder/grinder.dart';

void main(List<String> args) {
  pkg.name.value = "bot-name";
  pkg.humanName.value = "My App";

  pkg.addAllTasks();
  grind(args);
}
```

`ConfigVariable`s whose values are expensive to compute or might fail under
certain conditions can also be set to callback functions, which are evaluated
lazily when the variables are used by the Grinder tasks:

```dart
import 'package:cli_pkg/cli_pkg.dart' as pkg;
import 'package:grinder/grinder.dart';

void main(List<String> args) {
  pkg.githubReleaseNotes.fn = () => File.read("RELNOTES.md");

  pkg.addAllTasks();
  grind(args);
}
```

Each task specifies exactly which configuration variables it uses. Configuration
specific to a particular set of tasks is always prefixed with a corresponding
name. For example, [`pkg.jsFlags`][] applies to JavaScript compilation.

[`pkg.jsFlags`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/jsFlags.html