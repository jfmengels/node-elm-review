const path = require("node:path");
const OsHelpers = require("./os-helpers");
const fs = require("node:fs").promises;
const {glob} = require("tinyglobby");

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
      }),
  "fs:deleteFile": (args) =>
    fs.rm(args.path).catch((error) => {
      // TODO Return FsError
      return {error: "PermissionDenied"};
    }),
  "fs:createDirectory": (args) =>
    fs.mkdir(args.path, {recursive: true}).catch((error) => {
      // TODO Return FsError
      return {error: "PermissionDenied"};
    }),
  "fs:removeDirectory": (args) =>
    fs.rmdir(args.path).catch((error) => {
      // TODO Return FsError
      return {error: "PermissionDenied"};
    }),
  "fs:copyDirectory": (args) =>
    // TODO Make copyDirectory do a copy, not a symlink
    fs.symlink(args.from, args.to, "dir").catch((error) => {
      // TODO Return FsError
      return {error: "PermissionDenied"};
    }),
  "fs:walkTree": (args) =>
    glob(args.pattern ?? "*", {
      cwd: args.path,
      onlyFiles: args.onlyFiles,
      onlyDirectories: args.onlyDirectories
    }),
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

  app.ports.exit.subscribe(process.exit);
  app.ports.printlnStdout.subscribe(console.log);
  app.ports.printlnStderr.subscribe(console.error);

  ConcurrentTask.register({
    tasks,
    ports: {
      send: app.ports.send,
      receive: app.ports.receive
    }
  });
}

module.exports = main;
