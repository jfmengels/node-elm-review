const path = require('path');
const util = require('util');
const chalk = require('chalk');
const which = require('which');
const spawn = require('cross-spawn');
const ErrorMessage = require('./error-message');

/**
 * @typedef { import("./types/options").Options } Options
 * @typedef { import("./types/path").Path } Path
 */

/** Get the path to the Elm binary
 *
 * @param {Options} options
 * @return {Promise<Path>}
 */
function getElmBinary(options) {
  const whichAsync = util.promisify(which);
  if (options.compiler === undefined) {
    return whichAsync('elm').catch(() => {
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
    });
  }

  return whichAsync(path.resolve(options.compiler)).catch(() => {
    throw new ErrorMessage.CustomError(
      // prettier-ignore
      'ELM NOT FOUND',
      // prettier-ignore
      `I could not find the executable for the ${chalk.magentaBright('elm')} compiler at the location you specified:
  ${options.compiler}`,
      options.elmJsonPath
    );
  });
}

/** Get the version of the Elm compiler
 *
 * @param {Path} elmBinary
 * @return {Promise<string>}
 */
async function getElmVersion(elmBinary) {
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
 * @param {string} version
 * @return {string}
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
  getElmVersion
};
