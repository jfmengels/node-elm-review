const crypto = require('crypto');

module.exports = {hash};

/**
 * Hash a string.
 * @param {string} content
 * @returns {string}
 */
function hash(content) {
  return crypto.createHash('md5').update(content).digest('hex');
}
