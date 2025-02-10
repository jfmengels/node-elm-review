/**
 * @import {Options} from './types/options';
 * @import {Report} from './types/report';
 */
const Benchmark = require('./benchmark');
const StyledMessage = require('./styled-message');

/**
 * @param {Options} options
 * @param {Report} result
 * @returns {Promise<void>}
 */
async function report(options, result) {
  Benchmark.start(options, 'Writing error report');
  if (options.report === 'json') {
    await print(options, result);
  } else {
    StyledMessage.clearAndLog(options, result.errors ?? [], false);
  }

  Benchmark.end(options, 'Writing error report');
}

// JSON

/**
 * @param {Options} options
 * @param {Report} json
 * @returns {Promise<void>}
 */
async function print(options, json) {
  if (options.reportOnOneLine) {
    if ((json.errors?.length ?? 0) > 0) {
      await safeConsoleLog(
        json.errors
          ?.map((errorForFile) => {
            return errorForFile.errors
              .map((error) => {
                return JSON.stringify({
                  path: errorForFile.path,
                  ...error
                });
              })
              .join('\n');
          })
          .join('\n') ?? ''
      );
    }
  } else {
    await safeConsoleLog(
      JSON.stringify(
        {
          version: '1',
          cliVersion: options.packageJsonVersion,
          type: 'review-errors',
          errors: json.errors,
          extracts: json.extracts
        },
        null,
        options.debug || options.forTests ? 2 : 0
      )
    );
  }
}

/**
 * Prints a message in a way that will not be cut off.
 *
 * @remarks
 * Printing large outputs to stdout is not recommended because at times
 * console.log is asynchronous and returns before ensuring that the whole
 * output has been printed. Check out these links for more details:
 *
 * - <https://nodejs.org/api/process.html#process_process_exit_code>
 * - nodejs/node#6456
 * - nodejs/node#19218
 *
 * Using {@linkcode process.stdout.write} and passing a function ensures that
 * the whole output has been written.
 *
 * @param {string} message - Message to print.
 * @returns {Promise<void>}
 */
async function safeConsoleLog(message) {
  await new Promise((/** @type {(value?: never) => void} */ resolve) => {
    process.stdout.write(message + '\n', () => {
      resolve();
    });
  });
}

module.exports = {
  report
};
