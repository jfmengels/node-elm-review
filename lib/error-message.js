/**
 * @import {Options} from './types/options';
 * @import {Path} from './types/path';
 */
const chalk = require('chalk');
const stripAnsi = require('strip-ansi');
const Anonymize = require('./anonymize');

class CustomError extends Error {
  /**
   * @param {string} title
   * @param {string} message
   * @param {Path | null} [path]
   */
  constructor(title, message, path) {
    super(message);
    this.title = title;
    this.message = message;
    this.path = path;
  }
}

/**
 * @param {Options} options
 * @param {CustomError} err
 * @param {Path} [defaultPath]
 * @returns {string}
 */
function report(options, err, defaultPath) {
  if (options.report === 'json') {
    return Anonymize.pathsAndVersions(
      JSON.stringify(
        formatJson(options.debug, err, defaultPath),
        null,
        options.debug || options.forTests ? 2 : 0
      ),
      options.forTests
    );
  }

  return Anonymize.pathsAndVersions(
    formatHuman(options.debug, err),
    options.forTests
  );
}

/**
 * @param {Error} err
 * @returns {CustomError}
 */
function unexpectedError(err) {
  const error = new CustomError(
    'UNEXPECTED ERROR',
    // prettier-ignore
    `I ran into an unexpected error. Please open an issue at the following link:
  https://github.com/jfmengels/node-elm-review/issues/new

Please include this error message and as much detail as you can provide. Running
with ${chalk.yellow('--debug')} might give additional information. If you can, please provide a
setup that makes it easy to reproduce the error. That will make it much easier
to fix the issue.

Below is the error that was encountered.
--------------------------------------------------------------------------------
${err.stack}
`
  );
  error.stack = err.stack ?? error.stack;
  return error;
}

/**
 * @param {boolean} debug
 * @param {CustomError} error
 * @returns {string}
 */
const formatHuman = (debug, error) =>
  `${chalk.green(
    `-- ${error.title} ${'-'.repeat(80 - error.title.length - 4)}`
  )}

${error.message.trim()}${stacktrace(debug, error)}
`;

/**
 * @param {boolean} debug
 * @param {CustomError} error
 * @returns {string}
 */
function stacktrace(debug, error) {
  if (debug) {
    return '\n' + error.stack;
  }

  return '';
}

/**
 * @param {boolean} debug
 * @param {CustomError} error
 * @param {Path} [defaultPath]
 * @returns {{type: string; title: string; path: string | undefined; message: string[]; stack: string | undefined}}
 */
function formatJson(debug, error, defaultPath) {
  return {
    type: 'error',
    title: error.title,
    path: error.path ?? defaultPath,
    // TODO(@jfmengels): We currently strip the colors, but it would be nice to keep them so that editors can have nicer error messages.
    message: [stripAnsi(error.message.trim())],
    stack: debug && error.stack ? stripAnsi(error.stack) : undefined
  };
}

module.exports = {
  CustomError,
  unexpectedError,
  formatHuman,
  report
};
