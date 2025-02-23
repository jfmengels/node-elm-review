/**
 * @import {Options} from './types/options';
 * @import {Path} from './types/path';
 * @import {VersionString} from './types/version';
 */
const path = require('pathe');
const chalk = require('chalk');
const spawn = require('cross-spawn');
const which = require('which');
const ErrorMessage = require('./error-message');
const {backwardsCompatiblePath} = require('./npx');

/**
 * Get the path to the Elm binary
 *
 * @param {Options} options
 * @returns {Promise<Path>}
 */
async function getElmBinary(options) {
  try {
    const elmBinaryPath = await which(options.compiler ?? 'elm', {
      path: backwardsCompatiblePath(options.compiler, options.cwd)
    });
    return path.resolve(elmBinaryPath);
  } catch {
    throw new ErrorMessage.CustomError(
      'ELM NOT FOUND',
      options.compiler === undefined
        ? // prettier-ignore
          `I could not find the executable for the ${chalk.magentaBright('elm')} compiler.

A few options:
- Install it globally
- Specify the path using ${chalk.cyan('--compiler <path-to-elm>')}`
        : // prettier-ignore
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
 * @returns {VersionString}
 */
function getElmVersion(elmBinary) {
  const result = spawn.sync(elmBinary, ['--version'], {
    // @ts-expect-error(TS2769): The types are outdated.
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
    // @ts-expect-error(TS2769): The types are outdated.
    silent: false,
    env: process.env
  });

  if (result.status !== 0) {
    const error = JSON.parse(result.stderr.toString());
    // TODO(@jfmengels): Check for other kinds of errors.
    if (error.title !== 'NO INPUT') {
      // TODO(@jfmengels): Print the error nicely.
      throw new Error(error);
    }
  }
}

/**
 * @param {string} version
 * @returns {VersionString}
 */
function trimVersion(version) {
  const index = version.indexOf('-');
  if (index === -1) {
    return /** @type {VersionString} */ (version.trim());
  }

  return /** @type {VersionString} */ (version.slice(0, index).trim());
}

module.exports = {
  getElmBinary,
  getElmVersion,
  downloadDependenciesOfElmJson
};
