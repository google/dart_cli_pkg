## Dart CLI Packager

This package provides a set of [Grinder][] tasks that make it easy to release a
Dart command-line application on many different release channels, to Dart users
and non-Dart users alike. It also integrates with Travis CI to make it easy to
automatically deploy packages.

[Grinder]: https://pub.dev/packages/grinder

To use this package, import `package:cli_pkg/cli_pkg.dart` and call
[`pkg.addAllTasks()`][] before calling [`grind()`][]:

[`pkg.addAllTasks()`]: https://pub.dev/documentation/dart_cli_pkg/latest/cli_pkg/addAllTasks.html
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

It's strongly recommended that this package be imported with the prefix `pkg`.
