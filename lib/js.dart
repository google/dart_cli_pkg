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

import 'package:js/js.dart';
import 'package:js/js_util.dart';
import 'package:node_interop/process.dart';

@JS('process')
external final Process? _process; // process is null in the browser

/// This extension adds `maybe<Property>` getters that return non-nullable
/// properties with a nullable type.
extension PartialProcess on Process {
  /// Returns [release] as nullable.
  Release? get maybeRelease => release;
}

/// Whether the script is being executed in a Node.JS environment.
bool get isNodeJs => _process?.maybeRelease?.name == 'node';

/// Returns the NodeJs [Process] value only when the script is running in
/// Node.JS, otherwise returns `null`.
///
/// By checking whether the script is running in Node.JS we can avoid returning
/// a non-[Process] object if the script is running in a browser, and there is a
/// different `process` object in the `window`. This can happen when a library
/// or framework adds a global variable named `process`. For example, Next.JS
/// adds [`process.env`] to access environment variables on the browser.
///
/// [`process.env`]: https://nextjs.org/docs/pages/building-your-application/configuring/environment-variables#bundling-environment-variables-for-the-browser
///
/// The getter can still return a non-[Process] object if the script is running
/// in a browser and there is a `process` object in the `window` with the value
/// `{release: {name: 'node'}}`. In this case the script must trust the browser
/// is emulating a Node.JS environment.
///
/// Note: Add a dependency on `node_interop` to ensure you get a version
/// compatible with your usage.
Process? get process => isNodeJs ? _process : null;

/// Whether this Dart code is running in a strict mode context.
///
/// In strict mode, assigning properties to primitive types is an error. This
/// uses that fact to sniff whether strict mode is in effect.
final _isStrictMode = () {
  try {
    setProperty('', 'name', null);
    return false;
  } catch (_) {
    return true;
  }
}();

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
T wrapJSExceptions<T>(T Function() callback) {
  if (!_isStrictMode) return callback();

  try {
    return callback();
  } on String catch (error) {
    // ignore: use_rethrow_when_possible
    throw error;
  } on bool catch (error) {
    // ignore: use_rethrow_when_possible
    throw error;
  } on num catch (error) {
    // ignore: use_rethrow_when_possible
    throw error;
  } catch (error) {
    if (typeofEquals<Object>(error, 'symbol') ||
        typeofEquals<Object>(error, 'bigint') ||
        // ignore: unnecessary_cast
        (error as Object?) == null) {
      // Work around dart-lang/sdk#53106
      throw callMethod<String>(error, "toString", []);
    }
    rethrow;
  }
}
