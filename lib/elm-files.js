const path = require('path');
const util = require('util');
const fs = require('fs-extra');
const glob = require('glob');
const chalk = require('chalk');
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

async function getProjectFiles(args, projectToReview) {
  const elmJsonPath = path.join(projectToReview, 'elm.json');
  const elmJson = fs.readJsonSync(elmJsonPath);

  if (args.debug) {
    console.log('Reviewing the following files:');
  }

  const filesInDirectories = getFilesToReview(projectToReview, args._, elmJson);

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
misconfigured the CLI's arguments.`
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

function getProjectToReview(args) {
  const elmJsonPath = args.elmjson || findUp.sync('elm.json');
  if (!elmJsonPath) {
    throw new Error(
      /* eslint-disable prettier/prettier */
      errorMessage(
        'COULD NOT FIND ELM.JSON',
        `I was expecting to find an ${chalk.yellowBright('elm.json')} file in the current directory or one of its parents, but I did not find one.

If you wish to run elm-review from outside your project,
try re-running it with ${chalk.cyan('--elmjson <path-to-elm.json>')}.`
      )
      /* eslint-enable prettier/prettier */
    );
  }

  return path.dirname(elmJsonPath);
}

function getFilesToReview(
  projectToReview,
  directoriesFromCLIArguments,
  elmJson
) {
  if (directoriesFromCLIArguments.length !== 0) {
    return directoriesFromCLIArguments
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
      (directory.startsWith('C:')
        ? directory.slice(2).replace(/\\/g, '/')
        : directory) + '/**/*.elm',
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
  getProjectFiles,
  getProjectToReview
};
