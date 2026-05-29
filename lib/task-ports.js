const path = require("node:path");
const {spawn} = require("node:child_process");
const fs = require("node:fs").promises;
const {glob} = require("tinyglobby");

/**
 * @import {Pid, SpawnResult, Completed} from './types/processes';
 */

function registerPorts(app) {
  app.ports.exit.subscribe(flushAndExit);
  app.ports.printlnStdout.subscribe(console.log);
  app.ports.printlnStderrThenExit.subscribe(({message, exitCode}) => {
    console.error(message);
    flushAndExit(exitCode);
  });
  app.ports.printlnStderr.subscribe(console.error);
}

/**
 * @param {number} exitCode
 */
function flushAndExit(exitCode) {
  // Flush out stdout/stderr before exiting
  const empty = Buffer.from([]);
  process.stdout.write(empty, () => {
    process.stderr.write(empty, () => {
      process.exit(exitCode);
    });
  });
}

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
  "fs:createSymlink": (args) =>
    fs.symlink(args.target, args.linkPath, "dir").catch(wrapError),
  "fs:createDirectory": (args) =>
    fs.mkdir(args.path, {recursive: true}).catch(wrapError),
  "fs:removeDirectory": (args) => fs.rmdir(args.path).catch(wrapError),
  "fs:copyDirectory": async (args) =>
    copyDirectory(args.from, args.to).catch(wrapError),
  "fs:walkTree": walkTree,

  "os:runProcess": (args) => runProcess(args).catch(wrapError),
  "os:spawnProcess": (args) => spawnProcess(args).catch(wrapError),
  "os:waitProcess": (pid) => waitProcess(pid).catch(wrapError),

  "std::println": println
};

/**
 * @param {object} data
 * @param {"log" | "error"} data.logFunction
 * @param {string} data.message
 * @returns {Promise<void>}
 */
async function println({logFunction, message}) {
  console[logFunction](message);
}

async function runProcess(args) {
  return waitForProcessEnd(startProcess(args)).then((data) => {
    if (data.exitCode === 0) {
      return data;
    }

    return {
      error: {
        code: "CommandFailed",
        data
      }
    };
  });
}

function startProcess(args) {
  const spawned = spawn(args.command, args.args, {
    env: args.env,
    cwd: args.cwd,
    stdio: [
      args.stdin.kind,
      args.stdout.kind,
      args.stderr.kind === "stdout" ? process.stdout : args.stderr.kind
    ]
  });
  const spawnResult = {
    spawned,
    stdout: "",
    stderr: ""
  };

  switch (args.stdin.kind) {
    case "ignore":
    case "inherit": {
      break;
    }
    case "pipe": {
      spawned.stdin.write(args.stdin.data, () => {
        spawned.stdin.end();
      });
      break;
    }
    case "file": {
      throw new Error("Unsupported stdin kind file.");
    }
    default: {
      throw new Error("Unknown stdin kind:" + args.stdin.kind);
    }
  }

  if (typeof spawnResult.stdout === "string") {
    spawned.stdout?.on("data", (data) => {
      spawnResult.stdout += data.toString();
    });
  }
  if (typeof spawnResult.stderr === "string") {
    spawned.stderr?.on("data", (data) => {
      spawnResult.stderr += data.toString();
    });
  }
  return spawnResult;
}

/**
 * @param {SpawnResult} spawnResult;
 * @returns {Promise<Completed>}
 */
function waitForProcessEnd(spawnResult) {
  return new Promise((resolve) => {
    spawnResult.spawned.on("exit", (/** @type {number} */ exitCode) => {
      resolve({
        pid: spawnResult.spawned.pid,
        exitCode,
        stdout: spawnResult.stdout,
        stderr: spawnResult.stderr
      });
    });
  });
}

/** @type {Map<Pid, SpawnResult>} elmModulePath */
let spawnedProcesses = new Map();

async function spawnProcess(args) {
  const spawnResult = startProcess(args);
  const pid = spawnResult.spawned.pid;
  spawnedProcesses.set(pid, spawnResult);
  return pid;
}

/**
 * @param {Pid} pid;
 * @returns {Promise<Completed>}
 */
async function waitProcess(pid) {
  const spawnResult = spawnedProcesses.get(pid);
  if (!spawnResult) {
    // TODO Use a dedicated error for waiting on an non-existent pid.
    throw new Error(`waitProcess error: ${pid} does not exist`);
  }
  return waitForProcessEnd(spawnResult);
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

async function walkTree(args) {
  let files = await glob("**/*", {
    cwd: args.path,
    onlyFiles: args.onlyFiles,
    onlyDirectories: args.onlyDirectories
  });

  if (args.pattern) {
    // TODO Support other types than extension patterns (e.g. "*.elm")
    const pattern = args.pattern.replace("*", "");
    files = files.filter((path) => path.endsWith(pattern));
  }
  return files;
}

function wrapError(error) {
  return {error};
}

module.exports = {
  registerPorts,
  tasks
};
