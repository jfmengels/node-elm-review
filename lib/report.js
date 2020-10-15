const styledMessage = require('./styled-message');

module.exports = report;

async function report(options, result) {
  if (options.report === 'json') {
    return print(options, jsonReport(result.errors));
  }

  return styledMessage.clearAndLog(options, result.errors);
}

// JSON

function jsonReport(errors) {
  return {
    type: 'review-errors',
    errors
  };
}

function print(options, json) {
  if (options.reportOnOneLine) {
    if (json.type === 'review-errors') {
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
      return safeConsoleLog(JSON.stringify(json));
    }
  } else {
    return safeConsoleLog(
      JSON.stringify(json, null, options.debug || options.forTests ? 2 : 0)
    );
  }
}

// Printing large outputs to stdout is not recommended because at times
// console.log is asynchronous and returns before ensuring that the whole
// output has been printed. Check out these links for more details:
//
// - https://nodejs.org/api/process.html#process_process_exit_code
// - https://github.com/nodejs/node/issues/6456
// - https://github.com/nodejs/node/issues/19218
//
// Using process.stdout.write and passing a function ensures that
// the whole output has been written.
function safeConsoleLog(message) {
  return new Promise((resolve) => {
    process.stdout.write(message + '\n', () => {
      resolve();
    });
  });
}
