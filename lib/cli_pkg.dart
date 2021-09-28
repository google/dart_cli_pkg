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

import 'src/chocolatey.dart';
import 'src/github.dart';
import 'src/homebrew.dart';
import 'src/npm.dart';
import 'src/pub.dart';
import 'src/standalone.dart';

export 'src/chocolatey.dart';
export 'src/config_variable.dart' hide InternalConfigVariable;
export 'src/github.dart';
export 'src/homebrew.dart';
export 'src/info.dart' hide freezeSharedVariables;
export 'src/js_require.dart';
export 'src/js_require_target.dart';
export 'src/npm.dart';
export 'src/pub.dart';
export 'src/standalone.dart';

/// Enables all tasks from the `cli_pkg` package.
void addAllTasks() {
  addChocolateyTasks();
  addGithubTasks();
  addHomebrewTasks();
  addNpmTasks();
  addPubTasks();
  addStandaloneTasks();
}
