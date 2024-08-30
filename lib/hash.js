const crypto = require('node:crypto');

/**
 * Hash a string.
 *
 * @param {string} content
 * @returns {string}
 */
function hash(content) {
  return crypto.createHash('md5').update(content).digest('hex');
}

module.exports = {
  hash
};
