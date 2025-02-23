/**
 * @import {ProcessOutput} from 'zx' with {'resolution-mode': 'import'};
 * @import {Options} from './types/cli';
 */

const path = require('pathe');
const {toMatchFile} = require('jest-file-snapshot');
// @ts-expect-error(TS1479): zx doesn't ship CJS types.
const {$} = require('zx');

const cli = path.resolve(__dirname, '../../bin/elm-review');
expect.extend({toMatchFile});

/**
 * @param {string[]} args
 * @param {Options} [options]
 * @returns {Promise<string>}
 */
async function run(args, options) {
  const output = await internalExec(['--FOR-TESTS', ...args], options);

  if (output.exitCode !== 0) throw new Error(output.text());

  return output.stdout;
}

/**
 * @param {string[]} args
 * @param {Options | undefined} [options]
 * @returns {Promise<unknown>}
 */
async function runAndExpectError(args, options) {
  const output = await internalExec(['--FOR-TESTS', ...args], options);
  if (output.exitCode !== 0) {
    return output.stdout; // Should this be stderr?
  }

  throw new Error(
    `CLI did not exit with an exit code as expected. Here is its output:

  ${output.text()}`
  );
}

/**
 * @param {string[]} args
 * @param {Options | undefined} [options]
 * @returns {Promise<string>}
 */
async function runWithoutTestMode(args, options) {
  const output = await internalExec(args, options);

  if (output.exitCode !== 0) throw new Error(output.text());

  return output.stdout;
}

/**
 * @param {string[]} args
 * @param {Options} [options]
 * @returns {Promise<ProcessOutput>}
 */
async function internalExec(args, options = {}) {
  const result = await $({
    cwd: cwdFromOptions(options),
    env: {
      ...process.env,
      // Overriding `FORCE_COLOR` because Jest forcefully adds it as well,
      // which otherwise enables colors when we don't want it.
      FORCE_COLOR: options.colors ? '1' : '0'
    },
    quiet: true
  })`${cli} ${reportMode(options)} ${colors(options)} ${args}`.nothrow();
  return result;
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
 * @returns {string[]}
 */
function reportMode(options) {
  if (!options.report) {
    return [];
  }

  return [`--report=${options.report}`];
}

/**
 * @param {Options} options
 * @returns {string[]}
 */
function colors(options) {
  if (options.colors) {
    return [];
  }

  return ['--no-color'];
}

module.exports = {
  run,
  runAndExpectError,
  runWithoutTestMode
};
