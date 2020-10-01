const styledMessage = require('./styled-message');

module.exports = report;

function report(options, result) {
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
      json.errors.forEach((errorForFile) => {
        errorForFile.errors.forEach((error) => {
          console.log(
            JSON.stringify({
              path: errorForFile.path,
              ...error
            })
          );
        });
      });
    } else {
      console.log(JSON.stringify(json));
    }
  } else {
    console.log(
      JSON.stringify(json, null, options.debug || options.forTests ? 2 : 0)
    );
  }
}
