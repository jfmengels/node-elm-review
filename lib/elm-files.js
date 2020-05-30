const path = require('path');
const util = require('util');
const fs = require('fs-extra');
const glob = require('glob');
const cache = require('./cache');
const debug = require('./debug');
const elmParser = require('./parse-elm');
const appState = require('./state');
const errorMessage = require('./error-message');

const defaultGlob = '**/*.elm';
const ignore = ['**/elm-stuff/**', '**/node_modules/**'];

const globAsync = util.promisify(glob);
const fsReadFile = util.promisify(fs.readFile);
const fsStat = util.promisify(fs.stat);

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
    (candidate) => !candidate.split(path.sep).includes('elm-stuff')
  );
}

async function getProjectFiles(options) {
  const [elmJsonRaw, readme] = await Promise.all([
    fsReadFile(options.elmJsonPath, 'utf8'),
    getReadme(options)
  ]);
  appState.readmeChanged(readme);

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
    throw new errorMessage.CustomError(
      'NO FILES FOUND',
      `I was expecting to find Elm files in all the paths that you passed, but I could
not find any in the following directories:
${emptyDirectories.map(({directory}) => `- ${directory}`).join('\n')}

When I can’t find files in some of the directories, I’m assuming that you
misconfigured the CLI’s arguments.`
    );
  }

  debug('Reviewing the following files:');

  elmParser.prepareWorkers();
  const elmFilesToRead = [
    ...new Set(flatMap(filesInDirectories, (directory) => directory.files))
  ];
  const elmFiles = await Promise.all(
    elmFilesToRead.map((filePath) => readFile(options, filePath))
  );
  elmParser.terminateWorkers();

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

async function readFile(options, filePath) {
  debug(` - ${filePath}`);
  const relativeFilePath = path.relative(process.cwd(), filePath);

  const lastUpdatedTime = options.watch
    ? await fsReadLatestUpdatedTime(relativeFilePath)
    : null;

  const cachedFile = options.watch
    ? appState.getFileFromMemoryCache(relativeFilePath)
    : null;

  // Check if we still have the file in memory
  if (cachedFile && cachedFile.lastUpdatedTime >= lastUpdatedTime) {
    return cachedFile;
  }

  const source = await fsReadFile(relativeFilePath, 'utf8');
  const cachedAst =
    cachedFile && cachedFile.source === source ? cachedFile.ast : null;

  return {
    path: relativeFilePath,
    source,
    lastUpdatedTime,
    ast: cachedAst || (await readAst(options, source))
  };
}

function readAst(options, source) {
  return cache.readAstFromFSCache(options, source).then(async (result) => {
    if (result) {
      return result;
    }

    const ast = await elmParser.parse(source);
    if (ast !== null) {
      cache.cacheFile(options, {source, ast});
    }

    return ast;
  });
}

async function getReadme(options) {
  const path = options.readmePath;
  return fsReadFile(path, 'utf8')
    .then((content) => ({path, content}))
    .catch(() => null);
}

function getSourceDirectories(options, elmJson) {
  const projectToReview = options.projectToReview();
  const {directoriesToAnalyze} = options;

  if (directoriesToAnalyze.length !== 0) {
    return directoriesToAnalyze.map((directory) =>
      path.resolve(process.cwd(), directory)
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
    .map((directory) => path.join(projectToReview, directory))
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

function fsReadLatestUpdatedTime(filePath) {
  return fsStat(filePath).then((fileStat) => fileStat.mtime);
}

module.exports = {
  defaultGlob,
  getProjectFiles
};
