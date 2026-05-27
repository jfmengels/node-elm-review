const os = require("node:os");
const path = require("node:path");
const {spawn} = require("node:child_process");
const OsHelpers = require("./os-helpers");
const fs = require("node:fs").promises;
const {glob} = require("tinyglobby");

/**
 * @import {Pid, SpawnResult} from './types/processes';
 * @import {Path} from './types/path';
 * @import {ReviewModule} from './types/app';
 */

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
    fs.readFile(args.path, {encoding: "utf8"}).catch(wrapError),
  "fs:writeTextFile": (args) =>
    fs.writeFile(args.path, args.content, {encoding: "utf8"}).catch(wrapError),
  "fs:stat": (args) =>
    fs
      .stat(args.path)
      .then((stat) => {
        return {
          isFile: stat.isFile(),
          isDirectory: stat.isDirectory(),
          isSymlink: stat.isSymbolicLink(),
          size: stat.size,
          modifiedTime: Math.floor(stat.mtimeMs)
        };
      })
      .catch(wrapError),
  "fs:deleteFile": (args) => fs.rm(args.path).catch(wrapError),
  "fs:createSymlink": (args) => fs.symlink(args.target, args.linkPath, "dir").catch(wrapError),
  "fs:createDirectory": (args) =>
    fs.mkdir(args.path, {recursive: true}).catch(wrapError),
  "fs:removeDirectory": (args) => fs.rmdir(args.path).catch(wrapError),
  "fs:copyDirectory": async (args) =>
    copyDirectory(args.from, args.to).catch(wrapError),
  "fs:walkTree": (args) =>
    glob(args.pattern ?? "*", {
      cwd: args.path,
      onlyFiles: args.onlyFiles,
      onlyDirectories: args.onlyDirectories
    }),

  "os:runProcess": (args) => runProcess(args).catch(wrapError),
  "os:spawnProcess": spawnProcess,
  "os:waitProcess": waitProcess
};

async function runProcess(args) {
  return new Promise((resolve) => {
    waitForProcessEnd(startProcess(args), resolve);
  });
}

function startProcess(args) {
  const spawned = spawn(args.command, args.args, {
    env: args.env || process.env,
    cwd: args.cwd,
    stdio: [
      "ignore",
      args.stdout.kind,
      args.stderr.kind === "stdout" ? process.stdout : args.stderr.kind
    ]
  });

  const spawnResult = {
    spawned,
    stdout: args.stdout.kind === "pipe" ? "" : null,
    stderr: args.stderr.kind === "pipe" ? "" : null
  }

  if (typeof spawnResult.stdout === "string") {
    spawned.stdout.on("data", (data) => {
      spawnResult.stdout += data.toString();
    });
  }
  if (typeof spawnResult.stderr === "string") {
    spawned.stderr.on("data", (data) => {
      spawnResult.stderr += data.toString();
    });
  }
  return spawnResult;
}

function waitForProcessEnd(spawnResult, resolve) {
  spawnResult.spawned.on("exit", (code) => {
    const data = {
      pid: spawnResult.spawned.pid,
      exitCode: code,
      stdout: spawnResult.stdout,
      stderr: spawnResult.stderr
    };
    if (code === 0) {
      resolve(data);
    } else {
      resolve({
        error: {
          code: "CommandFailed",
          data
        }
      });
    }
  });
}

/** @type {Map<Pid, SpawnResult>} elmModulePath */
let spawnedProcesses = new Map();

async function spawnProcess(args) {
  try {
    const spawnResult = startProcess(args);
    const pid = spawnResult.spawned.pid;
    spawnedProcesses.set(pid, spawnResult);
    return pid;
  } catch (error) {
    return wrapError(error);
  }
}

async function waitProcess(pid) {
  return new Promise((resolve) => {
    waitForProcessEnd(spawnedProcesses.get(pid), resolve);
  }).finally(() => {
    spawnedProcesses.delete(pid);
  });
}

async function copyDirectory(src, dest) {
  await fs.mkdir(dest, {recursive: true});
  const entries = await fs.readdir(src, {withFileTypes: true});
  for (const entry of entries) {
    const s = path.join(src, entry.name);
    const d = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      await copyDirectory(s, d);
    } else {
      await fs.copyFile(s, d);
    }
  }
}

function wrapError(error) {
  console.error(error);
  return {error};
}

async function main() {
  const ConcurrentTask = await import("@andrewmacmurray/elm-concurrent-task");

  // TODO(@lishaduck): With ESM, this should use TLA.
  const elmModule = loadCompiledElmApp(
    path.resolve(__dirname, "../node/wrapper.js")
  );
  const app = elmModule.Elm.Node.WrapperMain.init({
    flags: {
      args: process.argv.slice(2),
      env: process.env,
      binaryRoot: path.dirname(__dirname),
      userHome: os.homedir()
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
