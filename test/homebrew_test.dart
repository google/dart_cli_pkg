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

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_test_handler/shelf_test_handler.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'descriptor.dart' as d;
import 'utils.dart';

void main() {
  var pubspec = {"name": "my_app", "version": "1.2.3"};

  test("throws an error without pkg.homebrewRepo", () async {
    await d.package(pubspec, _enableHomebrew(repo: false)).create();
    await _makeRepo("my_app");
    await git(["tag", "1.2.3"]);

    await _createHomebrewRepo();

    var server = await _serveArchive();
    var process = await _homebrewUpdate(server);
    expect(
      process.stdout,
      emitsThrough(
        contains("pkg.homebrewRepo must be set to deploy to Homebrew."),
      ),
    );
    await process.shouldExit(1);
    await server.close();
  });

  test("throws an error if url doesn't exist", () async {
    await d.package(pubspec, _enableHomebrew()).create();
    await _makeRepo("my_app");
    await git(["tag", "1.2.3"]);

    await d.dir("me/homebrew.git", [
      d.file("my_app.rb", """
          class MyApp < Formula
            sha256 "original sha"
          end
        """),
    ]).create();
    await _makeRepo("me/homebrew.git");

    var server = await _serveArchive();
    var process = await _homebrewUpdate(server);
    expect(
      process.stdout,
      emitsThrough(
        contains(
          "Couldn't find a url field in "
          "${p.join('build', 'homebrew', 'my_app.rb')}.",
        ),
      ),
    );
    await process.shouldExit(1);
    await server.close();
  });

  test("throws an error if sha256 doesn't exist", () async {
    await d.package(pubspec, _enableHomebrew()).create();
    await _makeRepo("my_app");
    await git(["tag", "1.2.3"]);

    await d.dir("me/homebrew.git", [
      d.file("my_app.rb", """
          class MyApp < Formula
            url "original url"
          end
        """),
    ]).create();
    await _makeRepo("me/homebrew.git");

    var server = await _serveArchive();
    var process = await _homebrewUpdate(server);
    expect(
      process.stdout,
      emitsThrough(
        contains(
          "Couldn't find a sha256 field in "
          "${p.join('build', 'homebrew', 'my_app.rb')}.",
        ),
      ),
    );
    await process.shouldExit(1);
    await server.close();
  });

  test("updates a Homebrew formula with default settings", () async {
    await d.package(pubspec, _enableHomebrew()).create();
    await _makeRepo("my_app");
    await git(["tag", "1.2.3"]);

    await _createHomebrewRepo();
    var server = await _serveArchive();
    await (await _homebrewUpdate(server)).shouldExit(0);
    await server.close();

    await _assertFormula(
      allOf([
        contains('url "https://github.com/me/app/archive/1.2.3.tar.gz"'),
        matches(RegExp(r'sha256 "[a-f0-9]{64}"')),
      ]),
    );

    expect(await _lastCommitMessage(), equals("Update my_app to 1.2.3"));
  });

  test("updates a Homebrew formula for a prerelease", () async {
    await d.package(
      {...pubspec, "version": "1.2.3-beta.1"},
      _enableHomebrew(
        config: "pkg.homebrewCreateVersionedFormula.value = false;",
      ),
    ).create();
    await _makeRepo("my_app");
    await git(["tag", "1.2.3-beta.1"]);

    await _createHomebrewRepo();
    var server = await _serveArchive("1.2.3-beta.1");
    await (await _homebrewUpdate(server)).shouldExit(0);
    await server.close();

    await _assertFormula(
      allOf([
        contains('url "https://github.com/me/app/archive/1.2.3-beta.1.tar.gz"'),
        matches(RegExp(r'sha256 "[a-f0-9]{64}"')),
      ]),
    );

    await d
        .nothing(p.join("me/homebrew.git", "my_app@1.2.3-beta.1.rb"))
        .validate();

    expect(await _lastCommitMessage(), equals("Update my_app to 1.2.3-beta.1"));
  });

  group("creates a new Homebrew formula", () {
    test("for a pre-release version by default", () async {
      await d.package({
        ...pubspec,
        "version": "1.2.3-beta.1",
      }, _enableHomebrew()).create();
      await _makeRepo("my_app");
      await git(["tag", "1.2.3-beta.1"]);

      await _createHomebrewRepo();
      var server = await _serveArchive("1.2.3-beta.1");
      await (await _homebrewUpdate(server)).shouldExit(0);
      await server.close();

      await _assertFormula(
        allOf([
          contains('url "original url"'),
          contains(r'sha256 "original sha"'),
        ]),
      );

      await _assertFormula(
        allOf([
          contains('class MyAppAT123Beta1 < Formula'),
          contains(
            'url "https://github.com/me/app/archive/1.2.3-beta.1.tar.gz"',
          ),
          matches(RegExp(r'sha256 "[a-f0-9]{64}"')),
        ]),
        path: "my_app@1.2.3-beta.1.rb",
      );

      expect(
        await _lastCommitMessage(),
        equals("Add a formula for my_app 1.2.3-beta.1"),
      );
    });

    test("for a release version", () async {
      await d
          .package(
            pubspec,
            _enableHomebrew(
              config: "pkg.homebrewCreateVersionedFormula.value = true;",
            ),
          )
          .create();
      await _makeRepo("my_app");
      await git(["tag", "1.2.3"]);

      await _createHomebrewRepo();
      var server = await _serveArchive();
      await (await _homebrewUpdate(server)).shouldExit(0);
      await server.close();

      await _assertFormula(
        allOf([
          contains('url "original url"'),
          contains(r'sha256 "original sha"'),
        ]),
      );

      await _assertFormula(
        allOf([
          contains('class MyAppAT123 < Formula'),
          contains('url "https://github.com/me/app/archive/1.2.3.tar.gz"'),
          matches(RegExp(r'sha256 "[a-f0-9]{64}"')),
        ]),
        path: "my_app@1.2.3.rb",
      );

      expect(
        await _lastCommitMessage(),
        equals("Add a formula for my_app 1.2.3"),
      );
    });

    test("for a release version with a build identifier", () async {
      await d.package(
        {...pubspec, "version": "1.2.3+foo.1"},
        _enableHomebrew(
          config: "pkg.homebrewCreateVersionedFormula.value = true;",
        ),
      ).create();
      await _makeRepo("my_app");
      await git(["tag", "1.2.3+foo.1"]);

      await _createHomebrewRepo();
      var server = await _serveArchive("1.2.3+foo.1");
      await (await _homebrewUpdate(server)).shouldExit(0);
      await server.close();

      await _assertFormula(
        allOf([
          contains('url "original url"'),
          contains(r'sha256 "original sha"'),
        ]),
      );

      await _assertFormula(
        allOf([
          contains('class MyAppAT123xfoo1 < Formula'),
          contains(
            'url "https://github.com/me/app/archive/1.2.3+foo.1.tar.gz"',
          ),
          matches(RegExp(r'sha256 "[a-f0-9]{64}"')),
        ]),
        path: "my_app@1.2.3+foo.1.rb",
      );

      expect(
        await _lastCommitMessage(),
        equals("Add a formula for my_app 1.2.3+foo.1"),
      );
    });
  });

  test("uses the human name in the commit message", () async {
    await d
        .package(
          pubspec,
          _enableHomebrew(config: 'pkg.humanName.value = "My App";'),
        )
        .create();
    await _makeRepo("my_app");
    await git(["tag", "1.2.3"]);

    await _createHomebrewRepo();
    var server = await _serveArchive();
    await (await _homebrewUpdate(server)).shouldExit(0);
    await server.close();

    expect(await _lastCommitMessage(), equals("Update My App to 1.2.3"));
  });

  test("can use a custom tag name", () async {
    await d
        .package(
          pubspec,
          _enableHomebrew(config: 'pkg.homebrewTag.value = "v1.2.3";'),
        )
        .create();
    await _makeRepo("my_app");
    await git(["tag", "v1.2.3"]);

    await _createHomebrewRepo();
    var server = await _serveArchive("v1.2.3");
    await (await _homebrewUpdate(server)).shouldExit(0);
    await server.close();

    await _assertFormula(
      contains('url "https://github.com/me/app/archive/v1.2.3.tar.gz"'),
    );

    expect(await _lastCommitMessage(), equals("Update my_app to 1.2.3"));
  });

  group("when finding the formula", () {
    test("ignores version-specific files", () async {
      await d.package(pubspec, _enableHomebrew()).create();
      await _makeRepo("my_app");
      await git(["tag", "1.2.3"]);

      await _createHomebrewRepo();
      await d
          .file("me/homebrew.git/my_app@1.0.0.rb", "my_app@1.0.0 original")
          .create();
      await d
          .file("me/homebrew.git/my_app@1.2.3.rb", "my_app@1.2.3 original")
          .create();
      await _commitAll("me/homebrew.git", "Add other formula versions");

      var server = await _serveArchive();
      await (await _homebrewUpdate(server)).shouldExit(0);
      await server.close();

      await _assertFormula(
        contains('url "https://github.com/me/app/archive/1.2.3.tar.gz"'),
      );
      await d
          .file("me/homebrew.git/my_app@1.0.0.rb", "my_app@1.0.0 original")
          .validate();
      await d
          .file("me/homebrew.git/my_app@1.2.3.rb", "my_app@1.2.3 original")
          .validate();
    });

    test("ignores non-.rb files", () async {
      await d.package(pubspec, _enableHomebrew()).create();
      await _makeRepo("my_app");
      await git(["tag", "1.2.3"]);

      await _createHomebrewRepo();
      await d.file("me/homebrew.git/my_app", "my_app original").create();
      await d.file("me/homebrew.git/my_app.py", "my_app.py original").create();
      await _commitAll("me/homebrew.git", "Add non-formula files");

      var server = await _serveArchive();
      await (await _homebrewUpdate(server)).shouldExit(0);
      await server.close();

      await _assertFormula(
        contains('url "https://github.com/me/app/archive/1.2.3.tar.gz"'),
      );
      await d.file("me/homebrew.git/my_app", "my_app original").validate();
      await d
          .file("me/homebrew.git/my_app.py", "my_app.py original")
          .validate();
    });

    test("uses the explicit formula", () async {
      await d
          .package(
            pubspec,
            _enableHomebrew(config: 'pkg.homebrewFormula.value = "my_app.rb";'),
          )
          .create();
      await _makeRepo("my_app");
      await git(["tag", "1.2.3"]);

      await _createHomebrewRepo();
      await d
          .file("me/homebrew.git/other_app.rb", "other_app.rb original")
          .create();
      await _commitAll("me/homebrew.git", "Add another formula");

      var server = await _serveArchive();
      await (await _homebrewUpdate(server)).shouldExit(0);
      await server.close();

      await _assertFormula(
        contains('url "https://github.com/me/app/archive/1.2.3.tar.gz"'),
      );
      await d
          .file("me/homebrew.git/other_app.rb", "other_app.rb original")
          .validate();
    });

    group("fails if", () {
      test("there are multiple possible formulas", () async {
        await d.package(pubspec, _enableHomebrew()).create();
        await _makeRepo("my_app");
        await git(["tag", "1.2.3"]);

        await _createHomebrewRepo();
        await d.file("me/homebrew.git/other_app.rb").create();
        await _commitAll("me/homebrew.git", "Add another formula");

        var server = await _serveArchive();
        var process = await _homebrewUpdate(server);
        expect(
          process.stdout,
          emitsThrough(
            contains(
              "Multiple formulas found in the repo, please set "
              "pkg.homebrewFormula.",
            ),
          ),
        );
        await process.shouldExit(1);
        await server.close();
      });

      test("there are no formulas", () async {
        await d.package(pubspec, _enableHomebrew()).create();
        await _makeRepo("my_app");
        await git(["tag", "1.2.3"]);

        await _createHomebrewRepo();
        File(d.path("me/homebrew.git/my_app.rb")).deleteSync();
        await _commitAll("me/homebrew.git", "Remove the formula");

        var server = await _serveArchive();
        var process = await _homebrewUpdate(server);
        expect(
          process.stdout,
          emitsThrough(
            contains(
              "No formulas found in the repo, please set "
              "pkg.homebrewFormula.",
            ),
          ),
        );
        await process.shouldExit(1);
        await server.close();
      });

      test("the only formula is versioned", () async {
        await d.package(pubspec, _enableHomebrew()).create();
        await _makeRepo("my_app");
        await git(["tag", "1.2.3"]);

        await _createHomebrewRepo();
        File(
          d.path("me/homebrew.git/my_app.rb"),
        ).renameSync(d.path("me/homebrew.git/my_app@1.0.0.rb"));
        await _commitAll("me/homebrew.git", "Rename the formula");

        var server = await _serveArchive();
        var process = await _homebrewUpdate(server);
        expect(
          process.stdout,
          emitsThrough(
            contains(
              "No formulas found in the repo, please set "
              "pkg.homebrewFormula.",
            ),
          ),
        );
        await process.shouldExit(1);
        await server.close();
      });
    });
  });
}

