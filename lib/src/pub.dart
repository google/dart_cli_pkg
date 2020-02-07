// Copyright 2019 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:convert';
import 'dart:io';

import 'package:grinder/grinder.dart';
import 'package:path/path.dart' as p;

import 'utils.dart';

/// The entire contents of pub's `~/.pub-cache/credentials.json` file.
///
/// **Do not check this in directly.** This should only come from secure
/// sources.
///
/// By default this comes from the `PUB_CREDENTIALS` environment variable.
String get pubCredentials {
  _pubCredentials ??= Platform.environment["PUB_CREDENTIALS"];
  if (_pubCredentials != null) return _pubCredentials;

  fail("pkg.pubCredentials must be set to deploy to pub.");
}

set pubCredentials(String value) => _pubCredentials = value;
String _pubCredentials;

/// The path in which pub expects to find its credentials file.
final String _credentialsPath = () {
  // This follows the same logic as pub:
  // https://github.com/dart-lang/pub/blob/d99b0d58f4059d7bb4ac4616fd3d54ec00a2b5d4/lib/src/system_cache.dart#L34-L43
  String cacheDir;
  if (Platform.environment.containsKey('PUB_CACHE')) {
    cacheDir = Platform.environment['PUB_CACHE'];
  } else if (Platform.isWindows) {
    var appData = Platform.environment['APPDATA'];
    cacheDir = p.join(appData, 'Pub', 'Cache');
  } else {
    cacheDir = p.join(Platform.environment['HOME'], '.pub-cache');
  }

  return p.join(cacheDir, 'credentials.json');
}();

/// Whether [addPubTasks] has been called yet.
var _addedPubTasks = false;

/// Enables tasks for uploading the package to Pub.
void addPubTasks() {
  if (_addedPubTasks) return;
  _addedPubTasks = true;

  addTask(GrinderTask('pkg-pub-deploy',
      taskFunction: () => _deploy(),
      description: 'Deploy the package to Pub.'));
}

// Deploy the Pub package to Pub.
Future<void> _deploy() async {
  Directory(p.dirname(_credentialsPath)).createSync(recursive: true);

  File(_credentialsPath).openSync(mode: FileMode.writeOnlyAppend)
    ..writeStringSync(pubCredentials)
    ..closeSync();

  log("pub publish");
  var process = await Process.start(
      p.join(sdkDir.path, "bin/pub$dotBat"), ["publish", "--force"]);
  LineSplitter().bind(utf8.decoder.bind(process.stdout)).listen(log);
  LineSplitter().bind(utf8.decoder.bind(process.stderr)).listen(log);
  if (await process.exitCode != 0) fail("pub publish failed");
}
