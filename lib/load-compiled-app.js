const path = require('path');

module.exports = loadCompiledElmApp;

let hasBeenPatchedAlready = false;

function loadCompiledElmApp(elmModulePath) {
  if (!hasBeenPatchedAlready) {
    const oldConsoleWarn = console.warn;
    const regex = /^Compiled in DE(BUG|V) mode/;
    // $FlowFixMe
    console.warn = function (...args) {
      if (args.length === 1 && regex.test(args[0])) return;
      return oldConsoleWarn.apply(console, args);
    };

    hasBeenPatchedAlready = true;
  }

  return require(path.resolve(elmModulePath));
}
