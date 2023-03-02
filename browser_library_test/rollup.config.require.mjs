import { nodeResolve } from '@rollup/plugin-node-resolve';
import commonjs from '@rollup/plugin-commonjs';

export default {
  input: 'lib/require.js',
  output: {
    file: 'lib/build/rollup-require.js',
format: 'iife',
  },
  plugins: [nodeResolve({browser: true}), commonjs()],
};
