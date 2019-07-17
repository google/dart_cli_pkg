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

import 'dart:cli';
import 'dart:io';
import 'dart:isolate';

import 'package:mustache/mustache.dart';
import 'package:path/path.dart' as p;

/// The template directory in the `cli_pkg` package.
final Future<String> _dir = () async {
  return p.fromUri(await Isolate.resolvePackageUri(
      Uri.parse('package:cli_pkg/src/templates')));
}();

/// A cache of parsed templates.
final _cache = p.PathMap<Template>();

/// Loads the template from [path] (relative to `lib/src/templates`, without the
/// trailing `.mustache`) and renders it using [variables].
String renderTemplate(String path, Map<String, String> variables) {
  path = p.join(waitFor(_dir), path);
  return _cache
      .putIfAbsent(path,
          () => Template(File("$path.mustache").readAsStringSync(), name: path))
      .renderString(variables);
}
