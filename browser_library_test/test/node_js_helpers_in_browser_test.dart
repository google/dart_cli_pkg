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

@TestOn('browser')

import 'dart:js_interop';
import 'dart:js_util';

import 'package:cli_pkg/js.dart';
import 'package:test/test.dart';

@JS('Object.defineProperty')
external Object _defineProperty(Object obj, Object prop, Object descriptor);

@JS('Symbol.toStringTag')
external Object _toStringTag;

void main() {
  group('isNodeJs', () {
    withNonNodeJsProcess(() {
      test('returns false', () => expect(isNodeJs, isFalse));
    });

    withFakedNodeJsProcess(() {
      test('returns true', () => expect(isNodeJs, isTrue));
    });
  });

  group('isBrowser', () {
    withNonNodeJsProcess(() {
      test('returns true', () => expect(isBrowser, isTrue));
    });

    withFakedNodeJsProcess(() {
      test('returns true', () => expect(isBrowser, isTrue));
    });
  });

  test('isJS returns true', () => expect(isJS, isTrue));

  // Strict-mode tests are in `npm_test.dart`.
  test('wrapJSException throws the same primitive in non-strict mode', () {
    expect(() => wrapJSExceptions(() => throw ''), throwsA(equals('')));
  });
}

/// Runs a suite of tests that verify the same behavior across environments that
/// look like Node.JS, but that don't actually fake a Node.JS environment.
void withNonNodeJsProcess(void Function() callback) {
  const nonNodeJsProcessTestCases = <String, Map<String, Map<String, String>>>{
    'an empty process': {},
    'a process with empty release': {'release': {}},
    'a process with non-Node.JS release name': {
      'release': {'name': 'definitely-not-node'}
    },
  };

  group('default environment', callback);

  for (final entry in nonNodeJsProcessTestCases.entries) {
    final caseName = entry.key;
    final processJson = entry.value.jsify();

    group(caseName, () {
      setUp(() => setProperty(globalThis, 'process', processJson));
      callback();
      tearDown(() => delete<Object>(globalThis, 'process'));
    });
  }
}

/// Runs a suite of tests that verify the same behavior across environments that
/// fake a Node.JS environment.
void withFakedNodeJsProcess(void Function() callback) {
  const fakeNodeJsProcess = {
    'release': {'name': 'node'}
  };

  group('fake Node.JS environment', () {
    setUp(() => setProperty(
        globalThis,
        'process',
        _defineProperty(fakeNodeJsProcess.jsify() as Object, _toStringTag,
            ({'value': 'process'}).jsify() as Object)));
    callback();
    tearDown(() => delete<Object>(globalThis, 'process'));
  });
}
