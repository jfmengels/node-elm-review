const path = require("node:path");
const {spawn} = require("node:child_process");
const fs = require("node:fs").promises;
const {glob} = require("tinyglobby");

/**
 * @import {Pid, SpawnResult, Completed} from './types/processes';
 */

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
  "os:spawnProcess": (args) => spawnProcess(args).catch(wrapError),
  "os:waitProcess": (pid) => waitProcess(pid).catch(wrapError)
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

/**
 * @param {SpawnResult} spawnResult;
 * @returns {Promise<Completed>}
 */
function waitForProcessEnd(spawnResult) {
  return new Promise(resolve => {
    spawnResult.spawned.on("exit", (/** @type {number} */ code) => {
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
            code: "ProcessError",
            data: spawnResult.stderr || spawnResult.stdout || "Unexpected error"
          }
        });
      }
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
  const spawnResult = spawnedProcesses.get(pid)
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

function wrapError(error) {
  return {error};
}

module.exports = {
  tasks
};
