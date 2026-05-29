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

  app.ports.exit.subscribe((/** @type {number} */ exitCode) => {
    // Flush out stdout/stderr before exiting
    const empty = Buffer.from([]);
    process.stdout.write(empty, () => {
      process.stderr.write(empty, () => {
        process.exit(exitCode);
      });
    });
  });
  app.ports.printlnStdout.subscribe(console.log);
  app.ports.printlnStderr.subscribe(console.error);

  ConcurrentTask.register({
    tasks: TaskPorts.tasks,
    ports: {
      send: app.ports.send,
      receive: app.ports.receive
    }
  });
})();
