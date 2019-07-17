// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';

/// Runs [grinder] in the application directory with the given [arguments].
///
/// Runs `pub get` first.
///
/// The [environment] and [forwardStdio] arguments have the same meanings as for
/// [TestProcess.start].
Future<TestProcess> grind(List<String> arguments,
    {Map<String, String> environment, bool forwardStdio = false}) async {
  var directory = Directory(d.sandbox).listSync().single.path;

  await (await TestProcess.start("pub", ["get", "--offline", "--no-precompile"],
          forwardStdio: forwardStdio, workingDirectory: directory))
      .shouldExit(0);

  return await TestProcess.start("pub", ["run", "grinder", ...arguments],
      forwardStdio: forwardStdio,
      workingDirectory: directory,
      environment: {...?environment, "_CLI_PKG_TESTING": "true"});
}

/// Extracts the contents of [archive] to [destination], both within `d.sandbox`.
Future<void> extract(String path, String destination) async {
  var bytes = File(d.path(path)).readAsBytesSync();
  var archive = path.endsWith(".zip")
      ? ZipDecoder().decodeBytes(bytes)
      : TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));

  for (var file in archive.files) {
    var filePath = p.join(d.path(destination), file.name);
    Directory(p.dirname(filePath)).createSync(recursive: true);
    File(filePath).writeAsBytesSync(file.content as List<int>);

    // Mark the file executable if necessary.
    if (!Platform.isWindows && file.mode & 1 == 1) {
      await (await TestProcess.start("chmod", ["a+x", filePath])).shouldExit(0);
    }
  }
}
