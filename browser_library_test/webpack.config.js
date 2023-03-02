const p = require("path");

module.exports = [
  {
    entry: "./lib/import.js",
    output: {
      path: p.resolve(__dirname, "lib/build"),
      filename: "webpack-import.js",
    },
    mode: "development",
  },
  {
    entry: "./lib/require.js",
    output: {
      path: p.resolve(__dirname, "lib/build"),
      filename: "webpack-require.js",
    },
    mode: "development",
  },
];
