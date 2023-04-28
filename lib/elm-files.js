const fs = require('fs');
const path = require('path');
const util = require('util');
const glob = require('glob');
const chalk = require('chalk');
const Hash = require('./hash');
const Debug = require('./debug');
const FS = require('./fs-wrapper');
const Benchmark = require('./benchmark');
const Anonymize = require('./anonymize');
const elmParser = require('./parse-elm');
const AppState = require('./state');
const OsHelpers = require('./os-helpers');
const ErrorMessage = require('./error-message');
const Cache = require('./cache');

/**
 * @typedef { import("./types/options").Options } Options
 * @typedef { import("./types/path").Path } Path
 * @typedef { import("./types/content").ElmFile } ElmFile
 * @typedef { import("./types/content").Readme } Readme
 * @typedef { import("./types/content").ElmJsonData } ElmJsonData
 */

const defaultGlob = '**/*.elm$';

const globAsync = util.promisify(glob);
const fsStat = util.promisify(fs.stat);

function flatMap(array, fn) {
  return array.reduce((result, item) => result.concat(fn(item)), []);
}

/**
 * @typedef {Object} ProjectFiles
 * @property {ElmJsonData} elmJsonData
 * @property {Readme | null} readme
 * @property {ElmFile[]} elmFiles
 * @property {Path[]} sourceDirectories
 */

/**
 * Get all files from the project.
 * @param {Options} options
 * @param {string} elmSyntaxVersion
 * @returns {Promise<ProjectFiles>}
 */
async function getProjectFiles(options, elmSyntaxVersion) {
  Benchmark.start(options, 'get project files');
  const relativePathToElmJson = options.elmJsonPath;

  const [elmJsonRaw, readme] = await Promise.all([
    readElmJson(options),
    getReadme(options, path.dirname(relativePathToElmJson))
  ]);
  AppState.readmeChanged(readme);

  const elmJson = JSON.parse(elmJsonRaw);
  const {isFromCliArguments, sourceDirectories} = getSourceDirectories(
    options,
    elmJson
  );

  const filesInDirectories = await Promise.all(
    sourceDirectories.map((dir) => findFiles(isFromCliArguments, dir))
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

  Debug.log(`Parsing using stil4m/elm-syntax v${elmSyntaxVersion}`);
  Debug.log('Reviewing the following files:');

  Benchmark.start(options, 'parse/fetch parsed files');
  const elmParserPath = options.elmParserPath(elmSyntaxVersion);
  elmParser.prepareWorkers();
  const elmFilesToRead = [
    ...new Set(flatMap(filesInDirectories, (directory) => directory.files))
  ];
  const elmFiles = await Promise.all(
    elmFilesToRead.map((filePath) =>
      readFile(
        options,
        elmParserPath,
        path.dirname(relativePathToElmJson),
        filePath
      )
    )
  );
  elmParser.terminateWorkers();
  Benchmark.end(options, 'parse/fetch parsed files');
  Benchmark.end(options, 'get project files');

  return {
    elmJsonData: {
      path: 'elm.json',
      raw: elmJsonRaw,
      project: elmJson
    },
    readme,
    elmFiles,
    sourceDirectories
  };
}

async function readElmJson(options) {
  try {
    return await FS.readFile(options.elmJsonPath);
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

async function readFile(
  options,
  elmParserPath,
  relativePathToElmJson,
  filePath
) {
  Debug.log(` - ${Anonymize.path(options, filePath)}`);
  const relativeFilePath = path.relative(relativePathToElmJson, filePath);

  const lastUpdatedTime = options.watch
    ? await fsReadLatestUpdatedTime(relativeFilePath)
    : null;

  const cachedFile = options.watch
    ? AppState.getFileFromMemoryCache(relativeFilePath)
    : null;

  // Check if we still have the file in memory
  if (
    lastUpdatedTime &&
    cachedFile &&
    cachedFile.lastUpdatedTime &&
    cachedFile.lastUpdatedTime >= lastUpdatedTime
  ) {
    return cachedFile;
  }

  const source = await FS.readFile(filePath).catch((error) => {
    throw new ErrorMessage.CustomError(
      'UNEXPECTED ERROR WHEN READING THE FILE',
      `I could not read the following file: ${relativeFilePath}\n\nOriginal error message: ${error.message}`
    );
  });
  const cachedAst =
    cachedFile && cachedFile.source === source ? cachedFile.ast : null;

  return {
    path: OsHelpers.makePathOsAgnostic(relativeFilePath),
    source,
    lastUpdatedTime,
    ast: cachedAst || (await readAst(options, elmParserPath, source))
  };
}

function readAst(options, elmParserPath, source) {
  const hash = Hash.hash(source);
  return Cache.getOrCompute(options.fileCachePath(), hash, () =>
    elmParser.parse(elmParserPath, source)
  );
}

async function getReadme(options, directoryContainingElmJson) {
  return FS.readFile(options.readmePath)
    .then((content) => ({
      path: path.relative(directoryContainingElmJson, options.readmePath),
      content
    }))
    .catch(() => null);
}

function getSourceDirectories(options, elmJson) {
  if (options.directoriesToAnalyze.length !== 0) {
    return {
      isFromCliArguments: true,
      sourceDirectories: options.directoriesToAnalyze.map((directory) =>
        path.resolve(process.cwd(), directory)
      )
    };
  }

  return {
    isFromCliArguments: false,
    sourceDirectories: standardSourceDirectories(options, elmJson)
  };
}

function standardSourceDirectories(options, elmJson) {
  const projectToReview = options.projectToReview();

  if (elmJson.type === 'package') {
    return [
      path.join(projectToReview, 'src'),
      path.join(projectToReview, 'tests')
    ];
  }

  // If the project is an "application"

  return flatMap(elmJson['source-directories'], (directory) => [
    path.join(projectToReview, directory),
    path.resolve(projectToReview, directory, '../tests/')
  ]).concat(path.join(projectToReview, 'tests'));
}

function findFiles(isFromCliArguments, directory) {
  // Replacing parts to make the globbing work on Windows
  const path_ = directory.replace(/.:/, '').replace(/\\/g, '/');

  if (isFromCliArguments) {
    return findForCliArguments(directory, path_);
  }

  return findFromFolder(directory, path_);
}

const globIgnore = ['**/elm-stuff/**'];

async function findForCliArguments(directory, path_) {
  try {
    const stat = await fsStat(directory);
    if (stat.isFile()) {
      // For finding files when `directory` is a direct Elm file, like "src/File.elm"
      return {
        files: await globAsync(path_, {
          nocase: true,
          ignore: globIgnore,
          nodir: true
        }),
        directory
      };
    }

    // For finding files when `directory` is a directory, like "src/" or "tests"
    return findFromFolder(directory, path_);
  } catch (error) {
    if (error.code === 'ENOENT') {
      // File/folder was not found. Return an empty array, which will give a nice
      // error report in the parent function
      return {
        files: [],
        directory
      };
    }

    throw error;
  }
}

async function findFromFolder(directory, path_) {
  return {
    files: await globAsync(`${path_}/**/*.elm`, {
      nocase: true,
      ignore: globIgnore,
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
