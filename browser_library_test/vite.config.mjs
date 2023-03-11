export default {
  base: "./",
  build: {
    lib: {
      entry: './lib/import.js',
      formats: ['es'],
      fileName: (format) => 'index.js',
    },
    // Isolate Vite's output in its own subdirectory because otherwise it'll
    // delete the other contents of the build directory.
    outDir: "./lib/build/vite-import",
  },
};