/// Returns the contents of a `grind.dart` file that enables Homebrew tasks and
/// sets appropriate GitHub configuration.
///
/// If [config] is passed, it's injected as code in `main()`.
///
/// If [repo] is `false`, this won't set `pkg.homebrewRepo`.
String _enableHomebrew({String? config, bool repo = true}) =>
    """
  void main(List<String> args) {
    ${config ?? ''}
    ${repo ? 'pkg.homebrewRepo.value = "me/homebrew";' : ''}
    pkg.githubRepo.value = "me/app";
    pkg.githubUser.value = "usr";
    pkg.githubPassword.value = "pwd";
    pkg.addHomebrewTasks();
    grind(args);
  }
""";

/// Creates a default Homebrew repository in `me/homebrew.git`.
Future<void> _createHomebrewRepo() async {
  await d.dir("me/homebrew.git", [
    d.file("my_app.rb", """
        class MyApp < Formula
          url "original url"
          sha256 "original sha"
        end
      """),
  ]).create();
  await _makeRepo("me/homebrew.git");
}

/// Makes the directory at [path] (relative to `d.sandbox`) into a Git
/// repository.
Future<void> _makeRepo(String path) async {
  await git(["init"], workingDirectory: path);
  await _commitAll(path, "Initial commit");

  // This is only necessary for the Homebrew repo, but it doesn't hurt to set
  // it elsewhere.
  await git([
    "config",
    "receive.denyCurrentBranch",
    "false",
  ], workingDirectory: path);
}

