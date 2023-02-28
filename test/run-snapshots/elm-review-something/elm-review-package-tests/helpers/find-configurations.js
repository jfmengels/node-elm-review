const path = require('path');
const {globSync} = require('glob');

const root = path
  .resolve(__dirname, '../../')
  .replace(/.:/, '')
  .replace(/\\/g, '/');

module.exports = {
  findPreviewConfigurations
};

function findPreviewConfigurations() {
  return globSync(`${root}/preview*/**/elm.json`, {
    ignore: ['**/elm-stuff/**'],
    nodir: true
  }).map(path.dirname);
}
