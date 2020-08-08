const ora = require('ora');
const appState = require('./state');

const options = appState.getOptions();

module.exports = {
  setText: options.report === 'json' ? (v) => v : setText,
  succeed: options.report === 'json' ? (v) => v : succeed,
  fail: options.report === 'json' ? (v) => v : fail
};

let spinner;

function setText(text) {
  if (spinner) {
    spinner.text = text;
  } else {
    spinner = ora({text, isEnabled: !options.forTests}).start();
  }
}

function succeed(text) {
  spinner.succeed(text);
  spinner = null;
}

function fail(text) {
  if (spinner) {
    spinner.fail(text);
    spinner = null;
  }
}
