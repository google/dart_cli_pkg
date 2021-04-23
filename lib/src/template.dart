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

import 'package:path/path.dart' as p;

import 'utils.dart';

/// A cache of template file contents.
final _cache = p.PathMap<String>();

/// Loads the template from [path] (relative to `lib/src/templates`, without the
/// trailing `.mustache`) and renders it using [variables].
///
/// Note: This function only supports simple variable replacement. It does not
/// support any additional Mustache features.
String renderTemplate(String path, Map<String, String> variables) {
  path = p.join(waitFor(cliPkgSrc), 'templates', path);
  var text =
      _cache.putIfAbsent(path, () => File("$path.mustache").readAsStringSync());
  for (var entry in variables.entries) {
    text = text.replaceAll('{{{${entry.key}}}}', entry.value);
  }
  return text;
}
