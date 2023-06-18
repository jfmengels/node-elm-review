const chalk = require('chalk');

/**
 * @type {(input: string, columns: number) => string }
 */
// eslint-disable-next-line @typescript-eslint/ban-ts-comment
// @ts-ignore: wrap-ansi includes type definitions since version 8, but it also requires node 12
const wrap = require('wrap-ansi');
const stripAnsi = require('strip-ansi');
const terminalLink = require('terminal-link');

/**
 * @typedef { import("./types/options").Options } Options
 * @typedef { import('./types/styled-message').FormattedString } FormattedString
 * @typedef { import("./types/styled-message").StyledMessage } StyledMessage
 * @typedef { import('./types/styled-message').StyledMessagePart } StyledMessagePart
 */

// LOG

/**
 * @param {Options} options
 * @param {StyledMessage} message
 * @param {boolean} clearFixLine
 */
function clearAndLog(options, message, clearFixLine) {
  if (options.watch && !options.debug && options.report !== 'json') {
    clearConsole();
  } else if (clearFixLine && process.stdout.isTTY) {
    process.stdout.clearLine(0);
    process.stdout.cursorTo(0);
  }

  log(options, message);
}

/**
 * @param {Options} options
 * @param {StyledMessage} message
 */
function log(options, message) {
  const colorEnabled = options.color !== false && options.report === null;
  console.log(wrapLinesForTerminal(styleMessage(colorEnabled, message)));
}

// COLORING

/**
 * @param {boolean} colorEnabled
 * @param {StyledMessage} message
 * @returns
 */
function styleMessage(colorEnabled, message) {
  return message
    .map((part) => {
      if (typeof part === 'string') {
        return part;
      }

      if (!colorEnabled) {
        return part.string;
      }

      const stringWithLink =
        part.href && terminalLink.isSupported
          ? terminalLink(part.string, part.href)
          : part.string;

      return withStyling(part)(stringWithLink);
    })
    .join('');
}

/**
 * @param {FormattedString} part
 * @returns {chalk.Chalk}
 */
function withStyling(part) {
  return part.color ? chalk.hex(part.color) : chalk;
}

// WRAP LINES

const codeBlockRegex = /^(\s{4}|\s{0,2}\d+\|\s|[\s^]*$|^·+$)/;

/**
 * @param {string} message
 * @returns {string}
 */
function wrapLinesForTerminal(message) {
  return message
    .split('\n\n')
    .map((paragraph) => {
      // Don't wrap what looks like code blocks, code extracts
      // or the line with ^^^^
      if (
        paragraph
          .split('\n')
          .every((line) => codeBlockRegex.test(stripAnsi(line)))
      ) {
        return paragraph;
      }

      return wrap(paragraph, 80);
    })
    .join('\n\n');
}

// CLEARING CONSOLE

function clearConsole() {
  process.stdout.write(
    process.platform === 'win32'
      ? '\u001B[2J\u001B[0f'
      : '\u001B[2J\u001B[3J\u001B[H'
  );
}

module.exports = {
  clearAndLog,
  log
};
