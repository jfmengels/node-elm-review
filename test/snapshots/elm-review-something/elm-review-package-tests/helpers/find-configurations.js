const path = require('path');
const glob = require('glob');

const root = path
  .resolve(__dirname, '../../')
  .replace(/.:/, '')
  .replace(/\\/g, '/');

module.exports = {
  findPreviewConfigurations,
  findExampleAndPreviewConfigurations
};

function findPreviewConfigurations() {
  return glob
    .sync(`${root}/preview*/**/elm.json`, {
      ignore: ['**/elm-stuff/**'],
      nodir: true
    })
    .map(path.dirname);
}

function findExampleAndPreviewConfigurations() {
  return glob
    .sync(`${root}/@(example|preview)*/**/elm.json`, {
      ignore: ['**/elm-stuff/**'],
      nodir: true
    })
    .map(path.dirname);
}
