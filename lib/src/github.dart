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

import 'package:charcode/charcode.dart';
import 'package:grinder/grinder.dart';
import 'package:path/path.dart' as p;
import 'package:string_scanner/string_scanner.dart';

import 'info.dart';
import 'standalone.dart';
import 'utils.dart';

/// The GitHub repository slug (for example, `username/repo`) to which to upload
/// package releases.
///
/// By default, this determines the repo from Git's `origin` remote, failing
/// that, from the pubspec's `homepage` field. If neither of those is a valid
/// Git URL, this must be set explicitly.
String get githubRepo {
  _githubRepo ??= _repoFromOrigin() ?? _repoFromPubspec();
  if (_githubRepo != null) return _githubRepo;

  fail("pkg.githubRepo must be set to deploy to GitHub.");
}

set githubRepo(String value) => _githubRepo = value;
String _githubRepo;

/// Returns the GitHub repo name from the Git configuration's
/// `remote.origin.url` field.
String _repoFromOrigin() {
  try {
    var result = Process.runSync("git", ["config", "remote.origin.url"]);
    if (result.exitCode != 0) return null;
    var origin = (result.stdout as String).trim();
    return origin.startsWith("http") ? _parseHttp(origin) : _parseGit(origin);
  } on IOException {
    return null;
  }
}

/// Returns the GitHub repo name from the pubspec's `homepage` field.
String _repoFromPubspec() =>
    pubspec.homepage == null ? null : _parseHttp(pubspec.homepage);

/// Parses a GitHub repo name from an SSH reference or a `git://` URL.
///
/// Returns `null` if it couldn't be parsed.
String _parseGit(String url) {
  var match = RegExp(r"^(git@github\.com:|git://github\.com/)"
          r"(?<repo>[^/]+/[^/]+?)(\.git)?$")
      .firstMatch(url);
  return match == null ? null : match.namedGroup('repo');
}

/// Parses a GitHub repo name from an HTTP or HTTPS URL.
///
/// Returns `null` if it couldn't be parsed.
String _parseHttp(String url) {
  var match = RegExp(r"^https?://github\.com/([^/]+/[^/]+?)(\.git)?($|/)")
      .firstMatch(url);
  return match == null ? null : match[1];
}

/// The GitHub username to use when creating releases and making other changes.
///
/// By default, this comes from the `GITHUB_USER` environment variable.
String get githubUser {
  _githubUser ??= Platform.environment["GITHUB_USER"];
  if (_githubUser != null) return _githubUser;

  fail("pkg.githubUser must be set to deploy to GitHub.");
}

set githubUser(String value) => _githubUser = value;
String _githubUser;

/// The GitHub password or authentication token to use when creating releases
/// and making other changes.
///
/// **Do not check this in directly.** This should only come from secure
/// sources.
///
/// This can be either the password itself, a [personal access token][], or an
/// OAuth token.
///
/// [personal access token]: https://github.com/settings/tokens
///
/// By default, this comes from the `GITHUB_PASSWORD` environment variable if it
/// exists, or `GITHUB_TOKEN` otherwise.
String get githubPassword {
  _githubPassword ??= Platform.environment["GITHUB_PASSWORD"] ??
      Platform.environment["GITHUB_TOKEN"];
  if (_githubPassword != null) return _githubPassword;

  fail("pkg.githubPassword must be set to deploy to GitHub.");
}

set githubPassword(String value) => _githubPassword = value;
String _githubPassword;

/// Returns the HTTP basic authentication Authorization header from the
/// environment.
String get _authorization =>
    "Basic ${base64.encode(utf8.encode("$githubUser:$githubPassword"))}";

/// The Markdown-formatted release notes to use for the GitHub release.
///
/// By default, this looks for a `CHANGELOG.md` file at the root of the
/// repository and uses the portion between the first and second level-2 `##`
/// headers. It throws a [FormatException] if the CHANGELOG doesn't begin with
/// `##` followed by [version].
///
/// If this is set to `null`, or by default if no `CHANGELOG.md` exists, no
/// release notes will be added to the GitHub release.
String get githubReleaseNotes {
  if (_githubReleaseNotes != null) return _githubReleaseNotes;
  if (!File("CHANGELOG.md").existsSync()) return null;

  _githubReleaseNotes = _lastChangelogSection() +
      "\n\n"
          "See the [full changelog](https://github.com/$githubRepo/blob/"
          "master/CHANGELOG.md#${version.toString().replaceAll(".", "")}) "
          "for changes in earlier releases.";
  return _githubReleaseNotes;
}

set githubReleaseNotes(String value) => _githubReleaseNotes = value;
String _githubReleaseNotes;

