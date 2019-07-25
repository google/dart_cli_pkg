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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:charcode/charcode.dart';
import 'package:grinder/grinder.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:string_scanner/string_scanner.dart';

import 'standalone.dart';
import 'src/info.dart';
import 'src/utils.dart';

/// The GitHub repository slug (for example, `username/repo`) to which to upload
/// package releases.
///
/// By default, this determines the repo from Git's `origin` remote, failing
/// that, from the pubspec's `homepage` field. If neither of those is a valid
/// Git URL, this must be set explicitly.
String get pkgGithubRepo {
  _pkgGithubRepo ??= _repoFromOrigin() ?? _repoFromPubspec();
  if (_pkgGithubRepo != null) return _pkgGithubRepo;

  fail("pkgGithubRepo must be set to deploy to GitHub.");
}

set pkgGithubRepo(String value) => _pkgGithubRepo = value;
String _pkgGithubRepo;

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
  var match = RegExp(r"^https?://github\.com/([^/]+/[^/]+)").firstMatch(url);
  return match == null ? null : match[1];
}

/// The GitHub username to use when creating releases and making other changes.
///
/// By default, this comes from the `GITHUB_USER` environment variable.
String get pkgGithubUser {
  _pkgGithubUser ??= Platform.environment["GITHUB_USER"];
  if (_pkgGithubUser != null) return _pkgGithubUser;

  fail("pkgGithubUser must be set to deploy to GitHub.");
}

set pkgGithubUser(String value) => _pkgGithubUser = value;
String _pkgGithubUser;

/// The GitHub password or authentication token to use when creating releases
/// and making other changes.
///
/// **Do not check this in directly.** This should only come from secure
/// sources.
///
/// This can be either the username itself, a [personal access token][], or an
/// OAuth token.
///
/// [personal access token]: https://github.com/settings/tokens
///
/// By default, this comes from the `GITHUB_PASSWORD` environment variable if it
/// exists, or `GITHUB_TOKEN` otherwise.
String get pkgGithubPassword {
  _pkgGithubPassword ??= Platform.environment["GITHUB_PASSWORD"] ??
      Platform.environment["GITHUB_TOKEN"];
  if (_pkgGithubPassword != null) return _pkgGithubPassword;

  fail("pkgGithubPassword must be set to deploy to GitHub.");
}

set pkgGithubPassword(String value) => _pkgGithubPassword = value;
String _pkgGithubPassword;

/// Returns the HTTP basic authentication Authorization header from the
/// environment.
String get _authorization =>
    "Basic ${base64.encode(utf8.encode("$pkgGithubUser:$pkgGithubPassword"))}";

/// The Markdown-formatted release notes to use for the GitHub release.
///
/// By default, this looks for a `CHANGELOG.md` file at the root of the
/// repository and uses the portion between the first and second level-2 `##`
/// headers. It throws a [FormatException] if the CHANGELOG doesn't begin with
/// `##` followed by [pkgVersion].
String get pkgGithubReleaseNotes {
  if (_pkgGithubReleaseNotes != null) return _pkgGithubReleaseNotes;
  if (!File("CHANGELOG.md").existsSync()) return null;

  _pkgGithubReleaseNotes = _lastChangelogSection() +
      "\n\n"
          "See the [full changelog](https://github.com/$pkgGithubRepo/blob/"
          "master/CHANGELOG.md#${pkgVersion.toString().replaceAll(".", "")}) "
          "for changes in earlier releases.";
  return _pkgGithubReleaseNotes;
}

set pkgGithubReleaseNotes(String value) => _pkgGithubReleaseNotes = value;
String _pkgGithubReleaseNotes;

