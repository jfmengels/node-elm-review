/**
 * @import {ReportMode} from './types/options';
 */
const ora = require('ora');

/**
 * @type {ora.Ora | null}
 */
let spinner;

/**
 * Set the text of the spinner.
 *
 * @param {string} text
 * @param {ReportMode} reportFormat
 * @param {boolean} forTests
 * @returns {void}
 */
function setText(text, reportFormat, forTests) {
  if (reportFormat === 'json') return;

  if (spinner) {
    spinner.text = text;
  } else {
    spinner = ora({text, isEnabled: !forTests}).start();
  }
}

/**
 * Completes the current task and replaces its text with the given text.
 *
 * @param {string | undefined} text
 * @param {ReportMode} reportFormat
 * @returns {void}
 */
function succeed(text, reportFormat) {
  if (reportFormat === 'json') return;

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
 * @param {ReportMode} reportFormat
 * @returns {void}
 */
function succeedAndNowDo(text, reportFormat) {
  if (reportFormat === 'json') return;

  if (!spinner) {
    return;
  }

  spinner.succeed();
  spinner.start(text);
}

/**
 * Fails the current task and replaces its text with the given text.
 *
 * @param {string | undefined} text
 * @param {ReportMode} reportFormat
 * @returns {void}
 */
function fail(text, reportFormat) {
  if (reportFormat === 'json') return;

  if (!spinner) {
    return;
  }

  spinner.fail(text);
  spinner = null;
}

module.exports = {
  setText: setText,
  succeed: succeed,
  succeedAndNowDo: succeedAndNowDo,
  fail: fail
};
