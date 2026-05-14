const path = require("node:path");
const fs = require("node:fs").promises;

let hasBeenPatchedAlready = false;

/**
 * @param {Path} elmModulePath
 * @returns {ReviewModule}
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

  /** @type {ReviewModule} */
  const elmApp = require(path.resolve(elmModulePath));

  return elmApp;
}

// TODO Extract this so elm-app-worker2 can use it too.
const tasks = {
  "fs:readTextFile": (args) =>
    fs.readFile(args.path, {encoding: "utf8"}).catch((error) => {
      // TODO Return FsError
      return {error: "PermissionDenied"};
    }),
  "fs:writeTextFile": (args) =>
    fs.writeFile(args.path, args.content, {encoding: "utf8"}).catch((error) => {
      // TODO Return FsError
      return {error: "PermissionDenied"};
    }),
  "fs:stat": (args) =>
    fs
      .stat(args.path)
      // TODO Map stat data
      .catch((error) => {
        // TODO Return FsError
        return {error: "PermissionDenied"};
      })
};

async function main() {
  const ConcurrentTask = await import("@andrewmacmurray/elm-concurrent-task");

  // TODO(@lishaduck): With ESM, this should use TLA.
  const elmModule = loadCompiledElmApp("./node/wrapper.js");
  const app = elmModule.Elm.Node.WrapperMain.init({
    flags: {
      args: process.argv.slice(2),
      env: process.env
    }
  });

  ConcurrentTask.register({
    tasks,
    ports: {
      send: app.ports.send,
      receive: app.ports.receive
    }
  });
}

module.exports = main;
