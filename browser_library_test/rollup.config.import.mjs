import { nodeResolve } from '@rollup/plugin-node-resolve';

export default {
  input: 'lib/import.js',
  output: {
    file: 'lib/build/rollup-import.js',
    format: 'iife',
  },
  plugins: [nodeResolve({browser: true})],
};
