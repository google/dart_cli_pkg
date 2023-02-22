import 'package:js/js.dart';

@JS()
class Exports {
  external set loadedAllDependency(Object value);
  external set loadedBrowserDependency(Object value);
  external set loadedNodeDependency(Object value);
  external set loadedCliDependency(Object value);
  external set loadedDefaultDependency(Object value);
}

@JS()
external Exports get exports;

@JS('immutable')
external Object? immutable;

@JS('lodash')
external Object? lodash;

@JS('os')
external Object? os;

@JS('fs')
external Object? fs;

@JS('http')
external Object? http;

void main() {
  exports.loadedAllDependency = immutable != null;
  exports.loadedBrowserDependency = lodash != null;
  exports.loadedNodeDependency = os != null;
  exports.loadedCliDependency = fs != null;
  exports.loadedDefaultDependency = http != null;
}
