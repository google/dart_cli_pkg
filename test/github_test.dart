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
import 'dart:io';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:async/async.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_test_handler/shelf_test_handler.dart';
import 'package:test/test.dart';
import 'package:tuple/tuple.dart';

import 'descriptor.dart' as d;
import 'utils.dart';

void main() {
  var pubspec = {
    "name": "my_app",
    "version": "1.2.3",
    "executables": {"foo": "foo"}
  };

  var pubspecWithHomepage = {
    ...pubspec,
    "homepage": "https://github.com/my_org/my_app"
  };

  group("repo name", () {
    group("throws an error", () {
      test("if it's not set anywhere", () async {
        await d.package(pubspec, _enableGithub()).create();

        var process = await grind(["pkg-github-release"]);
        expect(
            process.stdout,
            emitsThrough(
                contains("pkg.githubRepo must be set to deploy to GitHub.")));
        await process.shouldExit(1);
      });

      test("if it's not parsable from the pubspec homepage", () async {
        await d.package({...pubspec, "homepage": "http://my-cool-package.pkg"},
            _enableGithub()).create();

        var process = await grind(["pkg-github-release"]);
        expect(
            process.stdout,
            emitsThrough(
                contains("pkg.githubRepo must be set to deploy to GitHub.")));
        await process.shouldExit(1);
      });

      test("if it's not parsable from the Git config", () async {
        await d.package(pubspec, _enableGithub()).create();
        await git(["init"]);
        await git(["remote", "add", "origin", "git://random-url.com/repo"]);

        var process = await grind(["pkg-github-release"]);
        expect(
            process.stdout,
            emitsThrough(
                contains("pkg.githubRepo must be set to deploy to GitHub.")));
        await process.shouldExit(1);
      });
    });

    group("parses from the pubspec homepage", () {
      Future<void> assertParses(String homepage, String repo) async {
        await d.package(
            {...pubspec, "homepage": homepage}, _enableGithub()).create();
        await _release(repo);
      }

      test("with an https URL", () async {
        await assertParses(
            "https://github.com/google/dart_cli_pkg", "google/dart_cli_pkg");
      });

      test("with an http URL", () async {
        await assertParses(
            "http://github.com/google/dart_cli_pkg", "google/dart_cli_pkg");
      });

      test("with a URL with more nesting", () async {
        await assertParses(
            "http://github.com/google/dart_cli_pkg/tree/master/lib",
            "google/dart_cli_pkg");
      });
    });

    test("prefers the Git origin to the pubspec homepage", () async {
      await d.package(
          {...pubspec, "homepage": "http://github.com/google/wrong"},
          _enableGithub()).create();

      await git(["init"]);
      await git(["remote", "add", "origin", "git://github.com/google/right"]);

      await _release("google/right");
    });

    group("parses from the Git origin", () {
      Future<void> assertParses(String origin, String repo) async {
        await d.package(pubspec, _enableGithub()).create();
        await git(["init"]);
        await git(["remote", "add", "origin", origin]);
        await _release(repo);
      }

      test("with an https URL", () async {
        await assertParses(
            "https://github.com/google/dart_cli_pkg", "google/dart_cli_pkg");
      });

      test("with an https URL ending in .git", () async {
        await assertParses("https://github.com/google/dart_cli_pkg.git",
            "google/dart_cli_pkg");
      });

      test("with an http URL", () async {
        await assertParses(
            "http://github.com/google/dart_cli_pkg", "google/dart_cli_pkg");
      });

      test("with an http URL ending in .git", () async {
        await assertParses(
            "http://github.com/google/dart_cli_pkg.git", "google/dart_cli_pkg");
      });

      test("with a git URL", () async {
        await assertParses(
            "git://github.com/google/dart_cli_pkg", "google/dart_cli_pkg");
      });

      test("with a git URL ending in .git", () async {
        await assertParses(
            "git://github.com/google/dart_cli_pkg.git", "google/dart_cli_pkg");
      });

      test("with an SSH identifier", () async {
        await assertParses(
            "git@github.com:google/dart_cli_pkg", "google/dart_cli_pkg");
      });

      test("with an SSH identifier ending in .git", () async {
        await assertParses(
            "git@github.com:google/dart_cli_pkg.git", "google/dart_cli_pkg");
      });
    });

    test("prefers an explicit repo URL to Git origin", () async {
      await d.package(pubspec, """
        void main(List<String> args) {
          pkg.githubUser.value = "usr";
          pkg.githubPassword.value = "pwd";
          pkg.githubRepo.value = "google/right";
          pkg.addGithubTasks();
          grind(args);
        }
      """).create();

      await git(["init"]);
      await git(["remote", "add", "origin", "git://github.com/google/wrong"]);
      await _release("google/right");
    });
  });

  group("username", () {
    Future<void> assertUsername(String expected,
        {Map<String, String>? environment}) async {
      await _release("my_org/my_app", verify: (request) {
        expect(_getAuthorization(request).item1, equals(expected));
      }, environment: environment);
    }

    test("throws an error if it's not set anywhere", () async {
      await d.package(pubspecWithHomepage, _enableGithub(user: false)).create();

      var process = await grind(["pkg-github-release"]);
      expect(
          process.stdout,
          emitsThrough(
              contains("pkg.githubUser or pkg.githubBearerToken must be set to "
                  "deploy to GitHub.")));
      await process.shouldExit(1);
    });

    test("parses from the GITHUB_USER environment variable", () async {
      await d.package(pubspecWithHomepage, _enableGithub(user: false)).create();
      await assertUsername("fblthp", environment: {"GITHUB_USER": "fblthp"});
    });

    test("prefers an explicit username to the GITHUB_USER environment variable",
        () async {
      await d.package(pubspecWithHomepage, _enableGithub()).create();
      await assertUsername("usr", environment: {"GITHUB_USER": "wrong"});
    });
  });

  group("password", () {
    Future<void> assertPassword(String expected,
        {Map<String, String>? environment}) async {
      await _release("my_org/my_app", verify: (request) {
        expect(_getAuthorization(request).item2, equals(expected));
      }, environment: environment);
    }

    test("throws an error if it's not set anywhere", () async {
      await d
          .package(pubspecWithHomepage, _enableGithub(password: false))
          .create();

      var process = await grind(["pkg-github-release"]);
      expect(
          process.stdout,
          emitsThrough(
              contains("pkg.githubPassword or pkg.githubBearerToken must be "
                  "set to deploy to GitHub.")));
      await process.shouldExit(1);
    });

    test("parses from the GITHUB_TOKEN environment variable", () async {
      await d
          .package(pubspecWithHomepage, _enableGithub(password: false))
          .create();
      await assertPassword("secret", environment: {"GITHUB_TOKEN": "secret"});
    });

    test("prefers the GITHUB_PASSWORD environment variable to GITHUB_TOKEN",
        () async {
      await d
          .package(pubspecWithHomepage, _enableGithub(password: false))
          .create();
      await assertPassword("right",
          environment: {"GITHUB_PASSWORD": "right", "GITHUB_TOKEN": "wrong"});
    });

    test(
        "prefers an explicit username to the GITHUB_PASSWORD environment variable",
        () async {
      await d.package(pubspecWithHomepage, _enableGithub()).create();
      await assertPassword("pwd", environment: {"GITHUB_PASSWORD": "wrong"});
    });
  });

  group("bearer token", () {
    Future<void> assertToken(String expected,
        {Map<String, String>? environment}) async {
      await _release("my_org/my_app", verify: (request) {
        expect(request.headers, contains("authorization"));
        var authorization = request.headers["authorization"]!;
        expect(authorization, startsWith("Bearer "));

        expect(authorization.substring("Bearer ".length), equals(expected));
      }, environment: environment);
    }

    test("parses from the GITHUB_BEARER_TOKEN environment variable", () async {
      await d
          .package(pubspecWithHomepage, _enableGithub(password: false))
          .create();
      await assertToken("secret",
          environment: {"GITHUB_BEARER_TOKEN": "secret"});
    });

    test("prefers the GITHUB_BEARER_TOKEN environment variable to GITHUB_TOKEN",
        () async {
      await d
          .package(pubspecWithHomepage, _enableGithub(password: false))
          .create();
      await assertToken("right", environment: {
        "GITHUB_BEARER_TOKEN": "right",
        "GITHUB_TOKEN": "wrong"
      });
    });

    test(
        "prefers an explicit username to the GITHUB_PASSWORD environment variable",
        () async {
      await d
          .package(
              pubspecWithHomepage, _enableGithub(password: false, bearer: true))
          .create();
      await assertToken("secret",
          environment: {"GITHUB_BEARER_TOKEN": "wrong"});
    });
  });

  group("release notes", () {
    Future<void> assertReleaseNotes(Object matcher) async {
      await _release("my_org/my_app", verify: (request) async {
        expect(json.decode(await request.readAsString())["body"] as String?,
            matcher);
      });
    }

    Future<void> assertReleaseNotesFromChangelog(
        String changelog, Object matcher) async {
      await d.package(pubspecWithHomepage, _enableGithub()).create();
      await d.file("my_app/CHANGELOG.md", changelog).create();
      await assertReleaseNotes(matcher);
    }

    test("isn't set in the request if it's not set anywhere", () async {
      await d.package(pubspecWithHomepage, _enableGithub()).create();

      await _release("my_org/my_app", verify: (request) async {
        expect(
            json.decode(await request.readAsString()), isNot(contains("body")));
      });
    });

    group("from the CHANGELOG", () {
      test("adds a post scriptum", () async {
        await assertReleaseNotesFromChangelog(
            "## 1.2.3\n"
            "asdf",
            endsWith("\n\n"
                "See the [full changelog](https://github.com/my_org/my_app/"
                "blob/master/CHANGELOG.md#123) for changes in earlier "
                "releases."));
      });

      test("includes the body of the last entry", () async {
        await assertReleaseNotesFromChangelog(
            "## 1.2.3\n"
            "This is a great release!",
            startsWith("This is a great release!"));
      });

      test("only includes the first entry", () async {
        await assertReleaseNotesFromChangelog(
            "## 1.2.3\n"
            "This is a great release!\n"
            "## 1.2.3\n"
            "This one... not so great.",
            allOf([
              contains("This is a great release!"),
              isNot(contains("This one... not so great"))
            ]));
      });

      test("consolidates multi-line paragraphs", () async {
        await assertReleaseNotesFromChangelog(
            "## 1.2.3\n"
            "\n"
            "This is a\n"
            "great release!\n",
            startsWith("This is a great release!"));
      });

      test("leaves separate paragraphs separate", () async {
        await assertReleaseNotesFromChangelog(
            "## 1.2.3\n"
            "\n"
            "This is a great release!\n\n"
            "Give it a try!",
            startsWith("This is a great release!\n\n"
                "Give it a try!"));
      });

      test("leaves code blocks as-is", () async {
        await assertReleaseNotesFromChangelog(
            "## 1.2.3\n"
            "\n"
            "```scss\n"
            "a {\n"
            "  b: c;\n"
            "\n"
            "  d: e;\n"
            "}\n"
            "```",
            startsWith("```scss\n"
                "a {\n"
                "  b: c;\n"
                "\n"
                "  d: e;\n"
                "}\n"
                "```"));
      });

      test("leaves groups of link reference definitions as-is", () async {
        await assertReleaseNotesFromChangelog(
            "## 1.2.3\n"
            "\n"
            "[a], [b], [c]\n"
            "\n"
            "[a]: http://a.com\n"
            "[b]: http://b.org\n"
            "[c]: http://c.net\n",
            startsWith("[a], [b], [c]\n"
                "\n"
                "[a]: http://a.com\n"
                "[b]: http://b.org\n"
                "[c]: http://c.net\n"));
      });

      test(
          "folds a line that looks like a link reference definition in a paragraph",
          () async {
        await assertReleaseNotesFromChangelog(
            "## 1.2.3\n"
            "\n"
            "[a]\n"
            "[a]: http://a.com\n",
            startsWith("[a] [a]: http://a.com\n"));
      });
    });

    test("prefers explicit release notes to the CHANGELOG", () async {
      await d.package(pubspecWithHomepage, """
        void main(List<String> args) {
          pkg.githubUser.value = "usr";
          pkg.githubPassword.value = "pwd";
          pkg.githubReleaseNotes.value = "right";
          pkg.addGithubTasks();
          grind(args);
        }
      """).create();
      await d.file("my_app/CHANGELOG.md", "## 1.2.3\nwrong").create();
      await assertReleaseNotes("right");
    });
  });

  test("pkg-github-macos uploads standalone Mac OS archives", () async {
    await d.package(pubspecWithHomepage, _enableGithub()).create();
    await _release("my_org/my_app");

    var server = await _assertUploadsPackage("macos");
    await (await grind(["pkg-github-macos"], server: server)).shouldExit(0);
    await server.close();
  });

  test("pkg-github-linux uploads standalone Linux archives", () async {
    await d.package(pubspecWithHomepage, _enableGithub()).create();
    await _release("my_org/my_app");

    var server = await _assertUploadsPackage("linux");
    await (await grind(["pkg-github-linux"], server: server)).shouldExit(0);
    await server.close();
  });

  test("pkg-github-windows uploads standalone Windows archives", () async {
    await d.package(pubspecWithHomepage, _enableGithub()).create();
    await _release("my_org/my_app");

    var server = await _assertUploadsPackage("windows");
    await (await grind(["pkg-github-windows"], server: server)).shouldExit(0);
    await server.close();
  }, onPlatform: {"windows": Skip("dart-lang/sdk#37897")});
}

