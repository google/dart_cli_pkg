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

/// Whether we're running as JS (browser or Node.js).
const bool isJS = false;

/// Whether we're running as Node.js (not browser or Dart VM).
///
/// This is determined by validating that `process.release.name == "node"`.
bool get isNodeJs => throw '';

/// Whether we're running as browser (not Node.js or Dart VM).
///
/// This is determined by checking for the `scrollRestoration` property in
/// the browser's History API.
bool get isBrowser => throw '';

/// Runs [callback], wrapping any primitive JS objects it throws so they don't
/// crash when caught by Dart code.
///
/// This works around [a bug] in Dart where primitive types such as strings
/// thrown by JS will cause Dart code that catches them to crash in [strict mode]
/// specifically. For safety, all calls to callbacks passed in from an external
/// JS context should be wrapped in this function.
///
/// [a bug]: https://github.com/dart-lang/sdk/issues/53105
/// [strict mode]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Strict_mode
///
/// This function will rethrow the original error if it's run from a non-JS
/// platform.
T wrapJSExceptions<T>(T Function() callback) => throw '';
