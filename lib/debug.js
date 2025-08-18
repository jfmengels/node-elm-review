/**
 * @param {string} message
 * @param {boolean} isDebug
 * @returns {void}
 */
function log(message, isDebug) {
  if (isDebug) {
    console.log(message);
  }
}

module.exports = {
  log
};
