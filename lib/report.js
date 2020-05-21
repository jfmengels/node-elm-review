const styledMessage = require('./styled-message');

module.exports = report;

function report(options, result) {
  if (options.report === 'json') {
    return jsonReport(result);
  }

  return styledMessage.log(options, result.report);
}

// JSON

function jsonReport(result) {
  console.log(JSON.stringify(result.json, 0, 4));
}
