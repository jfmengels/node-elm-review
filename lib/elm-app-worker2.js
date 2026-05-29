const os = require("node:os");
const path = require("node:path");
const loadCompiledElmApp = require("./load-compiled-app");
const TaskPorts = require("./task-ports");

const [elmModulePath, ...args] = process.argv.slice(2);

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
})();
