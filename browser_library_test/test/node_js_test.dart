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

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:js_util';

import 'package:cli_pkg/js.dart';
import 'package:test/test.dart';

@TestOn('browser')
void main() {
  tearDown(() => globalThis.toJSBox.delete('process'.toJS));

  const nonNodeJsProcessTestCases = <String, Map<String, Map<String, String>>>{
    'an empty process': {},
    'a process with empty release': {'release': {}},
    'a process with non-Node.JS release name': {
      'release': {'name': 'hello'}
    },
  };

  const fakeNodeJsProcess = {
    'release': {'name': 'node'}
  };

  group('isNodeJs', () {
    test("returns 'false' from the browser", () {
      expect(isNodeJs, isFalse);
    });

    for (final entry in nonNodeJsProcessTestCases.entries) {
      final caseName = entry.key;
      final processJson = entry.value.jsify();

      test("returns 'false' when $caseName exists in the 'window'", () {
        globalThis.toJSBox['process'.toJS] = processJson;
        expect(isNodeJs, isFalse);
      });
    }

    test("returns 'true' with a fake Node.JS process", () {
      globalThis.toJSBox['process'.toJS] = fakeNodeJsProcess.jsify();
      expect(isNodeJs, isTrue);
    });
  });

  group('process', () {
    test("returns 'null' from the browser", () {
      expect(process, isNull);
    });

    for (final entry in nonNodeJsProcessTestCases.entries) {
      final caseName = entry.key;
      final processJson = entry.value.jsify();

      test("returns 'null' when $caseName exists in the 'window'", () {
        globalThis.toJSBox['process'.toJS] = processJson;
        expect(process, isNull);
      });
    }

    test("returns a fake process if it fakes being a Node.JS environment", () {
      globalThis.toJSBox['process'.toJS] = fakeNodeJsProcess.jsify();
      expect(process.jsify().dartify(), fakeNodeJsProcess);
    });
  });
}
