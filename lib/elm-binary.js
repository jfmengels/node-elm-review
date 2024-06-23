const path = require('node:path');
const chalk = require('chalk');
const which = require('which');
const spawn = require('cross-spawn');
const ErrorMessage = require('./error-message');

/**
 * @import {Options} from "./types/options"
 * @import {Path} from "./types/path"
 */

/**
 * Get the path to the Elm binary
 *
 * @param {Options} options
 * @returns {Promise<Path>}
 */
async function getElmBinary(options) {
  if (options.compiler === undefined) {
    try {
      return await which('elm');
    } catch {
      throw new ErrorMessage.CustomError(
        // prettier-ignore
        'ELM NOT FOUND',
        // prettier-ignore
        `I could not find the executable for the ${chalk.magentaBright('elm')} compiler.

A few options:
- Install it globally
- Specify the path using ${chalk.cyan('--compiler <path-to-elm>')}`,
        options.elmJsonPath
      );
    }
  }

  try {
    return await which(path.resolve(options.compiler));
  } catch {
    throw new ErrorMessage.CustomError(
      // prettier-ignore
      'ELM NOT FOUND',
      // prettier-ignore
      `I could not find the executable for the ${chalk.magentaBright('elm')} compiler at the location you specified:
  ${options.compiler}`,
      options.elmJsonPath
    );
  }
}

/**
 * Get the version of the Elm compiler
 *
 * @param {Path} elmBinary
 * @returns {string}
 */
function getElmVersion(elmBinary) {
  const result = spawn.sync(elmBinary, ['--version'], {
    silent: true,
    env: process.env
  });

  if (result.status !== 0) {
    return '0.19.1';
  }

  return trimVersion(result.stdout.toString());
}

/**
 * Download the dependencies of the project to analyze.
 *
 * @param {Path} elmBinary
 * @param {Path} elmJsonPath
 * @returns {void}
 */
function downloadDependenciesOfElmJson(elmBinary, elmJsonPath) {
  const result = spawn.sync(elmBinary, ['make', '--report=json'], {
    cwd: path.dirname(elmJsonPath),
    silent: false,
    env: process.env
  });

  if (result.status !== 0) {
    const error = JSON.parse(result.stderr.toString());
    // TODO Check for other kinds of errors
    if (error.title !== 'NO INPUT') {
      // TODO Print error nicely
      throw new Error(error);
    }
  }
}

/**
 * @param {string} version
 * @returns {string}
 */
function trimVersion(version) {
  const index = version.indexOf('-');
  if (index === -1) {
    return version.trim();
  }

  return version.slice(0, index).trim();
}

module.exports = {
  getElmBinary,
  getElmVersion,
  downloadDependenciesOfElmJson
};
