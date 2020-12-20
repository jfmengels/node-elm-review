const chalk = require('chalk');
const stripAnsi = require('strip-ansi');
const Anonymize = require('./anonymize');

class CustomError extends Error {
  constructor(title, message, path) {
    super(message);
    this.title = title;
    this.message = message;
    this.path = path;
  }
}

function report(options, err, defaultPath) {
  if (options.report === 'json') {
    return Anonymize.pathsAndVersions(
      options,
      Anonymize.pathsAndVersions(
        options,
        JSON.stringify(
          formatJson(options.debug, err, defaultPath),
          null,
          options.debug || options.forTests ? 2 : 0
        )
      )
    );
  }

  return Anonymize.pathsAndVersions(options, formatHuman(options.debug, err));
}

function unexpectedError(err) {
  const error = new CustomError(
    'UNEXPECTED ERROR',
    `I ran into an unexpected error. Please open an issue at the following link:
  https://github.com/jfmengels/node-elm-review/issues/new

Please include this error message and as much detail as you can provide. If you
can, please provide a setup that makes it easy to reproduce the error. That will
make it much easier to fix the issue.

Below is the error that was encountered.
--------------------------------------------------------------------------------
${err.stack}
`
  );
  error.stack = err.stack || error.stack;
  return error;
}

const formatHuman = (debug, error) =>
  `${chalk.green(
    `-- ${error.title} ${'-'.repeat(80 - error.title.length - 4)}`
  )}

${error.message.trim()}${stacktrace(debug, error)}
`;

function stacktrace(debug, error) {
  if (debug) {
    return '\n' + error.stack;
  }

  return '';
}

const formatJson = (debug, error, defaultPath) => {
  return {
    type: 'error',
    title: error.title,
    path: error.path || defaultPath,
    // TODO We currently strip the colors, but it would be nice to keep them
    // so that editors can have nicer error messages
    message: [stripAnsi(error.message.trim())],
    stack: debug ? stripAnsi(error.stack) : undefined
  };
};

module.exports = {
  CustomError,
  unexpectedError,
  formatHuman,
  report
};
