const os = require("node:os");
const path = require("node:path");
const ResultCache = require("./result-cache");
const loadCompiledElmApp = require("./load-compiled-app");
const TaskPorts = require("./task-ports");

const [elmModulePath, resultCacheFolder, ...args] = process.argv.slice(2);

const elmModule = loadCompiledElmApp(elmModulePath);

(async function main() {
  const ConcurrentTask = await import("@andrewmacmurray/elm-concurrent-task");

  const app = elmModule.Elm.Node.ReviewMain.init({
    flags: {
      args,
      env: process.env,
      logger: undefined,
      userHome: os.homedir(),
      binaryRoot: path.dirname(__dirname)
    }
  });

  TaskPorts.registerPorts(app);
  ConcurrentTask.register({
    tasks: TaskPorts.tasks,
    ports: {
      send: app.ports.send,
      receive: app.ports.receive
    }
  });

  const flatArgs = args.join(" ");
  ResultCache.load(
    {
      debug: flatArgs.includes("--debug"),
      directoriesToAnalyze: flatArgs.includes("--dirs-to-analyze") ? [""] : [],
      showBenchmark: flatArgs.includes("--benchmark-info"),
      rulesFilter: rulesFilter(flatArgs)
    },
    flatArgs.includes("--ignore-dirs") ? [""] : [],
    flatArgs.includes("--ignore-files") ? [""] : [],
    resultCacheFolder
  )

  function rulesFilter(args) {
    const matches = /--rules=(\w*)(\s|$)/.exec(args);
    if (!matches) {
      return null;
    }
    return matches[1].split(",");
  }
})();
