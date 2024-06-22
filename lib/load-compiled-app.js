const path = require('node:path');

/**
 * @import {Path} from "./types/path"
 * @import {Elm} from "./types/app"
 */

module.exports = loadCompiledElmApp;

let hasBeenPatchedAlready = false;

/**
 * @param {Path} elmModulePath
 * @returns {Elm}
 */
function loadCompiledElmApp(elmModulePath) {
  if (!hasBeenPatchedAlready) {
    const oldConsoleWarn = console.warn;
    const regex = /^Compiled in DE(BUG|V) mode/;
    console.warn = function (...args) {
      if (args.length === 1 && regex.test(args[0])) return;
      return oldConsoleWarn.apply(console, args);
    };

    hasBeenPatchedAlready = true;
  }

  return require(path.resolve(elmModulePath));
}
