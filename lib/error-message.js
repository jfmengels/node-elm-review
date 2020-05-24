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

const create = (title, message, path) =>
  JSON.stringify({
    customElmReviewError: true,
    title,
    path,
    message
  });

const formatHuman = (options, error) =>
  `${chalk.green(
    `-- ${error.title} ${'-'.repeat(80 - error.title.length - 4)}`
  )}

${error.message.trim()}${stacktrace(options, error)}
`;

function stacktrace(options, error) {
  if (options.debug) {
    return '\n' + error.stack;
  }

  return '';
}

const formatJson = (options, error, defaultPath) => {
  return {
    title: error.title,
    path: error.path || defaultPath,
    error: stripAnsi(error.message.trim()),
    stack: options.debug ? stripAnsi(error.stack) : undefined
  };
};

module.exports = {
  CustomError,
  create,
  formatHuman,
  formatJson
};
