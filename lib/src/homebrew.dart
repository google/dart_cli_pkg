// Copyright 2019 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:grinder/grinder.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'config_variable.dart';
import 'github.dart';
import 'info.dart';
import 'utils.dart';

/// The GitHub repository slug (for example, `username/repo`) of the Homebrew
/// repository for this package.
///
/// This must be set explicitly.
final homebrewRepo = InternalConfigVariable.fn<String>(
    // TODO: delete as
    () => fail("pkg.homebrewRepo must be set to deploy to Homebrew."));

/// The path to the formula file within the Homebrew repository to update with
/// the new package version.
///
/// If this isn't set, the task will default to looking for a single `.rb` file
/// at the root of the repo without an `@` in its filename and modifying that.
/// If there isn't exactly one such file, the task will fail.
final homebrewFormula = InternalConfigVariable.value<String>(null);

/// Whether to update [homebrewFormula] in-place or copy it to a new
/// `@`-versioned formula file for the current version number.
///
/// By default, this is `true` if and only if [version] is a prerelease version.
final homebrewCreateVersionedFormula =
    InternalConfigVariable.fn<bool>(() => version.isPreRelease);

/// Whether [addHomebrewTasks] has been called yet.
var _addedHomebrewTasks = false;

/// The Git tag for version of the package being released.
///
/// This tag must already exist in the local clone of the repo; it's not created
/// by this task. It defaults to [version].
final homebrewTag = InternalConfigVariable.value(version.toString());

/// Enables tasks for uploading the package to Homebrew.
void addHomebrewTasks() {
  if (_addedHomebrewTasks) return;
  _addedHomebrewTasks = true;

  freezeSharedVariables();
  homebrewRepo.freeze();
  homebrewFormula.freeze();
  homebrewCreateVersionedFormula.freeze();
  homebrewTag.freeze();

  addTask(GrinderTask('pkg-homebrew-update',
      taskFunction: () => _update(),
      description: 'Update the Homebrew formula.'));
}

/// Updates the Homebrew formula to point at the current version of the package.
Future<void> _update() async {
  ensureBuild();

  var process = await Process.start("git", [
    "archive",
    "--prefix=${githubRepo.value.split("/").last}-$homebrewTag/",
    "--format=tar.gz",
    homebrewTag.value
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

  if (homebrewCreateVersionedFormula.value) {
    formula = _replaceFirstMappedMandatory(
        formula,
        RegExp(r'^ *class ([^ <]+) *< *Formula *$', multiLine: true),
        (match) => 'class ${match[1]}AT${_classify(version)} < Formula',
        "Couldn't find a Formula subclass in $formulaPath.");

    var newFormulaPath = p.join(p.dirname(formulaPath),
        "${p.basenameWithoutExtension(formulaPath)}@$version.rb");
    writeString(newFormulaPath, formula);
    run("git",
        arguments: ["add", p.relative(newFormulaPath, from: repo)],
        workingDirectory: repo,
        runOptions: botEnvironment);
  } else {
    writeString(formulaPath, formula);
  }

  run("git",
      arguments: [
        "commit",
        "--all",
        "--message",
        homebrewCreateVersionedFormula.value
            ? "Add a formula for $humanName $version"
            : "Update $humanName to $version"
      ],
      workingDirectory: repo,
      runOptions: botEnvironment);

  await runAsync("git",
      arguments: [
        "push",
        url("https://$githubUser:$githubPassword@github.com/$homebrewRepo.git")
            .toString(),
        "HEAD:${await _originHead(repo)}"
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
  if (homebrewFormula.value != null) return p.join(repo, homebrewFormula.value);

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

/// Returns the name of HEAD in the origin remote (that is, the default branch
/// name of the upstream repository).
Future<String> _originHead(String repo) async {
  var result = await Process.run(
      "git", ["symbolic-ref", "refs/remotes/origin/HEAD"],
      workingDirectory: repo);
  if (result.exitCode != 0) {
    fail('"git symbolic-ref refs/remotes/origin/HEAD" failed:\n'
        '${result.stderr}');
  }

  var stdout = (result.stdout as String).trim();
  var prefix = "refs/remotes/origin/";
  if (!stdout.startsWith(prefix)) {
    fail('Unexpected output from "git symbolic-ref refs/remotes/origin/HEAD":\n'
        'Expected a string starting with "$prefix", got:\n'
        '$stdout');
  }

  return stdout.substring(prefix.length);
}

/// Converts [version] into the format Homebrew expects in an `@`-versioned
/// formula name, not including the leading `AT`.
String _classify(Version version) => version
    .toString()
    .replaceAllMapped(
        RegExp(r'[-_.]([a-zA-Z0-9])'), (match) => match[1].toUpperCase())
    .replaceAll('+', 'x');
