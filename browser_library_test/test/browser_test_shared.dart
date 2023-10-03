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

import 'package:cli_pkg/js.dart';
import 'package:js/js.dart';
import 'package:test/test.dart';

@JS()
external bool? get loadedAllDependency;

@JS()
external bool? get loadedBrowserDependency;

@JS()
external bool? get loadedNodeDependency;

@JS()
external bool? get loadedCliDependency;

@JS()
external bool? get loadedDefaultDependency;

void main() {
  test("the all dependency is loaded", () {
    expect(loadedAllDependency, isTrue);
  });

  test("the browser dependency is loaded", () {
    expect(loadedBrowserDependency, isTrue);
  });

  test("the node dependency is not loaded", () {
    expect(loadedNodeDependency, isFalse);
  });

  test("the cli dependency is not loaded", () {
    expect(loadedCliDependency, isFalse);
  });

  test("the default dependency is not loaded", () {
    expect(loadedDefaultDependency, isFalse);
  });

  test("isNodeJs returns 'false'", () {
    expect(isNodeJs, isFalse);
  });
  test("process returns 'null'", () {
    expect(process, isNull);
  });
}
