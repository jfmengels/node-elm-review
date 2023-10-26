const ora = require('ora');
const AppState = require('./state');

/**
 * @typedef { import("./types/options").Options } Options
 * @typedef { import("ora").Ora } Ora
 */

/** @type {Options} */
const options = AppState.getOptions();

module.exports = {
  setText: options.report === 'json' ? (v) => v : setText,
  succeed: options.report === 'json' ? (v) => v : succeed,
  succeedAndNowDo: options.report === 'json' ? (v) => v : succeedAndNowDo,
  fail: options.report === 'json' ? (v) => v : fail
};

/**
 * @type {Ora | null}
 */
let spinner;

/** Set the text of the spinner.
 *
 * @param {string} text
 * @returns {void}
 */
function setText(text) {
  if (spinner) {
    spinner.text = text;
  } else {
    spinner = ora({text, isEnabled: !options.forTests}).start();
  }
}

/** Completes the current task and replaces its text with the given text.
 *
 * @param {string | undefined} [text]
 * @returns {void}
 */
function succeed(text) {
  if (!spinner) {
    return;
  }

  spinner.succeed(text);
  spinner = null;
}

/** Completes the current task, and starts a new one with the given text.
 *
 * @param {string} text
 * @returns {void}
 */
function succeedAndNowDo(text) {
  if (!spinner) {
    return;
  }

  spinner.succeed();
  spinner.start(text);
}

/** Fails the current task and replaces its text with the given text.
 *
 * @param {string | undefined} text
 * @returns {void}
 */
function fail(text) {
  if (!spinner) {
    return;
  }

  spinner.fail(text);
  spinner = null;
}
