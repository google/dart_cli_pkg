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

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:pub_semver/pub_semver.dart';

import 'info.dart';

/// The set of entrypoint for executables defined by this package.
Set<String> get entrypoints => pkgExecutables.values.toSet();

/// The version of the current Dart executable.
final Version dartVersion = Version.parse(Platform.version.split(" ").first);

/// Whether we're using a dev Dart SDK.
bool get isDevSdk => dartVersion.isPreRelease;

/// Ensure that the `build/` directory exists.
void ensureBuild() {
  Directory('build').createSync(recursive: true);
}

/// Creates an [ArchiveFile] with the given [path] and [data].
///
/// If [executable] is `true`, this marks the file as executable.
ArchiveFile fileFromBytes(String path, List<int> data,
        {bool executable = false}) =>
    ArchiveFile(path, data.length, data)
      ..mode = executable ? 495 : 428
      ..lastModTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// Creates a UTF-8-encoded [ArchiveFile] with the given [path] and [contents].
///
/// If [executable] is `true`, this marks the file as executable.
ArchiveFile fileFromString(String path, String contents,
        {bool executable = false}) =>
    fileFromBytes(path, utf8.encode(contents), executable: executable);

/// Creates an [ArchiveFile] at the archive path [target] from the local file at
/// [source].
///
/// If [executable] is `true`, this marks the file as executable.
ArchiveFile file(String target, String source, {bool executable = false}) =>
    fileFromBytes(target, File(source).readAsBytesSync(),
        executable: executable);
