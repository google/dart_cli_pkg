import 'dart:js_interop';

extension type Exports._(JSObject _) implements JSObject {
  external set loadedAllDependency(JSFunction value);
  external set loadedBrowserDependency(JSFunction value);
  external set loadedNodeDependency(JSFunction value);
  external set loadedCliDependency(JSFunction value);
  external set loadedDefaultDependency(JSFunction value);
}

external Exports get exports;

@JS('immutable')
external JSObject? immutable;

@JS('lodash')
external JSObject? lodash;

@JS('os')
external JSObject? os;

@JS('fs')
external JSObject? fs;

@JS('http')
external JSObject? http;

void main() {
  exports.loadedAllDependency = immutable != null;
  exports.loadedBrowserDependency = lodash != null;
  exports.loadedNodeDependency = os != null;
  exports.loadedCliDependency = fs != null;
  exports.loadedDefaultDependency = http != null;
}
