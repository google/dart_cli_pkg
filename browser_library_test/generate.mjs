import * as fs from 'fs';

import {Generator} from '@jspm/generator';

const generator = new Generator({
  mapUrl: './lib/build/',
  defaultProvider: 'nodemodules',
  env: ['production', 'browser', 'module'],
});

await generator.install('./cli-pkg-test');

const map = generator.getMap();

// The @jspm/genearator resolves symlinks without a way to preserve them (unless
// file URLs are used). We have to manually restore the paths for the dart
// browser tests to work. This is a bit hacky, but it works for our use case. 
const prefix = './packages/cli_pkg_test/build/cli-pkg-test/';
const concretePathPrefix = '../../build/npm/';
function addPrefixToValues(map) {
  for (const [key, value] of Object.entries(map)) {
    map[key] = value.replace(concretePathPrefix, prefix);
  }
}

addPrefixToValues(map['imports']);

for (const [scope, imports] of Object.entries(map['scopes'])) {
  delete map['scopes'][scope];
  map['scopes'][scope.replace(concretePathPrefix, prefix)] = imports;
  addPrefixToValues(imports);
}

fs.writeFileSync('test/jspm_test.html', `
<!doctype html>
<html>
  <head>
    <title>JSPM Test</title>
    <link rel="x-dart-test" href="jspm_test.dart">
    <script src="packages/test/dart.js"></script>
    <script type="importmap">${JSON.stringify(map)}</script>
    <script src="packages/cli_pkg_test/import.js" type="module"></script>
  </head>
  <body>
  </body>
</html>
`);
