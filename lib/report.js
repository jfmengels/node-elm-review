const styledMessage = require('./styled-message');

module.exports = report;

function report(options, result) {
  if (options.report === 'json') {
    return jsonReport(options, result.report);
  }

  return styledMessage.log(options, result.report);
}

// JSON

function jsonReport(options, reportAsJson) {
  const json = {
    reportVersion: 1,
    report: reportAsJson
  };

  if (options.debug) {
    console.log(JSON.stringify(json, 0, 2));
  } else {
    console.log(JSON.stringify(json));
  }
}
