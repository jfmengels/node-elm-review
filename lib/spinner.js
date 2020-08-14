const ora = require('ora');
const AppState = require('./state');

const options = AppState.getOptions();

module.exports = {
  setText: options.report === 'json' ? (v) => v : setText,
  succeed: options.report === 'json' ? (v) => v : succeed,
  succeedAndNowDo: options.report === 'json' ? (v) => v : succeedAndNowDo,
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

function succeedAndNowDo(text) {
  spinner.succeed();
  spinner.start(text);
}

function fail(text) {
  if (spinner) {
    spinner.fail(text);
    spinner = null;
  }
}
