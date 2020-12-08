// Copyright 2020 Google LLC
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

import 'package:test/test.dart';

import 'package:cli_pkg/src/config_variable.dart';

void main() {
  group("the value constructor", () {
    test("sets the default value", () {
      var variable = InternalConfigVariable.value(12);
      expect(variable.value, equals(12));
    });

    test("is overridden by a new value", () {
      var variable = InternalConfigVariable.value(1);
      variable.value = 12;
      expect(variable.value, equals(12));
    });

    test("is overridden by a new function", () {
      var variable = InternalConfigVariable.value(1);
      variable.fn = () => 12;
      expect(variable.value, equals(12));
    });

    group("is still available as defaultValue when it's", () {
      test("overridden by a new value", () {
        var variable = InternalConfigVariable.value(1);
        variable.value = 12;
        expect(variable.defaultValue, equals(1));
      });

      test("overridden by a new function", () {
        var variable = InternalConfigVariable.value(1);
        variable.fn = () => 12;
        expect(variable.defaultValue, equals(1));
      });
    });
  });

  group("the function constructor", () {
    test("sets the default value", () {
      var variable = InternalConfigVariable.fn(() => 12);
      expect(variable.value, equals(12));
    });

    test("isn't called if the value isn't accessed", () {
      InternalConfigVariable.fn(expectAsync0(() => null, count: 0));
    });

    test("isn't called if the value is overridden", () {
      var variable =
          InternalConfigVariable.fn<int>(expectAsync0(() => null, count: 0));
      variable.value = 12;
      expect(variable.value, equals(12));
    });

    test("isn't called if the function is overridden", () {
      var variable =
          InternalConfigVariable.fn<int>(expectAsync0(() => null, count: 0));
      variable.fn = () => 12;
      expect(variable.value, equals(12));
    });

    test("is cached", () {
      var variable =
          InternalConfigVariable.fn<int>(expectAsync0(() => 12, count: 1));
      expect(variable.value, equals(12));
      expect(variable.value, equals(12));
    });

    group("is still available as defaultValue when it's", () {
      test("overridden by a new value", () {
        var variable = InternalConfigVariable.fn(() => 1);
        variable.value = 12;
        expect(variable.defaultValue, equals(1));
      });

      test("overridden by a new function", () {
        var variable = InternalConfigVariable.fn(() => 1);
        variable.fn = () => 12;
        expect(variable.defaultValue, equals(1));
      });
    });
  });

  group("fn=", () {
    test("sets the value", () {
      var variable = InternalConfigVariable.value(1);
      variable.fn = () => 12;
      expect(variable.value, equals(12));
    });

    test("isn't called if the value isn't accessed", () {
      var variable = InternalConfigVariable.value(1);
      variable.fn = expectAsync0(() => null, count: 0);
    });

    test("isn't called if the value is overridden", () {
      var variable = InternalConfigVariable.value(1);
      variable.fn = expectAsync0(() => null, count: 0);
      variable.value = 12;
      expect(variable.value, equals(12));
    });

    test("isn't called if the function is overridden", () {
      var variable = InternalConfigVariable.value(1);
      variable.fn = expectAsync0(() => null, count: 0);
      variable.fn = () => 12;
      expect(variable.value, equals(12));
    });

    test("is cached", () {
      var variable = InternalConfigVariable.value(1);
      variable.fn = expectAsync0(() => 12, count: 1);
      expect(variable.value, equals(12));
      expect(variable.value, equals(12));
    });
  });

  group("frozen", () {
    test("value can be read", () {
      var variable = InternalConfigVariable.value(1);
      variable.freeze();
      expect(variable.value, equals(1));
    });

    test("fn can be read", () {
      var variable = InternalConfigVariable.fn(() => 1);
      variable.freeze();
      expect(variable.value, equals(1));
    });

    test("value can't be set", () {
      var variable = InternalConfigVariable.value(1);
      variable.freeze();
      expect(() => variable.value = 12, throwsStateError);
    });

    test("fn can't be set", () {
      var variable = InternalConfigVariable.value(1);
      variable.freeze();
      expect(() => variable.fn = () => 12, throwsStateError);
    });

    group("the freeze function", () {
      test("isn't called if ConfigVariable.freeze() isn't", () {
        var variable = InternalConfigVariable.value(1,
            // TODO: no dynamic
            freeze: expectAsync1((n) => 0, count: 0));
        expect(variable.value, equals(1));
      });

      test("modifies a cached value", () {
        var variable = InternalConfigVariable.value(1, freeze: (n) => n + 1);
        variable.freeze();
        expect(variable.value, equals(2));
      });

      test("is only called once", () {
        var variable = InternalConfigVariable.value(1,
            freeze: expectAsync1((n) => n + 1, count: 1));
        variable.freeze();
        variable.freeze();
        expect(variable.value, equals(2));
      });

      test("modifies a function's return value", () {
        var variable = InternalConfigVariable.fn(() => 1, freeze: (n) => n + 1);
        variable.freeze();
        expect(variable.value, equals(2));
      });

      test("is only called once", () {
        var variable = InternalConfigVariable.fn(
            expectAsync0(() => 1, count: 1),
            freeze: expectAsync1((n) => n + 1, count: 1));
        variable.freeze();
        variable.freeze();
        expect(variable.value, equals(2));
      });
    });
  });
}
