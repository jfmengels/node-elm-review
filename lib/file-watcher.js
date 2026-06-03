const os = require("node:os");
const path = require("node:path");
const chokidar = require("chokidar");
const OsHelpers = require("./os-helpers");
const TaskPorts = require("./task-ports");
const ResultCache = require("./result-cache");
const ElmCommunication = require("./elm-communication");

function register() {
  globalThis.watchFiles = function watchFiles(optionsString, handler) {
    const options = JSON.parse(optionsString);
    let watcher = chokidar.watch(options.path, {
      ignoreInitial: true,
      ignored: options.excludePaths,
      disableGlobbing: options.path,
      atomic: options.coalesceMs
    });

    // eventMask is a Bitmask: 1=Created, 2=Modified, 4=Deleted, 8=Renamed
    if (options.eventMask % 2) {
      watcher = watcher.on("add", (absolutePath) =>
        handler(toFileEvent(1, absolutePath))
      );
    }
    if ((options.eventMask >> 1) % 2) {
      watcher = watcher.on("change", (absolutePath) =>
        handler(toFileEvent(2, absolutePath))
      );
    }
    if ((options.eventMask >> 2) % 2) {
      watcher = watcher.on("unlink", (absolutePath) =>
        handler(toFileEvent(4, absolutePath))
      );
    }

    return () => {
      watcher.close();
    };
  };
}

function toFileEvent(eventType, absolutePath) {
  return JSON.stringify({
    path: OsHelpers.makePathOsAgnostic(
      path.relative(process.cwd(), absolutePath)
    ),
    eventType: eventType,
    timestamp: Date.now(),
    subscriptionId: 0
  });
}

module.exports = {register};
