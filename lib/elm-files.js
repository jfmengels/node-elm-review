const path = require('path');
const util = require('util');
const fs = require('fs-extra');
const glob = require('glob');

const defaultGlob = '**/*.elm';
const ignore = ['**/elm-stuff/**', '**/node_modules/**', 'lintingDir/**'];

const fsReadFile = util.promisify(fs.readFile);
const fsWriteFile = util.promisify(fs.writeFile);

function flatMap(array, fn) {
  return array.reduce((res, item) => res.concat(fn(item)), []);
}

function getFiles(filename) {
  if (!fs.existsSync(filename)) {
    return [];
  }

  if (fs.lstatSync(filename).isDirectory()) {
    return flatMap(
      glob.sync('/' + defaultGlob, {
        root: filename,
        nocase: true,
        ignore: ['/**/elm-stuff/**', '/**/node_modules/**'],
        nodir: true
      }),
      resolveFilePath
    );
  }

  return [filename];
}

// Recursively search directories for *.elm files, excluding elm-stuff/
function resolveFilePath(filename) {
  // Exclude everything having anything to do with elm-stuff
  return getFiles(filename).filter(
    candidate => !candidate.split(path.sep).includes('elm-stuff')
  );
}

function getElmFiles(filePathArgs) {
  const relativeElmFiles = getElmFilePaths(filePathArgs);
  return Promise.all(
    flatMap(relativeElmFiles, resolveFilePath).map(async filePath => {
      const source = await fsReadFile(filePath, 'utf8');
      return {path: filePath, source};
    })
  );
}

function getElmFilePaths(filePathArgs) {
  if (filePathArgs.length > 0) {
    return flatMap(filePathArgs, globify(undefined));
  }

  const root = path.join(path.resolve(process.cwd()), '..');
  return globify(root)('**/*.elm');
}

function globify(root) {
  return filename => {
    return glob.sync(filename, {
      root,
      nocase: true,
      ignore,
      nodir: false
    });
  };
}

function writeElmFiles(files) {
  return Promise.all([
    files.map(({path, source}) => fsWriteFile(path, source))
  ]);
}

module.exports = {
  defaultGlob,
  getElmFiles,
  writeElmFiles
};
