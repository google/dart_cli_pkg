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
import 'package:async/async.dart';
import 'package:grinder/grinder.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';

import 'config_variable.dart';
import 'info.dart';
import 'standalone.dart';
import 'last_changelog_section.dart';
import 'utils.dart';

/// The GitHub repository slug (for example, `username/repo`) to which to upload
/// package releases.
///
/// By default, this determines the repo from Git's `origin` remote, failing
/// that, from the pubspec's `homepage` field. If neither of those is a valid
/// Git URL, this must be set explicitly.
final githubRepo = InternalConfigVariable.fn<String>(() =>
    _repoFromOrigin() ??
    _parseHttp(pubspec.homepage ?? '') ??
    fail("pkg.githubRepo must be set to deploy to GitHub."));

/// A regular expression for finding the next link in a paginated list of
/// results.
///
/// As suggested by https://docs.github.com/en/rest/guides/using-pagination-in-the-rest-api?apiVersion=2022-11-28.
final _nextLink =
    RegExp(r'(?<=<)([\S]*)(?=>; rel="next")', caseSensitive: false);

/// Returns the GitHub repo name from the Git configuration's
/// `remote.origin.url` field.
String? _repoFromOrigin() {
  try {
    var result = Process.runSync("git", ["config", "remote.origin.url"]);
    if (result.exitCode != 0) return null;
    var origin = (result.stdout as String).trim();
    return origin.startsWith("http") ? _parseHttp(origin) : _parseGit(origin);
  } on IOException {
    return null;
  }
}

/// Parses a GitHub repo name from an SSH reference or a `git://` URL.
///
/// Returns `null` if it couldn't be parsed.
String? _parseGit(String url) =>
    RegExp(r"^(git@github\.com:|git://github\.com/)"
            r"(?<repo>[^/]+/[^/]+?)(\.git)?$")
        .firstMatch(url)
        ?.namedGroup('repo');

/// Parses a GitHub repo name from an HTTP or HTTPS URL.
///
/// Returns `null` if it couldn't be parsed.
String? _parseHttp(String url) {
  var match = RegExp(r"^https?://github\.com/([^/]+/[^/]+?)(\.git)?($|/)")
      .firstMatch(url);
  return match == null ? null : match[1];
}

/// The GitHub username to use when creating releases and making other changes.
///
/// If you're using [GitHub Actions' `GITHUB_TOKEN` secret], you should use
/// [githubBearerToken] instead.
///
/// [GitHub Actions' `GITHUB_TOKEN` secret]: https://docs.github.com/en/actions/reference/authentication-in-a-workflow
///
/// By default, this comes from the `GITHUB_USER` environment variable.
final githubUser = InternalConfigVariable.fn<String>(() =>
    Platform.environment["GITHUB_USER"] ??
    fail("pkg.githubUser or pkg.githubBearerToken must be set to deploy to "
        "GitHub."));

/// The GitHub password or authentication token to use when creating releases
/// and making other changes.
///
/// **Do not check this in directly.** This should only come from secure
/// sources.
///
/// This can be either the password itself, a [personal access token][], or an
/// OAuth token. If you're using [GitHub Actions' `GITHUB_TOKEN` secret], you
/// should use [githubBearerToken] instead.
///
/// [personal access token]: https://github.com/settings/tokens
/// [GitHub Actions' `GITHUB_TOKEN` secret]: https://docs.github.com/en/actions/reference/authentication-in-a-workflow
///
/// By default, this comes from the `GITHUB_PASSWORD` environment variable if it
/// exists, or `GITHUB_TOKEN` otherwise.
final githubPassword = InternalConfigVariable.fn<String>(() =>
    Platform.environment["GITHUB_PASSWORD"] ??
    Platform.environment["GITHUB_TOKEN"] ??
    fail("pkg.githubPassword or pkg.githubBearerToken must be set to deploy to "
        "GitHub."));

/// The GitHub token to use for [bearer authorization].
///
/// [bearer authorization]: https://tools.ietf.org/html/rfc6750
///
/// **Do not check this in directly.** This should only come from secure
/// sources.
///
/// This is an alternate way of authenticating a GitHub account, rather than
/// using [githubUser] and [githubPassword]. It's only documented to work with
/// [GitHub Actions' `GITHUB_TOKEN` secret], so if you aren't specifically using
/// that it's better to use [githubUser] and [githubPassword].
///
/// [GitHub Actions' `GITHUB_TOKEN` secret]: https://docs.github.com/en/actions/reference/authentication-in-a-workflow
///
/// Note that this can only be used for GitHub actions directly, not for
/// Homebrew actions.
///
/// By default, this comes from the `GITHUB_BEARER_TOKEN` environment variable.
/// If it's set, it's used in preference to [githubUser] and [githubPassword].
/// To override this behavior, set its value to `null`.
final githubBearerToken = InternalConfigVariable.value<String?>(
    Platform.environment["GITHUB_BEARER_TOKEN"]);

/// Returns the HTTP basic authentication Authorization header from the
/// environment.
String get _authorization {
  var bearerToken = githubBearerToken.value;
  return bearerToken != null
      ? "Bearer $bearerToken"
      : "Basic ${base64.encode(utf8.encode("$githubUser:$githubPassword"))}";
}

