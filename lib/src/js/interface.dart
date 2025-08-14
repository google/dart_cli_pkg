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
/// This is determined by checking for the `querySelector` function in the
/// browser's Document API.
bool get isBrowser => throw '';

/// This used to exist to work around a bug in the Dart SDk that has since been
/// fixed in all supported Dart SDK versions.
@Deprecated('Run the callback directly, without a wrapper')
T wrapJSExceptions<T>(T Function() callback) => throw '';