/// The contents of a `grind.dart` file that just enables GitHub tasks.
///
/// If [user], [password], or [bearer] are `true`, this sets default values for
/// `pkg.githubUser`, `pkg.githubPassword`, and `pkg.githubBearerToken`,
/// respectively.
String _enableGithub(
    {bool user = true, bool password = true, bool bearer = false}) {
  var buffer = StringBuffer("""
    void main(List<String> args) {
  """);

  if (user) buffer.writeln('pkg.githubUser.value = "usr";');
  if (password) buffer.writeln('pkg.githubPassword.value = "pwd";');
  if (bearer) buffer.writeln('pkg.githubBearerToken.value = "secret";');
  buffer.writeln("pkg.addGithubTasks();");
  buffer.writeln("grind(args);");
  buffer.writeln("}");

  return buffer.toString();
}

/// Runs the release process, asserts that a POST is made to the URL for the
/// given [repo], passes that POST request to [verify], and returns a 201
/// CREATED response.
Future<void> _release(String repo,
    {FutureOr<void> verify(shelf.Request request)?,
    Map<String, String>? environment}) async {
  var server = await ShelfTestServer.create();
  server.handler.expect("POST", "/repos/$repo/releases",
      expectAsync1((request) async {
    if (verify != null) await verify(request);
    return shelf.Response(201);
  }));

  var grinder = await grind(["pkg-github-release"],
      server: server, environment: environment);
  await grinder.shouldExit(0);
  await server.close();
}

