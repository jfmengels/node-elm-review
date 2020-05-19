const worker = null;

try {
  // Conditional imports, because `worker_threads` is not supported by default
  // on Node v10
  // eslint-disable-next-line node/no-unsupported-features/node-builtins
  const {Worker} = require('worker_threads');

  module.exports = {
    init,
    stop: () => {}
  };
} catch {
  module.exports = {
    init,
    stop: () => {}
  };
}

function init(elmModulePath, flags) {
  const elmModule = loadCompiledElmApp(elmModulePath);
  const app = elmModule.Elm.Elm.Review.Main.init({
    flags
  });
  return app;
}

function loadCompiledElmApp(elmModulePath) {
  const oldConsoleWarn = console.warn;
  const regex = /^Compiled in DE(BUG|V) mode/;
  // $FlowFixMe
  console.warn = function(...args) {
    if (args.length === 1 && regex.test(args[0])) return;
    return oldConsoleWarn.apply(console, args);
  };

  // $FlowFixMe
  return require(elmModulePath);
}
