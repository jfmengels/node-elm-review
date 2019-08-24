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

async function getProjectFiles(args) {
  const projectToLint = getProjectToLint(args);
  const elmJsonPath = path.join(projectToLint, 'elm.json');
  const elmJson = fs.readJsonSync(elmJsonPath);

  if (args.debug) {
    console.log('Linting the following files:');
  }

  const elmFiles = await Promise.all(
    [...new Set(getFilesToLint(projectToLint, elmJson))].map(async filePath => {
      if (args.debug) {
        console.log(` - ${filePath}`);
      }

      const source = await fsReadFile(filePath, 'utf8');
      return {
        path: path.relative(process.cwd(), filePath),
        source
      };
    })
  );

  return {
    elmJson,
    elmFiles
  };
}

function getProjectToLint(args) {
  if (args.project) {
    return path.relative(
      process.cwd(),
      path.resolve(process.cwd(), args.project)
    );
  }

  return process.cwd();
}

function getFilesToLint(projectToLint, elmJson) {
  if (elmJson.type === 'package') {
    return glob.sync(path.resolve(projectToLint, 'src') + '/**/*.elm', {
      nocase: true,
      ignore,
      nodir: false
    });
  }

  return flatMap(elmJson['source-directories'], directory => {
    // TODO Performance: Call these globs in parallel
    return glob.sync(path.resolve(projectToLint, directory) + '/**/*.elm', {
      nocase: true,
      ignore,
      nodir: false
    });
  });
}

function writeElmFiles(files) {
  return Promise.all([
    files.map(({path, source}) => fsWriteFile(path, source))
  ]);
}

module.exports = {
  defaultGlob,
  getProjectFiles,
  writeElmFiles
};
