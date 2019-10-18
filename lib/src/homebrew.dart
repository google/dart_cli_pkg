// Copyright 2019 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:grinder/grinder.dart';
import 'package:path/path.dart' as p;

import 'github.dart';
import 'info.dart';
import 'utils.dart';

/// The GitHub repository slug (for example, `username/repo`) of the Homebrew
/// repository for this package.
///
/// This must be set explicitly.
String get homebrewRepo {
  if (_homebrewRepo != null) return _homebrewRepo;
  fail("pkg.homebrewRepo must be set to deploy to Homebrew.");
}

set homebrewRepo(String value) => _homebrewRepo = value;
String _homebrewRepo;

/// The path to the formula file within the Homebrew repository to update with
/// the new package version.
///
/// If this isn't set, the task will default to looking for a single `.rb` file
/// at the root of the repo without an `@` in its filename and modifying that.
/// If there isn't exactly one such file, the task will fail.
String homebrewFormula;

/// Whether [addHomebrewTasks] has been called yet.
var _addedHomebrewTasks = false;

/// The Git tag for version of the package being released.
///
/// This tag must already exist in the local clone of the repo; it's not created
/// by this task. It defaults to [version].
String get homebrewTag => _homebrewTag ?? version.toString();
set homebrewTag(String value) => _homebrewTag = value;
String _homebrewTag;

/// Enables tasks for uploading the package to Homebrew.
void addHomebrewTasks() {
  if (_addedHomebrewTasks) return;
  _addedHomebrewTasks = true;

  addTask(GrinderTask('pkg-homebrew-update',
      taskFunction: () => _update(),
      description: 'Update the Homebrew formula.'));
}

/// Updates the Homebrew formula to point at the current version of the package.
Future<void> _update() async {
  ensureBuild();

  var process = await Process.start("git", [
    "archive",
    "--prefix=${githubRepo.split("/").last}-$homebrewTag/",
    "--format=tar.gz",
    homebrewTag
  ]);
  var digest = await sha256.bind(process.stdout).first;
  var stderr = await utf8.decodeStream(process.stderr);
  if ((await process.exitCode) != 0) {
    fail('git archive "$homebrewTag" failed:\n$stderr');
  }

  var repo =
      await cloneOrPull(url("https://github.com/$homebrewRepo.git").toString());

  var formulaPath = _formulaFile(repo);
  var formula = _replaceFirstMappedMandatory(
      File(formulaPath).readAsStringSync(),
      RegExp(r'\n( *)url "[^"]+"'),
      (match) => '\n${match[1]}url '
          '"https://github.com/$githubRepo/archive/$homebrewTag.tar.gz"',
      "Couldn't find a url field in $formulaPath.");
  formula = _replaceFirstMappedMandatory(
      formula,
      RegExp(r'\n( *)sha256 "[^"]+"'),
      (match) => '\n${match[1]}sha256 "$digest"',
      "Couldn't find a sha256 field in $formulaPath.");

  writeString(formulaPath, formula);

  run("git",
      arguments: [
        "commit",
        "--all",
        "--message",
        "Update $humanName to $version"
      ],
      workingDirectory: repo,
      runOptions: botEnvironment);

  await runAsync("git",
      arguments: [
        "push",
        url("https://$githubUser:$githubPassword@github.com/$homebrewRepo.git")
            .toString(),
        "HEAD:master"
      ],
      workingDirectory: repo);
}

/// Like [String.replaceFirstMapped], but fails with [error] if no match is found.
String _replaceFirstMappedMandatory(
    String string, Pattern from, String replace(Match match), String error) {
  var found = false;
  var result = string.replaceFirstMapped(from, (match) {
    found = true;
    return replace(match);
  });

  if (!found) fail(error);
  return result;
}

/// Returns the path to the formula file to update in [repo].
String _formulaFile(String repo) {
  if (homebrewFormula != null) return p.join(repo, homebrewFormula);

  var entries = [
    for (var entry in Directory(repo).listSync())
      if (entry is File &&
          entry.path.endsWith(".rb") &&
          !p.basename(entry.path).contains("@"))
        entry.path
  ];

  if (entries.isEmpty) {
    fail("No formulas found in the repo, please set pkg.homebrewFormula.");
  } else if (entries.length > 1) {
    fail("Multiple formulas found in the repo, please set "
        "pkg.homebrewFormula.");
  } else {
    return entries.single;
  }
}
