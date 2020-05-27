const styledMessage = require('./styled-message');

module.exports = report;

function report(options, result) {
  if (options.report === 'json') {
    return print(options, jsonReport(result.errors));
  }

  return styledMessage.log(options, result.errors);
}

// JSON

function jsonReport(errors) {
  return {
    type: 'review-errors',
    errors
  };
}

function print(options, json) {
  if (options.debug) {
    console.log(JSON.stringify(json, null, 2));
  } else {
    console.log(JSON.stringify(json));
  }
}
