// Copyright 2019 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:convert';
import 'dart:io';

import 'package:cli_util/cli_util.dart';
import 'package:grinder/grinder.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'config_variable.dart';
import 'utils.dart';

/// The entire contents of the `pub-credentials.json` file.
///
/// **Do not check this in directly.** This should only come from secure
/// sources.
///
/// You can find your current `pub-credentials.json` in the following locations:
///
/// * Dart prior to 2.15.0: `$HOME/.pub-cache/credentials.json`.
/// * Linux: `$XDG_CONFIG_HOME/dart/pub-credentials.json` if `$XDG_CONFIG_HOME`
///   is defined, otherwise `$HOME/.config/dart/pub-credentials.json`.
/// * Mac OS: `$HOME/Library/Application Support/dart/pub-credentials.json`
/// * Windows: `%APPDATA%/dart/pub-credentials.json`
///
/// By default this comes from the `PUB_CREDENTIALS` environment variable.
final pubCredentials = InternalConfigVariable.fn<String>(
  () =>
      Platform.environment["PUB_CREDENTIALS"] ??
      fail("pkg.pubCredentials must be set to deploy to pub."),
);

/// The path in which pub expects to find its credentials file.
final String _credentialsPath = () {
  // This follows the same logic as pub.
  if (dartVersion >= Version.parse('2.15.0')) {
    // https://github.com/dart-lang/pub/blob/a16763a93b5050c6a9d917fca5a132cfcb00f1a9/doc/cache_layout.md#layout
    return p.join(applicationConfigHome('dart'), 'pub-credentials.json');
  }

  // https://github.com/dart-lang/pub/blob/d99b0d58f4059d7bb4ac4616fd3d54ec00a2b5d4/lib/src/system_cache.dart#L34-L43
  String cacheDir;
  var pubCache = Platform.environment['PUB_CACHE'];
  if (pubCache != null) {
    cacheDir = pubCache;
  } else if (Platform.isWindows) {
    var appData = Platform.environment['APPDATA']!;
    cacheDir = p.join(appData, 'Pub', 'Cache');
  } else {
    cacheDir = p.join(Platform.environment['HOME']!, '.pub-cache');
  }

  return p.join(cacheDir, 'credentials.json');
}();

/// Whether [addPubTasks] has been called yet.
var _addedPubTasks = false;

/// Enables tasks for uploading the package to Pub.
void addPubTasks() {
  if (_addedPubTasks) return;
  _addedPubTasks = true;

  pubCredentials.freeze();

  addTask(
    GrinderTask(
      'pkg-pub-deploy',
      taskFunction: () => _deploy(),
      description: 'Deploy the package to Pub.',
    ),
  );
}

// Deploy the Pub package to Pub.
Future<void> _deploy() async {
  Directory(p.dirname(_credentialsPath)).createSync(recursive: true);

  File(_credentialsPath).openSync(mode: FileMode.writeOnlyAppend)
    ..writeStringSync(pubCredentials.value)
    ..closeSync();

  log("dart pub publish");
  var process = await Process.start(p.join(sdkDir.path, "bin/dart$dotExe"), [
    "pub",
    "publish",
    "--force",
  ]);
  LineSplitter().bind(utf8.decoder.bind(process.stdout)).listen(log);
  LineSplitter().bind(utf8.decoder.bind(process.stderr)).listen(log);
  if (await process.exitCode != 0) fail("dart pub publish failed");
}
