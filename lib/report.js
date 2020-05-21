const styledMessage = require('./styled-message');

module.exports = report;

function report(options, result) {
  if (options.report === 'json') {
    return jsonReport(options, result);
  }

  return styledMessage.log(options, result.report);
}

// JSON

function jsonReport(options, result) {
  console.log(
    JSON.stringify(
      {
        reportVersion: 1,
        errors: result.json
      },
      0,
      options.debug ? 2 : 0
    )
  );
}
