// Copyright 2022 Google LLC
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

@TestOn('browser')

import 'package:test/test.dart';

import 'browser_test_shared.dart' as shared;

void main() async {
  // TODO(nweiz): Periodically retry this to see if it works again.
  // Unfortunately we can't get any actual information about the failure until
  // dart-lang/test#345 is fixed.
  group('', shared.main, tags: ['not-on-gh-actions']);
}