/// Creates a GitHub release for [version] of this package.
///
/// This creates the release on the [githubRepo] repository, using
/// [humanName] as the release name and [githubReleaseNotes] as the
/// release notes.
Future<void> _release() async {
  var response = await client.post(
      url("https://api.github.com/repos/$githubRepo/releases"),
      headers: {
        "content-type": "application/json",
        "authorization": _authorization
      },
      body: jsonEncode({
        "tag_name": version.toString(),
        "name": "$humanName $version",
        "prerelease": version.isPreRelease,
        if (githubReleaseNotes != null) "body": githubReleaseNotes
      }));

  if (response.statusCode != 201) {
    fail("${response.statusCode} error creating release:\n${response.body}");
  } else {
    log("Released $humanName $version to GitHub.");
  }
}

/// A regular expression that matches a Markdown code block.
final _codeBlock = RegExp(" *```");

/// Returns the most recent section in the CHANGELOG, reformatted to remove line
/// breaks that will show up on GitHub.
String _lastChangelogSection() {
  var scanner = StringScanner(File("CHANGELOG.md").readAsStringSync(),
      sourceUrl: "CHANGELOG.md");

  // Scans the remainder of the current line and returns it. This consumes the
  // trailing newline but doesn't return it.
  String scanLine() {
    var buffer = StringBuffer();
    while (!scanner.isDone && scanner.peekChar() != $lf) {
      buffer.writeCharCode(scanner.readChar());
    }
    scanner.scanChar($lf);
    return buffer.toString();
  }

  scanner.expect(RegExp("## $version\r?\n"));

  var buffer = StringBuffer();
  while (!scanner.isDone && !scanner.matches("## ")) {
    if (scanner.matches(_codeBlock)) {
      do {
        buffer.writeln(scanLine());
      } while (!scanner.matches(_codeBlock));
      buffer.writeln(scanLine());
    } else if (scanner.matches(RegExp(" *\n"))) {
      buffer.writeln();
      buffer.writeln(scanLine());
    } else {
      buffer.write(scanLine());
      buffer.writeCharCode($space);
    }
  }

  return buffer.toString().trim();
}

/// Whether [addGithubTasks] has been called yet.
var _addedGithubTasks = false;

/// Enables tasks for releasing the package on GitHub releases.
void addGithubTasks() {
  if (_addedGithubTasks) return;
  _addedGithubTasks = true;

  addStandaloneTasks();

  addTask(GrinderTask('pkg-github-release',
      taskFunction: _release,
      description: 'Create a GitHub release, without executables.'));

  for (var os in ["linux", "macos", "windows"]) {
    addTask(GrinderTask('pkg-github-$os',
        taskFunction: () => _uploadExecutables(os),
        description: 'Release ${humanOSName(os)} executables to GitHub.',
        depends: [
          // Dart as of 2.7 doesn't support 32-bit Mac OS executables.
          if (os != "macos")
            'pkg-standalone-$os-ia32',
          'pkg-standalone-$os-x64'
        ]));
  }

  addTask(GrinderTask('pkg-github-all',
      description: 'Create a GitHub release with all executables.',
      depends: [
        'pkg-github-release',
        'pkg-github-linux',
        'pkg-github-macos',
        'pkg-github-windows'
      ]));
}

/// Upload the 32- and 64-bit executables to the current GitHub release
Future<void> _uploadExecutables(String os) async {
  var response = await client.get(
      url("https://api.github.com/repos/$githubRepo/releases/tags/$version"),
      headers: {"authorization": _authorization});

  var body = json.decode(response.body);
  var uploadUrlTemplate = body["upload_url"];
  if (uploadUrlTemplate == null) {
    throw 'Unexpected GitHub response, expected "upload_url" field:\n' +
        JsonEncoder.withIndent("  ").convert(body);
  }

  // Remove the URL template.
  var uploadUrl = uploadUrlTemplate.replaceFirst(RegExp(r"\{[^}]+\}$"), "");

  await Future.wait([
    // Dart as of 2.7 doesn't support 32-bit Mac OS executables.
    if (os != "macos")
      "ia32",
    "x64"
  ].map((architecture) async {
    var format = os == "windows" ? "zip" : "tar.gz";
    var package = "$standaloneName-$version-$os-$architecture.$format";
    var response = await client.post("$uploadUrl?name=$package",
        headers: {
          "content-type":
              os == "windows" ? "application/zip" : "application/gzip",
          "authorization": _authorization
        },
        body: File(p.join("build", package)).readAsBytesSync());

    if (response.statusCode != 201) {
      fail("${response.statusCode} error uploading $package:\n"
          "${response.body}");
    } else {
      log("Uploaded $package.");
    }
  }));
}
