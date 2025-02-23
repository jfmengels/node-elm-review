/**
 * @import {Ast, ElmFile, ElmJson, ProjectFiles, Readme, Source, SourceDirectories} from './types/content';
 * @import {ReviewOptions} from './types/options';
 * @import {Path} from './types/path';
 */
const path = require('pathe');
const chalk = require('chalk');
const {glob} = require('tinyglobby');
const Anonymize = require('./anonymize');
const Benchmark = require('./benchmark');
const Cache = require('./cache');
const Debug = require('./debug');
const ErrorMessage = require('./error-message');
const FS = require('./fs-wrapper');
const Hash = require('./hash');
const {unique} = require('./utils');
const elmParser = require('./parse-elm');
const AppState = require('./state');

const defaultGlob = '**/*.elm$';

/**
 * Get all files from the project.
 *
 * @param {ReviewOptions} options
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

  /** @type {ElmJson} */
  const elmJson = JSON.parse(elmJsonRaw);
  const {isFromCliArguments, sourceDirectories} = getSourceDirectories(
    options,
    elmJson
  );

  const filesInDirectories = await Promise.all(
    sourceDirectories.map(
      async (dir) => await findFiles(isFromCliArguments, dir)
    )
  );

  const emptyDirectories = filesInDirectories.filter(
    ({files}) => files.length === 0
  );
  const elmFilesToRead = unique(
    filesInDirectories.flatMap((directory) => directory.files)
  );
  // TODO(@jfmengels): Have a different message depending on how directories were chosen (CLI directories, application, package).
  if (options.directoriesToAnalyze.length > 0 && emptyDirectories.length > 0) {
    throw new ErrorMessage.CustomError(
      'NO FILES FOUND',
      `I was expecting to find Elm files in all the paths that you passed, but I could
not find any in the following directories:
${emptyDirectories.map(({directory}) => `- ${directory}`).join('\n')}

When I can’t find files in some of the directories, I’m assuming that you
misconfigured the CLI’s arguments.`
    );
  } else if (elmFilesToRead.length === 0) {
    throw new ErrorMessage.CustomError(
      'NO FILES FOUND',
      `I could not find any files in this project. I looked in these folders:
${sourceDirectories.map((directory) => `- ${directory}`).join('\n')}`
    );
  }

  Debug.log(
    `Parsing using stil4m/elm-syntax v${elmSyntaxVersion}`,
    options.debug
  );
  Debug.log('Reviewing the following files:', options.debug);

  Benchmark.start(options, 'parse/fetch parsed files');
  const elmParserPath = options.elmParserPath(elmSyntaxVersion);
  elmParser.prepareWorkers();
  const elmFiles = await Promise.all(
    elmFilesToRead.map(
      async (filePath) =>
        await readFile(
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

/**
 * @param {ReviewOptions} options
 * @returns {Promise<string>}
 */
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

/**
 * Read an Elm file and parse it and cache the result.
 *
 * @param {ReviewOptions} options
 * @param {Path} elmParserPath
 * @param {Path} relativePathToElmJson
 * @param {Path} filePath
 * @returns {Promise<ElmFile>}
 */
async function readFile(
  options,
  elmParserPath,
  relativePathToElmJson,
  filePath
) {
  Debug.log(` - ${Anonymize.path(options, filePath)}`, options.debug);
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
    cachedFile?.lastUpdatedTime &&
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
    path: relativeFilePath,
    source,
    lastUpdatedTime,
    ast: cachedAst ?? (await readAst(options, elmParserPath, source))
  };
}

/**
 * Parse an Elm file and cache the result.
 *
 * @param {ReviewOptions} options
 * @param {Path} elmParserPath
 * @param {Source} source
 * @returns {Promise<Ast | null>}
 */
async function readAst(options, elmParserPath, source) {
  const hash = Hash.hash(source);
  return await Cache.getOrCompute(
    options.fileCachePath(),
    hash,
    async () => await elmParser.parse(elmParserPath, source)
  );
}

/**
 * Get the README.md file.
 *
 * @param {ReviewOptions} options
 * @param {Path} directoryContainingElmJson
 * @returns {Promise<Readme | null>}
 */
async function getReadme(options, directoryContainingElmJson) {
  try {
    const content = await FS.readFile(options.readmePath);
    return {
      path: path.relative(directoryContainingElmJson, options.readmePath),
      content
    };
  } catch {
    return null;
  }
}

/**
 * Get the source-directories from the `elm.json` file.
 *
 * @param {ReviewOptions} options
 * @param {ElmJson} elmJson
 * @returns {{isFromCliArguments: boolean, sourceDirectories: SourceDirectories}}
 */
function getSourceDirectories(options, elmJson) {
  if (options.directoriesToAnalyze.length > 0) {
    return {
      isFromCliArguments: true,
      sourceDirectories: unique(
        options.directoriesToAnalyze.map((directory) =>
          path.resolve(options.cwd, directory)
        )
      )
    };
  }

  return {
    isFromCliArguments: false,
    sourceDirectories: standardSourceDirectories(options, elmJson)
  };
}

/**
 * Get the source-directories from the `elm.json` file.
 *
 * @param {ReviewOptions} options
 * @param {ElmJson} elmJson
 * @returns {SourceDirectories}
 */
function standardSourceDirectories(options, elmJson) {
  const projectToReview = options.projectToReview();

  if (elmJson.type === 'package') {
    return [
      path.join(projectToReview, 'src'),
      path.join(projectToReview, 'tests')
    ];
  }

  // If the project is an "application"
  const sourceDirectories = elmJson['source-directories'] ?? [];
  if (sourceDirectories.length === 0) {
    throw new ErrorMessage.CustomError(
      'EMPTY SOURCE-DIRECTORIES',
      `The \`source-directories\` in your \`elm.json\` is empty. I need it to contain
at least 1 directory in order to find files to analyze. The Elm compiler will
need that as well anyway.`
    );
  }

  return unique([
    ...sourceDirectories.flatMap((/** @type {Path} */ directory) => [
      path.join(projectToReview, directory),
      path.resolve(projectToReview, directory, '../tests/')
    ]),
    path.join(projectToReview, 'tests')
  ]);
}

/**
 * Find Elm files in directory
 *
 * @param {boolean} isFromCliArguments
 * @param {Path} directory
 * @returns {Promise<{files: Path[], directory: Path}>}
 */
async function findFiles(isFromCliArguments, directory) {
  if (isFromCliArguments) {
    return await findForCliArguments(directory);
  }

  return await findFromFolder(directory);
}

/**
 * Find Elm files in directory
 *
 * @param {Path} directory
 * @returns {Promise<{files: Path[], directory: Path}>}
 */
async function findForCliArguments(directory) {
  try {
    const stat = await FS.stat(directory);
    if (stat.isFile()) {
      // For finding files when `directory` is a direct Elm file, like "src/File.elm"
      return {
        files: await glob(path.basename(directory), {
          caseSensitiveMatch: false,
          ignore: [`**/elm-stuff/**`],
          cwd: path.dirname(directory),
          absolute: true
        }),
        directory
      };
    }

    // For finding files when `directory` is a directory, like "src/" or "tests"
    return await findFromFolder(directory);
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

/**
 * Find Elm files in directory
 *
 * @param {Path} directory
 * @returns {Promise<{files: Path[], directory: Path}>}
 */
async function findFromFolder(directory) {
  return {
    files: await glob('**/*.elm', {
      caseSensitiveMatch: false,
      ignore: ['**/elm-stuff/**'],
      cwd: directory,
      absolute: true
    }),
    directory
  };
}

/**
 * Get the time at which the file was last modified.
 *
 * @param {Path} filePath
 * @returns {Promise<Date>}
 */
async function fsReadLatestUpdatedTime(filePath) {
  const fileStat = await FS.stat(filePath);

  return fileStat.mtime;
}

module.exports = {
  defaultGlob,
  getProjectFiles,
  readElmJson
};
