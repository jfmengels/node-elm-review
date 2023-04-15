const crypto = require('crypto');

module.exports = {hash};

function hash(content) {
  return crypto.createHash('md5').update(content).digest('hex');
}
