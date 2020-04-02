const chalk = require('chalk');
const wrap = require('wrap-ansi');
const stripAnsi = require('strip-ansi');

// LOG

function log(options, message) {
  if (options.watch && !options.debug) {
    clearConsole();
  }

  const colorEnabled = options.color === undefined;
  console.log(wrapLinesForTerminal(colorMessage(colorEnabled, message)));
}

// COLORING

function colorMessage(colorEnabled, message) {
  return message
    .map(part => {
      const chalkWithColor = colorEnabled ? withColor(part) : chalk;
      return chalkWithColor(part.string);
    })
    .join('');
}

function withColor(part) {
  const chalkWithColor = part.color
    ? chalk.rgb(part.color[0], part.color[1], part.color[2])
    : chalk;
  return part.backgroundColor
    ? chalkWithColor.bgRgb(
        part.backgroundColor[0],
        part.backgroundColor[1],
        part.backgroundColor[2]
      )
    : chalkWithColor;
}

// WRAP LINES

const codeBlockRegex = /^(\s{4}|\d+\|\s|[\s^]*$)/;

function wrapLinesForTerminal(message) {
  return message
    .split('\n\n')
    .map(paragraph => {
      // Don't wrap what looks like code blocks, code extracts
      // or the line with ^^^^
      if (
        paragraph
          .split('\n')
          .every(line => codeBlockRegex.test(stripAnsi(line)))
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
  log
};
