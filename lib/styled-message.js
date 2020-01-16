const chalk = require('chalk');

// LOG

function styledMessage(options, message) {
  if (options.watch && !options.debug) {
    clearConsole();
  }

  const colorEnabled = options.color === undefined;
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

function clearConsole() {
  process.stdout.write(
    process.platform === 'win32'
      ? '\u001B[2J\u001B[0f'
      : '\u001B[2J\u001B[3J\u001B[H'
  );
}

module.exports = styledMessage;
