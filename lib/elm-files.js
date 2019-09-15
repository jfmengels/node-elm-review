const path = require('path');
const util = require('util');
const fs = require('fs-extra');
const glob = require('glob');
const findUp = require('find-up');
const errorMessage = require('./error-message');

const defaultGlob = '**/*.elm';
const ignore = ['**/elm-stuff/**', '**/node_modules/**'];

const fsReadFile = util.promisify(fs.readFile);

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

async function getProjectFiles(args, projectToLint) {
  const elmJsonPath = path.join(projectToLint, 'elm.json');
  const elmJson = fs.readJsonSync(elmJsonPath);

  if (args.debug) {
    console.log('Linting the following files:');
  }

  const filesInDirectories = getFilesToLint(projectToLint, args._, elmJson);

  const emptyDirectories = filesInDirectories.filter(
    ({files}) => files.length === 0
  );

  // TODO Have a different message depending on how directories were chosen (CLI directories, application, package)
  if (args._.length !== 0 && emptyDirectories.length !== 0) {
    throw new Error(
      errorMessage(
        'NO FILES FOUND',
        `I was expecting to find Elm files in all the paths that you passed, but I could
not find any in the following directories:
${emptyDirectories.map(({directory}) => `- ${directory}`).join('\n')}

When I can't find files in some of the directories, I'm assuming that you
misconfigured the CLI's arguments, and that you prefer to know rather than have
some files silently not be analyzed.`
      )
    );
  }

  const elmFiles = await Promise.all(
    [...new Set(flatMap(filesInDirectories, directory => directory.files))].map(
      async filePath => {
        if (args.debug) {
          console.log(` - ${filePath}`);
        }

        const source = await fsReadFile(filePath, 'utf8');
        return {
          path: path.relative(process.cwd(), filePath),
          source
        };
      }
    )
  );

  return {
    elmJson,
    elmFiles
  };
}

function getProjectToLint(args) {
  const elmJsonPath = args.elmjson || findUp.sync('elm.json');
  return path.dirname(elmJsonPath);
}

function getFilesToLint(projectToLint, directoriesFromCLIArguments, elmJson) {
  if (directoriesFromCLIArguments.length !== 0) {
    return directoriesFromCLIArguments
      .map(directory => path.join(process.cwd(), directory))
      .map(findFiles);
  }

  if (elmJson.type === 'package') {
    return [findFiles(path.join(projectToLint, 'src'))];
  }

  // If the application is an "application"

  return elmJson['source-directories']
    .map(directory => path.join(projectToLint, directory))
    .map(findFiles);
}

function findFiles(directory) {
  return {
    files: glob.sync(directory + '/**/*.elm', {
      nocase: true,
      ignore,
      nodir: false
    }),
    directory
  };
}

module.exports = {
  defaultGlob,
  getProjectFiles,
  getProjectToLint
};
