const path = require('node:path');
const {globSync} = require('tinyglobby');

const root = path
  .resolve(__dirname, '../../')
  .replace(/.:/, '')
  .replace(/\\/g, '/');

/**
 * @returns {string[]}
 */
function findPreviewConfigurations() {
  return globSync(`${root}/preview*/**/elm.json`, {
    ignore: ['**/elm-stuff/**']
  }).map((val) => path.dirname(val));
}

module.exports = {
  findPreviewConfigurations
};
