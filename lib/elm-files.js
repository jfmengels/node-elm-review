const path = require('path');
const util = require('util');
const fs = require('fs-extra');
const glob = require('glob');
const cache = require('./cache');
const elmParser = require('./parse-elm');
const errorMessage = require('./error-message');

const defaultGlob = '**/*.elm';
const ignore = ['**/elm-stuff/**', '**/node_modules/**'];

const globAsync = util.promisify(glob);
const fsReadFile = util.promisify(fs.readFile);

function flatMap(array, fn) {
  return array.reduce((result, item) => result.concat(fn(item)), []);
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
  const [elmJsonRaw, readme] = await Promise.all([
    fsReadFile(options.elmJsonPath, 'utf8'),
    getReadme(options)
  ]);
  const elmJson = JSON.parse(elmJsonRaw);
  const sourcesDirectories = getSourceDirectories(options, elmJson);

  const filesInDirectories = await Promise.all(
    sourcesDirectories.map(findFiles)
  );

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

When I can’t find files in some of the directories, I’m assuming that you
misconfigured the CLI’s arguments.`
      )
    );
  }

  if (options.debug) {
    console.log('Reviewing the following files:');
  }

  elmParser.prepareWorkers();
  const elmFiles = await Promise.all(
    [...new Set(flatMap(filesInDirectories, directory => directory.files))].map(
      async filePath => {
        if (options.debug) {
          console.log(` - ${filePath}`);
        }

        const source = await fsReadFile(filePath, 'utf8');
        const relativeFilePath = path.relative(process.cwd(), filePath);
        return {
          path: relativeFilePath,
          source,
          ast: await cache
            .readAstFromCache(options, source)
            .then(async result => {
              if (result) {
                return result;
              }

              const ast = await elmParser.parse(source);
              if (ast !== null) {
                cache.cacheFile(options, {source, ast});
              }

              return ast;
            })
        };
      }
    )
  );

  return {
    elmJsonData: {
      path: options.elmJsonPath,
      raw: elmJsonRaw,
      project: elmJson
    },
    readme,
    elmFiles,
    sourcesDirectories
  };
}

async function getReadme(options) {
  const path = options.readmePath;
  return fsReadFile(path, 'utf8')
    .then(content => ({path, content}))
    .catch(() => null);
}

function getSourceDirectories(options, elmJson) {
  const projectToReview = options.projectToReview();
  const {directoriesToAnalyze} = options;

  if (directoriesToAnalyze.length !== 0) {
    return directoriesToAnalyze.map(directory =>
      path.join(process.cwd(), directory)
    );
  }

  if (elmJson.type === 'package') {
    return [
      path.join(projectToReview, 'src'),
      path.join(projectToReview, 'tests')
    ];
  }

  // If the project is an "application"

  return elmJson['source-directories']
    .map(directory => path.join(projectToReview, directory))
    .concat(path.join(projectToReview, 'tests'));
}

async function findFiles(directory) {
  // Replacing parts to make the globbing work on Windows
  const path_ = directory.replace(/.:/, '').replace(/\\/g, '/');
  return {
    files: await Promise.all([
      globAsync(path_, {
        nocase: true,
        ignore,
        nodir: true
      }),
      globAsync(`${path_}/**/*.elm`, {
        nocase: true,
        ignore,
        nodir: false
      })
    ]).then(([a, b]) => a.concat(b)),
    directory
  };
}

module.exports = {
  defaultGlob,
  getProjectFiles
};
