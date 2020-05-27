const chalk = require('chalk');
const stripAnsi = require('strip-ansi');

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
    if (options.debug) {
      return JSON.stringify(
        formatJson(options.debug, err, defaultPath),
        null,
        2
      );
    }

    return JSON.stringify(formatJson(options.debug, err, defaultPath));
  }

  return formatHuman(options.debug, err);
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
    message: stripAnsi(error.message.trim()),
    stack: debug ? stripAnsi(error.stack) : undefined
  };
};

module.exports = {
  CustomError,
  report
};
