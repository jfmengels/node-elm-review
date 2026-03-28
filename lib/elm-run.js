"use strict";

/**
 * @import {ChildProcess} from 'node:child_process'
 * @import {Path} from './types/path'
 * @import {ElmRunOptions, ElmRunProcessOptions} from './types/elm-run'
 */

const path = require("node:path");
const chalk = require("chalk");
const spawn = require("cross-spawn");
const which = require("which");
const ErrorMessage = require("./error-message");

/**
 * Get the path to the elm-run binary
 *
 * @param {Path} cwd
 * @returns {Promise<Path>}
 */
async function getElmRunBinary(cwd) {
  try {
    const elmRunBinaryPath = await which("run");
    return path.resolve(elmRunBinaryPath);
  } catch {
    throw new ErrorMessage.CustomError(
      "ELM-RUN NOT FOUND",
      `I could not find the executable for ${chalk.magentaBright("elm-run")}`
    );
  }
}

/** @satisfies {Partial<ElmRunOptions>} */
const defaultOptions = {
  cwd: undefined,
  pathToElmRun: undefined,
  output: undefined,
  target: undefined,
  verbose: false,
  processOpts: undefined
};

/**
 * @param {ElmRunOptions} options
 * @returns {ElmRunOptions}
 */
function prepareOptions(options) {
  return Object.assign({}, defaultOptions, options);
}

/**
 * @param {ElmRunOptions} options
 * @returns {string[]}
 */
function prepareProcessArgs(options) {
  return ["make", "--output=" + options.output, options.target];
}

/**
 * @param {ElmRunOptions} options
 * @returns {ElmRunProcessOptions}
 */
function prepareProcessOpts(options) {
  const env = Object.assign({LANG: "en_US.UTF-8"}, process.env);
  return Object.assign(
    {env: env, stdio: "inherit", cwd: options.cwd},
    options.processOpts
  );
}

/**
 * @param {ElmRunOptions} options
 * @returns {ChildProcess}
 */
function runCompiler(options) {
  const processArgs = prepareProcessArgs(options);
  const processOpts = prepareProcessOpts(options);
  const pathToElmRun = options.pathToElmRun;

  if (options.verbose) {
    console.log(["Running", pathToElmRun].concat(processArgs).join(" "));
  }

  return spawn(pathToElmRun, processArgs, processOpts);
}

/**
 * @param {string | { code: string | undefined, message: string }} err
 * @param {Path} pathToElmRun
 */
function compilerErrorToString(err, pathToElmRun) {
  if (typeof err === "object" && typeof err.code === "string") {
    switch (err.code) {
      case "ENOENT":
        return (
          'Could not find `run` binary "' + pathToElmRun + '". Is it installed?'
        );

      case "EACCES":
        return (
          'The `run` binary "' +
          pathToElmRun +
          '" did not have permission to run. Do you need to give it executable permissions?'
        );

      default:
        return (
          'Error attempting to run elm-run "' + pathToElmRun + '":\n' + err
        );
    }
  } else if (typeof err === "object" && typeof err.message === "string") {
    return JSON.stringify(err.message);
  } else {
    return (
      "Exception thrown when attempting to run Elm compiler " +
      JSON.stringify(pathToElmRun)
    );
  }
}

/**
 * @param {ElmRunOptions} options
 * @returns {ChildProcess}
 */
function compile(options) {
  const optionsWithDefaults = prepareOptions(options);

  try {
    return runCompiler(optionsWithDefaults).on("error", function (err) {
      throw err;
    });
  } catch (err) {
    throw compilerErrorToString(err, options.pathToElmRun);
  }
}

module.exports = {
  compile,
  getElmRunBinary
};
