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

/// A variable whose value is configurable by the user, either as a static value
/// or as a callback that's called as-needed and whose value is cached.
///
/// A config variable's value should be configured in the `main()` method of
/// `tool/grind.dart`, before any `add*Tasks()` functions are called.
class ConfigVariable<T> {
  /// The cached value.
  T _value;

  /// The variable's original value,
  T _defaultValue;

  /// Whether [_value] has been cached yet or not.
  ///
  /// This is used to distinguish a cached `null` value from a value that hasn't
  /// yet been derived.
  var _cached = false;

  /// A function that generates [_value].
  T Function() _callback;

  /// The original callback for generating [_value].
  T Function() _defaultCallback;

  /// Whether this variable has been frozen and can no longer be modified by the
  /// user.
  var _frozen = false;

  /// A function to call to make [_value] unmodifiable.
  final T Function(T) _freeze;

  /// The variable's value.
  T get value {
    if (!_cached) {
      _value = _callback();
      _cached = true;
    }
    return _value;
  }

  set value(T value) {
    if (_frozen) {
      throw StateError(
          "Can't modify a ConfigVariable after pkg.add*Tasks() has been "
          "called.");
    }

    _callback = null;
    _value = value;
    _cached = true;
  }

  /// Returns the default value for this variable, even if its value has since
  /// been overridden.
  T get defaultValue =>
      _defaultCallback == null ? _defaultValue : _defaultCallback();

  /// Sets the variable's value to the result of calling [callback].
  ///
  /// This callback will be called lazily, if and when the variable's value is
  /// actually needed.
  set fn(T callback()) {
    if (_frozen) {
      throw StateError(
          "Can't modify a ConfigVariable after pkg.add*Tasks() has been "
          "called.");
    }

    _callback = callback;
    _value = null;
    _cached = false;
  }

  ConfigVariable._fn(this._callback, {T Function(T) freeze})
      : _defaultCallback = _callback,
        _freeze = freeze;

  ConfigVariable._value(this._value, {T Function(T) freeze})
      : _defaultValue = _value,
        _cached = true,
        _freeze = freeze;

  String toString() => value.toString();
}

/// Expose extension methods so we can hide them from external users.
extension InternalConfigVariable<T> on ConfigVariable<T> {
  /// Creates a configuration variable whose value defaults to the result of the
  /// given [_callback].
  ///
  /// If [freeze] is passed, it's called when the variable is frozen to make the
  /// value unmodifiable as well.
  static ConfigVariable<T> fn<T>(T callback(), {T Function(T) freeze}) =>
      ConfigVariable._fn(callback, freeze: freeze);

  /// Creates a configuration variable with the given [value].
  ///
  /// If [freeze] is passed, it's called when the variable is frozen to make the
  /// value unmodifiable as well.
  static ConfigVariable<T> value<T>(T value, {T Function(T) freeze}) =>
      ConfigVariable._value(value, freeze: freeze);

  /// Marks the variable as unmodifiable.
  void freeze() {
    if (_frozen) return;
    _frozen = true;
    if (_freeze != null) {
      if (_cached) {
        _value = _freeze(_value);
      } else {
        var oldCallback = _callback;
        _callback = () => _freeze(oldCallback());
      }
    }
  }
}
