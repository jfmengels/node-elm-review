#!/usr/bin/env node

const path = require('path');
const glob = require('glob');
const fs = require('fs-extra');
const root = path.dirname(__dirname);
const packageElmJson = require(`${root}/elm.json`);

// Find all elm.json files

const previewElmJsonFiles = glob.sync(
  makePathOsAgnostic(`${root}/preview*/**/elm.json`),
  {
    nocase: true,
    ignore: ['**/elm-stuff/**'],
    nodir: false
  }
);

const previewFolders = previewElmJsonFiles.map(path.dirname);

previewFolders.forEach((pathToPreviewFolder) => {
  const pathToExampleFolder = `${pathToPreviewFolder}/`.replace(
    /preview/g,
    'example'
  );
  fs.removeSync(pathToExampleFolder);
  fs.copySync(pathToPreviewFolder, pathToExampleFolder, {overwrite: true});

  const pathToElmJson = path.resolve(pathToExampleFolder, 'elm.json');
  const elmJson = fs.readJsonSync(pathToElmJson);

  // Remove the source directory pointing to the package's src/
  elmJson['source-directories'] = elmJson['source-directories'].filter(
    (sourceDirectory) =>
      path.resolve(pathToExampleFolder, sourceDirectory) !==
      path.resolve(root, 'src')
  );
  elmJson.dependencies.direct[packageElmJson.name] = packageElmJson.version;
  fs.writeJsonSync(pathToElmJson, elmJson, {spaces: 4});
});

// HELPERS

function makePathOsAgnostic(path_) {
  return path_.replace(/.:/, '').replace(/\\/g, '/');
}