/// Commits all changes in the repository at [path] with the given [message].
Future<void> _commitAll(String path, String message) async {
  await git(["add", "."], workingDirectory: path);
  await git(["commit", "-m", message], workingDirectory: path);
}

/// Returns a [ShelfTestServer] with a pre-loaded expectation that grinder will
/// request an archive for `my_org/my_app` 1.2.3.
Future<ShelfTestServer> _serveArchive([String tag = "1.2.3"]) async {
  var server = await ShelfTestServer.create();
  server.handler.expect("GET", "/me/app/archive/$tag.tar.gz", (request) async {
    var process = await Process.start("git", [
      "archive",
      "--prefix=app-$tag/",
      "--format=tar.gz",
      tag,
    ], workingDirectory: appDir);

    process.exitCode.then((exitCode) async {
      if (exitCode != 0) {
        fail(
          'git archive $tag failed:\n' +
              await utf8.decodeStream(process.stderr),
        );
      }
    });

    return shelf.Response.ok(
      process.stdout,
      headers: {"content-type": "application/x-gzip"},
    );
  });
  return server;
}

/// Run Grinders `pkg-homebrew-update` task with the test host set so that it
/// will treat `me/homebrew.git` as the Homebrew repository.
Future<TestProcess> _homebrewUpdate(ShelfTestServer server) => grind(
  ["pkg-homebrew-update"],
  environment: {
    // Trick Git into cloning from and pushing to a local path rather than an
    // SSH URL.
    "_CLI_PKG_TEST_GIT_HOST": p.toUri(d.sandbox).toString(),
  },
  server: server,
);

/// Asserts that `me/homebrew.git/my_app.rb` matches [matcher] after being
/// reset to the new `HEAD` state.
///
/// The [path] is the basename of the formula file to verify. If it isn't
/// passed, it defaults to `my_app.rb`.
Future<void> _assertFormula(Object matcher, {String? path}) async {
  await git(["reset", "--hard", "HEAD"], workingDirectory: "me/homebrew.git");
  await d
      .file(p.join("me/homebrew.git", path ?? "my_app.rb"), matcher)
      .validate();
}

/// Returns the last commit message in `me/homebrew.git`.
Future<String> _lastCommitMessage() async {
  var git = await TestProcess.start("git", [
    "log",
    "-1",
    "--pretty=%B",
  ], workingDirectory: d.path("me/homebrew.git"));
  await git.shouldExit(0);
  return (await git.stdout.rest.toList()).join("\n").trim();
}
