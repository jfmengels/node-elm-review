const AppState = require('./state');

const options = AppState.getOptions();

/**
 * @param {string} message
 * @returns {void}
 */
function log(message) {
  if (options.debug) {
    console.log(message);
  }
}

module.exports = {
  log
};
