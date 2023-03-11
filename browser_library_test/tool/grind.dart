// Copyright 2023 Google LLC
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

import 'package:cli_pkg/cli_pkg.dart' as pkg;
import 'package:grinder/grinder.dart';

void main(List<String> args) {
  pkg.npmPackageJson.value = {
    "name": "cli-pkg-test",
    "dependencies": {"immutable": "^4.2.0", "lodash": "^4.17.0"}
  };
  pkg.jsModuleMainLibrary.value = "lib/src/module_main.dart";
  pkg.jsRequires.value = [
    pkg.JSRequire('immutable', target: pkg.JSRequireTarget.all),
    pkg.JSRequire('lodash', target: pkg.JSRequireTarget.browser),
    pkg.JSRequire('os', target: pkg.JSRequireTarget.node),
    pkg.JSRequire('fs', target: pkg.JSRequireTarget.cli),
    pkg.JSRequire('http', target: pkg.JSRequireTarget.defaultTarget),
  ];
  pkg.jsEsmExports.value = {
    'loadedAllDependency',
    'loadedBrowserDependency',
    'loadedNodeDependency',
    'loadedCliDependency',
    'loadedDefaultDependency',
  };

  pkg.addNpmTasks();
  grind(args);
}

@Task('Run all tasks required to test the package')
@Depends(readyPackage, npmInstall, raw, webpack, rollup, esbuild, jspm, vite)
void beforeTest() {}

@Task('Install JS dependencies')
void npmInstall() {
  run("npm", arguments: ["install"]);
}

@Task('Make the cli-pkg-test package ready for loading')
@Depends('pkg-npm-dev')
void readyPackage() {
  run("npm", arguments: ["install"], workingDirectory: "build/npm");
}

@Task('Set up raw HTML imports.')
void raw() {
  delete(getDir('lib/build/pkg'));
  Directory('lib/build/pkg').createSync(recursive: true);

  _forceLink('lib/build/cli-pkg-test', '../../build/npm');
  File('lib/build/pkg/package.json').writeAsStringSync(json.encode({
    "dependencies": {"cli-pkg-test": "file:../cli-pkg-test"}
  }));
  run("npm", arguments: ["install"], workingDirectory: "lib/build/pkg");
  run("npm",
      arguments: ["install"], workingDirectory: "lib/build/cli-pkg-test");
}

@Task('Build jspm')
void jspm() {
  _forceLink('lib/build/cli-pkg-test', '../../build/npm');
  _forceLink('lib/build/node_modules', '../../node_modules');
  run("node", arguments: ["generate.mjs"]);
}

@Task('Build webpack bundles')
void webpack() {
  run("npx", arguments: ["webpack"]);
}

@Task('Build rollup bundles')
void rollup() {
  run("npx", arguments: ["rollup", "--config", "rollup.config.import.mjs"]);
  run("npx", arguments: ["rollup", "--config", "rollup.config.require.mjs"]);
}

@Task('Build esbuild bundles')
void esbuild() {
  run("npx", arguments: [
    "esbuild",
    "--bundle",
    "lib/require.js",
    "--outfile=lib/build/esbuild-require.js"
  ]);
  run("npx", arguments: [
    "esbuild",
    "--bundle",
    "lib/import.js",
    "--outfile=lib/build/esbuild-import.js"
  ]);
}

@Task('Build rollup bundles')
void vite() {
  run("npx", arguments: ["vite", "build"]);
}

@Task('Format JS source')
void format() {
  run("npx", arguments: [
    "prettier",
    "--write",
    "**/*.js",
    "!lib/build/**",
    "!build/**"
  ]);
}

/// Creates a link from [location] to [target], overwriting an existing link if
/// it exists.
void _forceLink(String location, String target) {
  try {
    Link(location).deleteSync();
  } on IOException {
    // Ignore if the link doesn't exist.
  }

  Link(location).createSync(target);
}
