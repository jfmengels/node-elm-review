/**
 * @import {ProcessOutput} from 'zx' with {'resolution-mode': 'import'};
 * @import {Options} from './types/cli';
 */

const path = require('node:path');
const {TextDecoder} = require('node:util');
const {toMatchFile} = require('jest-file-snapshot');
// @ts-expect-error(TS1479): zx doesn't ship CJS types.
const {$} = require('zx');
const {app} = require('../../lib/main');
const Options_ = require('../../lib/options');

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
 * Capture all writes to process.stdout during the execution of fn.
 *
 * @param {() => Promise<void>} fn - Function to run while capturing stdout
 * @returns {Promise<{ error?: unknown, stdout: string }>}
 */
async function withCapturedStdout(fn) {
  const decoder = new TextDecoder();

  let stdout = '';
  const stdoutWriteSpy = jest
    .spyOn(process.stdout, 'write')
    .mockImplementation((chunk) => {
      stdout += typeof chunk === 'string' ? chunk : decoder.decode(chunk);

      return true;
    });
  const processExitSpy = jest
    .spyOn(process, 'exit')
    .mockImplementation((code) => {
      throw new Error(`process.exit was called with exit code ${code}`);
    });

  try {
    process.stderr.write('Running function with captured stdout\n');
    await fn();
    return {stdout};
  } catch (err) {
    process.stderr.write('Function threw an error\n');
    return {stdout, error: err};
  } finally {
    process.stderr.write('Restoring mocks\n');
    processExitSpy.mockRestore();
    stdoutWriteSpy.mockRestore();
  }
}

/**
 *
 * @param {string[]} args
 * @param {string} project
 * @returns {Promise<{stdout: string, error: unknown}>}
 */
async function internalRun(args, project) {
  const options = Options_.compute(
    args,
    path.resolve(__dirname, '..', project)
  );

  const {stdout, error} = await withCapturedStdout(async () => {
    await app(options, (err) => {
      throw err;
    });
  });

  return {stdout, error};
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
  runWithoutTestMode,
  internalRun
};