/// The Markdown-formatted release notes to use for the GitHub release.
///
/// By default, this looks for a `CHANGELOG.md` file at the root of the
/// repository and uses the portion between the first and second level-2 `##`
/// headers. It throws a [FormatException] if the CHANGELOG doesn't begin with
/// `##` followed by [version].
///
/// If this is set to `null`, or by default if no `CHANGELOG.md` exists, no
/// release notes will be added to the GitHub release.
final githubReleaseNotes = InternalConfigVariable.fn<String?>(() {
  if (!File("CHANGELOG.md").existsSync()) return null;

  return lastChangelogSection(File("CHANGELOG.md").readAsStringSync(), version,
          sourceUrl: "CHANGELOG.md") +
      "\n\n"
          "See the [full changelog](https://github.com/$githubRepo/blob/"
          "master/CHANGELOG.md#${version.toString().replaceAll(".", "")}) "
          "for changes in earlier releases.";
});

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
        if (githubReleaseNotes.value != null) "body": githubReleaseNotes.value
      }));

  if (response.statusCode != 201) {
    fail("${response.statusCode} error creating release:\n${response.body}");
  } else {
    log("Released $humanName $version to GitHub.");
  }
}

/// Whether [addGithubTasks] has been called yet.
var _addedGithubTasks = false;

/// Enables tasks for releasing the package on GitHub releases.
void addGithubTasks() {
  if (_addedGithubTasks) return;
  _addedGithubTasks = true;

  freezeSharedVariables();
  githubRepo.freeze();
  githubUser.freeze();
  githubPassword.freeze();
  githubBearerToken.freeze();
  githubReleaseNotes.freeze();

  addStandaloneTasks();

  addTask(GrinderTask('pkg-github-release',
      taskFunction: _release,
      description: 'Create a GitHub release, without executables.'));

  var osTasks = osToArchs.entries.map((entry) {
    var os = entry.key;
    var archTasks = entry.value
        .map((arch) => GrinderTask('pkg-github-$os-$arch',
            taskFunction: () => _uploadExecutables(os, arch),
            description:
                'Release ${humanOSName(os)} $arch executables to GitHub.',
            depends: ['pkg-standalone-$os-$arch']))
        .toList();
    archTasks.forEach(addTask);

    return GrinderTask('pkg-github-$os',
        description: 'Release ${humanOSName(os)} executables to GitHub.',
        depends: archTasks.map((task) => task.name));
  }).toList();
  osTasks.forEach(addTask);

  var dependencies = ['pkg-github-release'];
  dependencies.addAll(osTasks.map((task) => task.name));

  addTask(GrinderTask('pkg-github-all',
      description: 'Create a GitHub release with all executables.',
      depends: dependencies));

  addTask(GrinderTask('pkg-github-fix-permissions',
      description: 'Fix insecure permissions for older GitHub releases.\n'
          'See https://sass-lang.com/blog/security-alert-tar-permissions',
      taskFunction: _fixPermissions));
}

/// Upload an executable for the given [os] and [arch] to the current GitHub
/// release.
Future<void> _uploadExecutables(String os, String arch) async {
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

  var format = os == "windows" ? "zip" : "tar.gz";
  var package = "$standaloneName-$version-$os-$arch.$format";
  response = await client.post(Uri.parse("$uploadUrl?name=$package"),
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
}

/// Update permissions of old releases to ensure that they aren't listed as
/// group/all writeable.
Future<void> _fixPermissions() async {
  var pool = Pool(5);
  var group = FutureGroup<void>();
  var count = 0;
  await for (var release
      in _getPaginated("https://api.github.com/repos/$githubRepo/releases")) {
    var assets =
        (release["assets"] as List<dynamic>).cast<Map<String, dynamic>>();
    for (var asset in assets) {
      if (!(asset["name"] as String).endsWith(".tar.gz")) continue;

      group.add(pool.withResource(() async {
        var assetResponse = await client.get(
            url(asset["browser_download_url"] as String),
            headers: {"authorization": _authorization});
        var archive = TarDecoder()
            .decodeBytes(GZipDecoder().decodeBytes(assetResponse.bodyBytes));
        for (var file in archive.files) {
          // 0o755: ensure that the write permission bits aren't set for
          // non-owners.
          file.mode &= 493;
        }
        await client.patch(url(asset["url"] as String),
            headers: {"authorization": _authorization},
            body: GZipEncoder().encode(TarEncoder().encode(archive)));

        count++;
        stdout.write("\rUpdated archives: $count");
      }));
    }
  }

  group.close();
  await group.future;
  stdout.writeln();
}

/// Makes a GET request to [url] and returns the parsed JSON results,
/// potentially across multiple pages.
Stream<Map<String, dynamic>> _getPaginated(String firstUrl) async* {
  var nextUrl = url(firstUrl);

  while (true) {
    var response =
        await client.get(nextUrl, headers: {"authorization": _authorization});
    for (var result in json.decode(response.body) as List<dynamic>) {
      yield result as Map<String, dynamic>;
    }

    var link = response.headers["link"];
    if (link == null) return;

    var match = _nextLink.firstMatch(link);
    if (match == null) return;

    nextUrl = url(match[1]!);
  }
}
