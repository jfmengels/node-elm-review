/**
 * @import {Path} from './types/path';
 * @import {ReviewElm} from './types/app';
 */
const path = require('node:path');

module.exports = loadCompiledElmApp;

let hasBeenPatchedAlready = false;

/**
 * @param {Path} elmModulePath
 * @returns {ReviewElm}
 */
function loadCompiledElmApp(elmModulePath) {
  if (!hasBeenPatchedAlready) {
    const oldConsoleWarn = console.warn;
    const regex = /^Compiled in DE(BUG|V) mode/;
    console.warn = function (...args) {
      if (args.length === 1 && regex.test(args[0])) return;
      oldConsoleWarn.apply(console, args);
    };

    hasBeenPatchedAlready = true;
  }

  /** @type {ReviewElm} */
  const elmApp = require(path.resolve(elmModulePath));

  return elmApp;
}
