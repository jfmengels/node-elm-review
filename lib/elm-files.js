const path = require('path');
const crypto = require('crypto');
const util = require('util');
const fs = require('fs-extra');
const glob = require('glob');
const errorMessage = require('./error-message');

const defaultGlob = '**/*.elm';
const ignore = ['**/elm-stuff/**', '**/node_modules/**'];

const fsReadFile = util.promisify(fs.readFile);
const fsReadJson = util.promisify(fs.readJson);

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

async function getProjectFiles(options) {
  const {elmJsonPath} = options;
  const elmJson = fs.readJsonSync(elmJsonPath);

  const filesInDirectories = getFilesToReview(options, elmJson);

  const emptyDirectories = filesInDirectories.filter(
    ({files}) => files.length === 0
  );

  // TODO Have a different message depending on how directories were chosen (CLI directories, application, package)
  if (
    options.directoriesToAnalyze.length !== 0 &&
    emptyDirectories.length !== 0
  ) {
    throw new Error(
      errorMessage(
        'NO FILES FOUND',
        `I was expecting to find Elm files in all the paths that you passed, but I could
not find any in the following directories:
${emptyDirectories.map(({directory}) => `- ${directory}`).join('\n')}

When I can't find files in some of the directories, I'm assuming that you
misconfigured the CLI's arguments.`
      )
    );
  }

  if (options.debug) {
    console.log('Reviewing the following files:');
  }

  const elmFiles = await Promise.all(
    [...new Set(flatMap(filesInDirectories, directory => directory.files))].map(
      async filePath => {
        if (options.debug) {
          console.log(` - ${filePath}`);
        }

        const source = await fsReadFile(filePath, 'utf8');
        const ast = await fsReadJson(
          path.join(options.fileCachePath(), `${hash(source)}.json`)
        ).catch(() => null);
        return {
          path: path.relative(process.cwd(), filePath),
          source,
          ast
        };
      }
    )
  );

  return {
    elmJson,
    elmFiles
  };
}

function hash(content) {
  return crypto
    .createHash('md5')
    .update(content)
    .digest('hex');
}

function getFilesToReview(options, elmJson) {
  const projectToReview = options.projectToReview();
  const {directoriesToAnalyze} = options;

  if (directoriesToAnalyze.length !== 0) {
    return directoriesToAnalyze
      .map(directory => path.join(process.cwd(), directory))
      .map(findFiles);
  }

  if (elmJson.type === 'package') {
    return [findFiles(path.join(projectToReview, 'src'))];
  }

  // If the application is an "application"

  return elmJson['source-directories']
    .map(directory => path.join(projectToReview, directory))
    .map(findFiles);
}

function findFiles(directory) {
  return {
    files: glob.sync(
      // Replacing parts to make the globbing work on Windows
      directory.replace(/.:/, '').replace(/\\/g, '/') + '/**/*.elm',
      {
        nocase: true,
        ignore,
        nodir: false
      }
    ),
    directory
  };
}

module.exports = {
  defaultGlob,
  getProjectFiles
};
