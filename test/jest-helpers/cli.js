const path = require('node:path');
const {promisify} = require('node:util');
const {toMatchFile} = require('jest-file-snapshot');
const exec = promisify(require('node:child_process').exec);

const cli = path.resolve(__dirname, '../../bin/elm-review');
expect.extend({toMatchFile});

/**
 * @import {Options} from './types/cli';
 */

/**
 * @param {string} args
 * @param {Options} [options]
 * @returns {Promise<string>}
 */
async function run(args, options) {
  return await internalExec(`--FOR-TESTS ${args}`, options);
}

/**
 * @param {string} args
 * @param {Options | undefined} [options]
 * @returns {Promise<unknown>}
 */
async function runAndExpectError(args, options) {
  try {
    const output = await internalExec(`--FOR-TESTS ${args}`, options);
    throw new Error(
      `CLI did not exit with an exit code as expected. Here is its output:\n\n${output}`
    );
  } catch (/** @type {unknown} */ error) {
    return error;
  }
}

/**
 * @param {string} args
 * @param {Options | undefined} [options]
 * @returns {Promise<string>}
 */
async function runWithoutTestMode(args, options) {
  return await internalExec(args, options);
}

/**
 * @param {string} args
 * @param {Options} [options]
 * @returns {Promise<string>}
 */
async function internalExec(args, options = {}) {
  // Overriding FORCE_COLOR because Jest forcefully adds it as well,
  // which otherwise enables colors when we don't want it.
  const colorFlag = 'FORCE_COLOR=' + (options.colors ? '1' : '0');

  try {
    // If this just uses child_process.exec, the shell scripts are pointless, and should be all migrated to Jest tests.
    const result = await exec(
      [colorFlag, cli, reportMode(options), colors(options), args].join(' '),
      {
        ...options,
        cwd: cwdFromOptions(options)
      }
    );
    return result.stdout;
  } catch (error) {
    throw error.stdout;
  }
}

/**
 * @param {Options} options
 * @returns {string | undefined}
 */
function cwdFromOptions(options) {
  if (options.project) {
    return path.resolve(__dirname, '..', options.project);
  }

  return options.cwd;
}

/**
 * @param {Options} options
 * @returns {string}
 */
function reportMode(options) {
  if (!options.report) {
    return '';
  }

  return `--report=${options.report}`;
}

/**
 * @param {Options} options
 * @returns {"" | "--no-color"}
 */
function colors(options) {
  if (options.colors) {
    return '';
  }

  return `--no-color`;
}

module.exports = {
  run,
  runAndExpectError,
  runWithoutTestMode
};
