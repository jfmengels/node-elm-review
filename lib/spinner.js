/**
 * @import {Options} from './types/options';
 */
const ora = require('ora');
const AppState = require('./state');

/** @type {Options} */
const options = AppState.getOptions();

/**
 * @type {ora.Ora | null}
 */
let spinner;

/**
 * Set the text of the spinner.
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

/**
 * Completes the current task and replaces its text with the given text.
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

/**
 * Completes the current task, and starts a new one with the given text.
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

/**
 * Fails the current task and replaces its text with the given text.
 *
 * @param {string | undefined} [text]
 * @returns {void}
 */
function fail(text) {
  if (!spinner) {
    return;
  }

  spinner.fail(text);
  spinner = null;
}

/**
 * @template {(v: string) => void} T
 * @param {T} func
 * @returns {(T | (() => void))}
 */
function exportFunc(func) {
  return options.report === 'json' ? () => {} : func;
}

module.exports = {
  setText: exportFunc(setText),
  succeed: exportFunc(succeed),
  succeedAndNowDo: exportFunc(succeedAndNowDo),
  fail: exportFunc(fail)
};