/// Creates a GitHub release for [pkgVersion] of this package.
///
/// This creates the release on the [pkgGithubRepo] repository, using
/// [pkgHumanName] as the release name and [pkgGithubReleaseNotes] as the
/// release notes.
@Task('Create a GitHub release, without executables.')
Future<void> pkgGithubRelease({http.Client client}) async {
  var response = await withClient(client, (client) {
    return client.post(
        url("https://api.github.com/repos/$pkgGithubRepo/releases"),
        headers: {
          "content-type": "application/json",
          "authorization": _authorization
        },
        body: jsonEncode({
          "tag_name": pkgVersion.toString(),
          "name": "$pkgHumanName $pkgVersion",
          "prerelease": pkgVersion.isPreRelease,
          if (pkgGithubReleaseNotes != null) "body": pkgGithubReleaseNotes
        }));
  });

  if (response.statusCode != 201) {
    fail("${response.statusCode} error creating release:\n${response.body}");
  } else {
    log("Released $pkgHumanName $pkgVersion to GitHub.");
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

  scanner.expect("## $pkgVersion\n");

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

/// Uploads 32- and 64-bit Linux executable packages to the GitHub release for
/// the current version.
///
/// This uploads the archives generated by [pkgStandaloneLinuxIa32] and
/// [pkgStandaloneLinuxX64]. It must be invoked after [pkgGithubRelease], but it
/// does not automatically invoke [pkgGithubRelease] to allow for different
/// operating systems' executables to be uploaded in separate steps.
///
/// If this is run on Linux, the 64-bit executable is built as a native
/// executable. If it's run on any other operating system, it's built as a
/// snapshot instead, which is substantially slower.
@Task('Release Linux executables to GitHub.')
Future<void> pkgGithubLinux({http.Client client}) async {
  await pkgCompileSnapshot();
  await withClient(client, (client) async {
    await Future.wait([
      pkgStandaloneLinuxIa32(client: client),
      pkgStandaloneLinuxX64(client: client)
    ]);
    await _uploadExecutables("linux", client: client);
  });
}

/// Uploads 32- and 64-bit Mac OS executable packages to the GitHub release for
/// the current version.
///
/// This uploads the archives generated by [pkgStandaloneMacOsIa32] and
/// [pkgStandaloneMacOsX64]. It must be invoked after [pkgGithubRelease], but it
/// does not automatically invoke [pkgGithubRelease] to allow for different
/// operating systems' executables to be uploaded in separate steps.
///
/// If this is run on Mac OS, the 64-bit executable is built as a native
/// executable. If it's run on any other operating system, it's built as a
/// snapshot instead, which is substantially slower.
@Task('Release Mac OS executables to GitHub.')
Future<void> pkgGithubMacOs({http.Client client}) async {
  await pkgCompileSnapshot();
  await withClient(client, (client) async {
    await Future.wait([
      pkgStandaloneMacOsIa32(client: client),
      pkgStandaloneMacOsX64(client: client)
    ]);
    await _uploadExecutables("macos", client: client);
  });
}

/// Uploads 32- and 64-bit Windows executable packages to the GitHub release for
/// the current version.
///
/// This uploads the archives generated by [pkgStandaloneWindowsIa32] and
/// [pkgStandaloneWindowsX64]. It must be invoked after [pkgGithubRelease], but it
/// does not automatically invoke [pkgGithubRelease] to allow for different
/// operating systems' executables to be uploaded in separate steps.
///
/// If this is run on Windows, the 64-bit executable is built as a native
/// executable. If it's run on any other operating system, it's built as a
/// snapshot instead, which is substantially slower.
@Task('Release Windows executables to GitHub.')
Future<void> pkgGithubWindows({http.Client client}) async {
  await pkgCompileSnapshot();
  await withClient(client, (client) async {
    await Future.wait([
      pkgStandaloneWindowsIa32(client: client),
      pkgStandaloneWindowsX64(client: client)
    ]);
    await _uploadExecutables("windows", client: client);
  });
}

/// Creates a GitHub release for [pkgVersion] of this package and uploads 32-
/// and 64-bit Linux, Mac OS, and Windows executables for this package.
///
/// This creates the GitHub release using [pkgGithubRelease] and uploads
/// archives generated by [pkgStandaloneLinuxIa32], [pkgStandaloneLinuxX64],
/// [pkgStandaloneMacOsIa32], [pkgStandaloneMacOsX64],
/// [pkgStandaloneWindowsIa32], and [pkgStandaloneWindowsX64].
///
/// Note that this will only build native executables for the operating system
/// it's invoked on. All other operating systems' executables will be built as
/// snapshots, which are substantially slower. To build all snapshots as native
/// executables, invoke the individual [pkgGithubLinux], [pkgGithubMacOs], and
/// [pkgGithubWindows] tasks on their respective oeprating systems.
@Task('Create a GitHub release with all executables.')
Future<void> pkgGithubAll({http.Client client}) async {
  await withClient(client, (client) async {
    await pkgGithubRelease(client: client);
    await Future.wait([
      pkgGithubLinux(client: client),
      pkgGithubMacOs(client: client),
      pkgGithubWindows(client: client)
    ]);
  });
}

/// Upload the 32- and 64-bit executables to the current GitHub release
Future<void> _uploadExecutables(String os, {http.Client client}) async {
  return withClient(client, (client) async {
    var response = await client.get(
        url("https://api.github.com/repos/$pkgGithubRepo/tags/$pkgVersion"),
        headers: {"authorization": _authorization});

    var uploadUrl = json
        .decode(response.body)["upload_url"]
        // Remove the URL template.
        .replaceFirst(RegExp(r"\{[^}]+\}$"), "");

    await Future.wait(["ia32", "x64"].map((architecture) async {
      var format = os == "windows" ? "zip" : "tar.gz";
      var package = "$pkgStandaloneName-$pkgVersion-$os-$architecture.$format";
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
  });
}
