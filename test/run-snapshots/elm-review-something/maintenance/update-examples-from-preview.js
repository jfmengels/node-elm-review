#!/usr/bin/env node

const path = require('node:path');
const fs = require('fs-extra');
const root = path.resolve(__dirname, '..');
const packageElmJson = require(`${root}/elm.json`);
const {
  findPreviewConfigurations
} = require('../elm-review-package-tests/helpers/find-configurations');

if (require.main === module) {
  copyPreviewsToExamples();
} else {
  module.exports = copyPreviewsToExamples;
}

// Find all elm.json files

/**
 * @typedef {object} ApplicationElmJson
 * @property {string[]} source-directories
 * @property {DependencyList} dependencies
 */

/**
 * @typedef {object} DependencyList
 * @property {Record<string, string>} direct
 * @property {Record<string, string>} indirect
 */

/**
 * @returns {void}
 */
function copyPreviewsToExamples() {
  const previewFolders = findPreviewConfigurations();
  for (const folder of previewFolders) {
    copyPreviewToExample(folder);
  }
}

/**
 * @param {string} pathToPreviewFolder
 * @returns {void}
 */
function copyPreviewToExample(pathToPreviewFolder) {
  const pathToExampleFolder = `${pathToPreviewFolder}/`.replace(
    /preview/g,
    'example'
  );

  fs.rmSync(pathToExampleFolder, {
    recursive: true,
    force: true,
    maxRetries: 10
  });
  fs.copySync(pathToPreviewFolder, pathToExampleFolder, {overwrite: true});

  const pathToElmJson = path.resolve(pathToExampleFolder, 'elm.json');
  const elmJson = /** @type {ApplicationElmJson} */ (
    fs.readJsonSync(pathToElmJson)
  );

  // Remove the source directory pointing to the package's src/
  elmJson['source-directories'] = elmJson['source-directories'].filter(
    (sourceDirectory) =>
      path.resolve(pathToExampleFolder, sourceDirectory) !==
      path.resolve(root, 'src')
  );
  elmJson.dependencies.direct[packageElmJson.name] = packageElmJson.version;
  fs.writeJsonSync(pathToElmJson, elmJson, {spaces: 4});
}
