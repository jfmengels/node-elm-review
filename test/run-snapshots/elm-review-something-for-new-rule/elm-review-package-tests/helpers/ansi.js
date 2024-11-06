/**
 * @param {string} text
 * @returns {string}
 */
function red(text) {
  return `\u001B[31m${text}\u001B[39m`;
}

/**
 * @param {string} text
 * @returns {string}
 */
function green(text) {
  return `\u001B[32m${text}\u001B[39m`;
}

/**
 * @param {string} text
 * @returns {string}
 */
function yellow(text) {
  return `\u001B[33m${text}\u001B[39m`;
}

module.exports = {
  red,
  green,
  yellow
};
