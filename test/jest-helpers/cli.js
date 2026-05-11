/**
 * @import {ProcessOutput} from 'zx' with {'resolution-mode': 'import'};
 * @import {Options} from './types/cli';
 */

const path = require('node:path');
const {toMatchFile} = require('jest-file-snapshot');
// @ts-expect-error(TS1479): zx doesn't ship CJS types.
const {$} = require('zx');

const packageJson = require('../../package.json');

const cli = path.resolve(__dirname, '../../bin/elm-review');

expect.extend({toMatchFile});

/**
 * Strip the path and version out of the given string.
 * This is to remove the absolute paths from the output, which would break snapshots when run on different computers.
 *
 * Also formats the output to readable JSON is the output is JSON parsable.
 *
 * @param {string} output
 * @returns {string}
 */
function anonymizeAndFormat(output) {
  const anonymized = output
    .split(path.dirname(__dirname))
    .join('<local-path>')
    .split(packageJson.version)
    .join('<version>');
  try {
    return JSON.stringify(JSON.parse(anonymized), null, 2);
  } catch {
    return anonymized;
  }
}

/**
 * @param {string[]} args
 * @param {Options} [options]
 * @returns {Promise<string>}
 */
async function run(args, options) {
  const cwd = cwdFromOptions(options);
  const output = await internalExec(args, cwd, options);

  if (output.exitCode !== 0) throw new Error(output.text());

  return anonymizeAndFormat(output.stdout);
}

/**
 * @param {string[]} args
 * @param {Options | undefined} [options]
 * @returns {Promise<unknown>}
 */
async function runAndExpectError(args, options) {
  const cwd = cwdFromOptions(options);
  const output = await internalExec(args, cwd, options);
  if (output.exitCode !== 0) {
    return anonymizeAndFormat(output.stdout); // Should this be stderr?
  }

  throw new Error(
    `CLI did not exit with an exit code as expected. Here is its output:

  ${anonymizeAndFormat(output.text())}`
  );
}

/**
 * @param {string[]} args
 * @param {Options | undefined} [options]
 * @returns {Promise<string>}
 */
async function runWithoutPostProcessing(args, options) {
  const cwd = cwdFromOptions(options);
  const output = await internalExec(args, cwd, options);

  if (output.exitCode !== 0) throw new Error(output.text());

  return output.stdout;
}

/**
 * @param {string[]} args
 * @param {string} cwd
 * @param {Options} [options]
 * @returns {Promise<ProcessOutput>}
 */
async function internalExec(args, cwd, options = {}) {
  const result = await $({
    cwd: cwd,
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
 * @param {Options | undefined} options
 * @returns {string}
 */
function cwdFromOptions(options) {
  if (!options) {
    return path.dirname(__dirname);
  }

  if (options.project) {
    return path.resolve(__dirname, '..', options.project);
  }

  return options.cwd ?? __dirname;
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
  runWithoutPostProcessing
};
