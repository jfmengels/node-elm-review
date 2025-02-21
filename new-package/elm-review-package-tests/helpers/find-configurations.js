const path = require('node:path');
const {globSync} = require('tinyglobby');

const root = path.resolve(__dirname, '../../');

/**
 * @returns {string[]}
 */
function findPreviewConfigurations() {
  return globSync('preview*/**/elm.json', {
    ignore: ['**/elm-stuff/**'],
    cwd: root,
    absolute: true
  }).map((val) => path.dirname(val));
}

module.exports = {
  findPreviewConfigurations
};