/// Returns a [ShelfTestServer] with pre-loaded expectations for a series of
/// requests corresponding to uploading a package for the given [os].
Future<ShelfTestServer> _assertUploadsPackage(String os) async {
  var server = await ShelfTestServer.create();
  server.handler.expect("GET", "/repos/my_org/my_app/releases/tags/1.2.3",
      (request) async {
    var authorization = _getAuthorization(request);
    expect(authorization.item1, equals("usr"));
    expect(authorization.item2, equals("pwd"));

    // This isn't the real GitHub upload URL, but we want to verify that we
    // use the template rather than hard-coding.
    return shelf.Response.ok(
        json.encode({"upload_url": server.url.resolve("/upload").toString()}));
  });

  // TODO(nweiz): Instead of manually collating futures here, just make separate
  // order-independent assertions for each architecture once
  // dart-lang/shelf_test_handler#9 is fixed.
  var urls = FutureGroup<String>();
  for (var i = 0; i < (os == 'macos' ? 1 : 2); i++) {
    var completer = Completer<String>();
    urls.add(completer.future);

    server.handler.expectAnything(expectAsync1((request) async {
      expect(request.method, equals("POST"));

      var url = request.url.toString();
      completer.complete(url);
      expect(url, startsWith("upload?name=my_app-1.2.3-$os-"));
      expect(url, endsWith(os == "windows" ? ".zip" : ".tar.gz"));

      expect(
          request.headers,
          containsPair("content-type",
              os == "windows" ? "application/zip" : "application/gzip"));
      var archive = os == "windows"
          ? ZipDecoder().decodeBytes(await collectBytes(request.read()))
          : TarDecoder().decodeBytes(await collectBytes(
              // Cast to work around dart-lang/shelf#189.
              request.read().cast<List<int>>().transform(gzip.decoder)));

      expect(archive.findFile("my_app/foo${os == 'windows' ? '.bat' : ''}"),
          isNotNull);

      return shelf.Response(201);
    }));
  }
  urls.close();
  expect(
      urls.future,
      completion(containsAll([
        // Dart as of 2.7 doesn't support 32-bit Mac OS executables.
        if (os != "macos") contains("ia32"),
        contains("x64")
      ])));

  return server;
}

/// Returns the username and password from [request]'s basic authentication.
///
/// Throws a [TestFailure] if [request] doesn't have a well-formed basic
/// authentication header.
Tuple2<String, String> _getAuthorization(shelf.Request request) {
  expect(request.headers, contains("authorization"));
  var authorization = request.headers["authorization"]!;
  expect(authorization, startsWith("Basic "));

  var decoded =
      utf8.decode(base64.decode(authorization.substring("Basic ".length)));
  expect(decoded, contains(":"));

  var components = decoded.split(":");
  expect(components, hasLength(2));
  return Tuple2(components.first, components.last);
}
