const path = require('node:path');
const {glob} = require('glob');

const root = path
  .resolve(__dirname, '../../')
  .replace(/.:/, '')
  .replace(/\\/g, '/');

/**
 * @returns {string[]}
 */
function findPreviewConfigurations() {
  return glob
    .sync(`${root}/preview*/**/elm.json`, {
      ignore: ['**/elm-stuff/**'],
      nodir: true
    })
    .map((val) => path.dirname(val));
}

module.exports = {
  findPreviewConfigurations
};
