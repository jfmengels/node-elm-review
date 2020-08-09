const path = require('path');
const util = require('util');
const glob = require('glob');
const fs = require('fs-extra');
const chalk = require('chalk');
const cache = require('./cache');
const Debug = require('./debug');
const Anonymize = require('./anonymize');
const elmParser = require('./parse-elm');
const AppState = require('./state');
const ErrorMessage = require('./error-message');

const defaultGlob = '**/*.elm';

const globAsync = util.promisify(glob);
const fsReadFile = util.promisify(fs.readFile);
const fsStat = util.promisify(fs.stat);

function flatMap(array, fn) {
  return array.reduce((result, item) => result.concat(fn(item)), []);
}

async function getProjectFiles(options) {
  const relativePathToElmJson = options.elmJsonPath;

  const [elmJsonRaw, readme] = await Promise.all([
    readElmJson(options),
    getReadme(options, path.dirname(relativePathToElmJson))
  ]);
  AppState.readmeChanged(readme);

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
    throw new ErrorMessage.CustomError(
      'NO FILES FOUND',
      `I was expecting to find Elm files in all the paths that you passed, but I could
not find any in the following directories:
${emptyDirectories.map(({directory}) => `- ${directory}`).join('\n')}

When I can’t find files in some of the directories, I’m assuming that you
misconfigured the CLI’s arguments.`
    );
  }

  Debug.log('Reviewing the following files:');

  elmParser.prepareWorkers();
  const elmFilesToRead = [
    ...new Set(flatMap(filesInDirectories, (directory) => directory.files))
  ];
  const elmFiles = await Promise.all(
    elmFilesToRead.map((filePath) =>
      readFile(options, path.dirname(relativePathToElmJson), filePath)
    )
  );
  elmParser.terminateWorkers();

  return {
    elmJsonData: {
      path: 'elm.json',
      raw: elmJsonRaw,
      project: elmJson
    },
    readme,
    elmFiles,
    sourcesDirectories
  };
}

async function readElmJson(options) {
  try {
    return await fsReadFile(options.elmJsonPath, 'utf8');
  } catch (error) {
    if (error.code === 'ENOENT') {
      const details = options.elmJsonPathWasSpecified
        ? `Since you specified this path, I’m assuming that you misconfigured the CLI’s
arguments.`
        : `Are you running inside an Elm project? If not, you may want to create one or to
use the ${chalk.cyan('--elmjson <path-to-elm.json>')} flag.`;

      throw new ErrorMessage.CustomError(
        'ELM.JSON NOT FOUND',
        `I could not find the ${chalk.cyan(
          'elm.json'
        )} of the project to review. I was looking for it at:

    ${options.elmJsonPath}

${details}`
      );
    }

    throw error;
  }
}

async function readFile(options, relativePathToElmJson, filePath) {
  Debug.log(` - ${Anonymize.path(options, filePath)}`);
  const relativeFilePath = path.relative(relativePathToElmJson, filePath);

  const lastUpdatedTime = options.watch
    ? await fsReadLatestUpdatedTime(relativeFilePath)
    : null;

  const cachedFile = options.watch
    ? AppState.getFileFromMemoryCache(relativeFilePath)
    : null;

  // Check if we still have the file in memory
  if (cachedFile && cachedFile.lastUpdatedTime >= lastUpdatedTime) {
    return cachedFile;
  }

  const source = await fsReadFile(filePath, 'utf8').catch((error) => {
    throw new ErrorMessage.CustomError(
      'UNEXPECTED ERROR WHEN READING THE FILE',
      `I could not read the following file: ${relativeFilePath}\n\nOriginal error message: ${error.message}`
    );
  });
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

async function getReadme(options, directoryContainingElmJson) {
  return fsReadFile(options.readmePath, 'utf8')
    .then((content) => ({
      path: path.relative(directoryContainingElmJson, options.readmePath),
      content
    }))
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
  const ignore = ['**/elm-stuff/**'];

  if (path_.endsWith('.elm')) {
    // For finding files when `directory` is a direct Elm file, like "src/File.elm"
    return {
      files: await globAsync(path_, {
        nocase: true,
        ignore,
        nodir: true
      }),
      directory
    };
  }

  // For finding files when `directory` is a directory, like "src/"
  return {
    files: await globAsync(`${path_}/**/*.elm`, {
      nocase: true,
      ignore,
      nodir: false
    }),
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
