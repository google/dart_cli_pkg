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

extension type _NodeProcess._(JSObject object) implements JSObject {
  external _ProcessReleaseInfo? get release;
}

extension type _ProcessReleaseInfo._(JSObject object) implements JSObject {
  external String get name;
}

@JS('process')
external final _NodeProcess? _process; // process is undefined in the browser

extension type _JSDocument._(JSObject object) implements JSObject {
  external JSAny? get querySelector;
}

@JS('document')
external final _JSDocument? _document; // document is undefined in Node.JS

const bool isJS = true;

bool get isNodeJs => _process?.release?.name == 'node';

bool get isBrowser =>
    !isNodeJs &&
    switch (_document) {
      var document? => document.querySelector.typeofEquals('function'),
      _ => false
    };

@Deprecated('Run the callback directly, without a wrapper')
T wrapJSExceptions<T>(T Function() callback) => callback();
