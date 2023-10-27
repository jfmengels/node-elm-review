const Benchmark = require('./benchmark');
const StyledMessage = require('./styled-message');

module.exports = {
  report
};

async function report(options, result) {
  Benchmark.start(options, 'Writing error report');
  if (options.report === 'json') {
    print(options, result);
  } else {
    StyledMessage.clearAndLog(options, result.errors, false);
  }

  Benchmark.end(options, 'Writing error report');
}

// JSON

function print(options, json) {
  if (options.reportOnOneLine) {
    if (json.errors.length > 0) {
      return safeConsoleLog(
        json.errors
          .map((errorForFile) => {
            return errorForFile.errors
              .map((error) => {
                return JSON.stringify({
                  path: errorForFile.path,
                  ...error
                });
              })
              .join('\n');
          })
          .join('\n')
      );
    }
  } else {
    return safeConsoleLog(
      JSON.stringify(
        {type: 'review-errors', errors: json.errors, extracts: json.extracts},
        null,
        options.debug || options.forTests ? 2 : 0
      )
    );
  }
}

/**
 * Prints a message in a way that will not be cut off.
 *
 * Printing large outputs to stdout is not recommended because at times
 * console.log is asynchronous and returns before ensuring that the whole
 * output has been printed. Check out these links for more details:
 *
 * - https://nodejs.org/api/process.html#process_process_exit_code
 * - https://github.com/nodejs/node/issues/6456
 * - https://github.com/nodejs/node/issues/19218
 *
 * Using process.stdout.write and passing a function ensures that
 * the whole output has been written.
 *
 * @param {string} message - Message to print.
 * @returns {Promise<void>}
 */
function safeConsoleLog(message) {
  return new Promise((resolve) => {
    process.stdout.write(message + '\n', () => {
      resolve();
    });
  });
}
