/**
 * @import {Options} from './types/options';
 * @import {Path} from './types/path';
 * @import {Suppression, SuppressedErrorsFile} from './types/suppressed';
 */
const childProcess = require('node:child_process');
const path = require('node:path');
const chalk = require('chalk');
const {glob} = require('tinyglobby');
const exit = require('../vendor/exit');
const ErrorMessage = require('./error-message');
const FS = require('./fs-wrapper');
const {intoError} = require('./utils');
const PathHelpers = require('./path-helpers');

// WRITE

const orange = chalk.keyword('orange');

/**
 * @param {Options} options
 * @param {SuppressedErrorsFile[]} suppressionFiles
 * @returns {Promise<void>}
 */
async function write(options, suppressionFiles) {
  const requestedSuppress = options.subcommand === 'suppress';
  if (options.template && !requestedSuppress) {
    return;
  }

  const deleteAllRules = requestedSuppress && options.rulesFilter === null;
  const suppressedErrorsFolder = options.suppressedErrorsFolder();
  if (deleteAllRules) {
    await FS.remove(suppressedErrorsFolder);
  }

  await FS.mkdirp(suppressedErrorsFolder).catch((error) => {
    if (error.code === 'EEXIST') return;
    throw error;
  });

  const writePromises = suppressionFiles.map(async ({rule, suppressions}) => {
    const filePath = path.join(suppressedErrorsFolder, `${rule}.json`);
    if (suppressions.length > 0) {
      const newContents = formatJson(suppressions);

      const previousContents = await FS.readFile(filePath).catch(() => '');
      if (previousContents !== newContents) {
        try {
          await FS.writeFile(filePath, newContents);
          return;
        } catch (err) {
          const error = intoError(err);

          const relativeFolderPath =
            path.relative(options.cwd, options.suppressedErrorsFolder()) + '/';
          const relativeFilePath = path.relative(options.cwd, filePath);
          throw new ErrorMessage.CustomError(
            'FAILED TO UPDATE SUPPRESSION FILE',
            // prettier-ignore
            `I tried updating the suppression file in the ${orange(relativeFolderPath)} folder, but failed to write to ${orange(relativeFilePath)}.

Please check that ${chalk.greenBright('elm-review')} has write permissions to that file and folder. In case it helps, here's the error I encountered:

  ${error.toString()}`,
            filePath
          );
        }
      }

      return null;
    }

    if (deleteAllRules) {
      return null;
    }

    await FS.remove(filePath);
  });
  await Promise.all(writePromises);
}

/**
 * @param {Suppression[]} suppressions
 * @returns {string}
 */
function formatJson(suppressions) {
  const formattedSuppressions = suppressions
    .sort(suppressionSorting)
    .map(formatCountSuppression)
    .join(',\n    ');

  return `{
  "version": 1,
  "automatically created by": "elm-review suppress",
  "learn more": "elm-review suppress --help",
  "suppressions": [
    ${formattedSuppressions}
  ]
}
`;
}

/**
 * @param {Suppression} a
 * @param {Suppression} b
 * @returns {number}
 */
function suppressionSorting(a, b) {
  const tallyDifference = b.count - a.count;
  if (tallyDifference !== 0) {
    return tallyDifference;
  }

  return a.filePath.localeCompare(b.filePath, 'en');
}

/**
 * @param {Suppression} suppression
 * @returns {string}
 */
function formatCountSuppression(suppression) {
  // Normalize path to use forward slashes for cross-platform consistency
  const normalizedPath = PathHelpers.toUnixPath(suppression.filePath);
  return `{ "count": ${suppression.count}, "filePath": "${normalizedPath}" }`;
}

// READ

/**
 * @param {Options} options
 * @returns {Promise<SuppressedErrorsFile[]>}
 */
async function read(options) {
  if (options.subcommand === 'suppress') {
    return [];
  }

  let files = await glob('**/*.json', {
    caseSensitiveMatch: false,
    ignore: ['**/elm-stuff/**'],
    cwd: options.suppressedErrorsFolder(),
    absolute: true
  });

  if (options.rulesFilter) {
    const {rulesFilter} = options;
    files = files.filter((/** @type {Path} */ filePath) =>
      rulesFilter.includes(path.basename(filePath, '.json'))
    );
  }

  return await Promise.all(
    files.map(async (/** @type {Path} */ filePath) => {
      const entry =
        /** @type {{version: number, suppressions: Suppression[]}} */ (
          await FS.readJsonFile(filePath)
        );
      if (entry.version !== 1) {
        throw new ErrorMessage.CustomError(
          // prettier-ignore
          'UNKNOWN VERSION FOR SUPPRESSION FILE',
          // prettier-ignore
          `I was trying to read ${chalk.keyword('orange')(filePath)} but the version of that file is ${chalk.red(`"${entry.version}"`)} whereas I only support version ${chalk.yellowBright(`"1"`)}.

Try updating ${chalk.greenBright('elm-review')} to a version that supports this version of suppression files.`
        );
      }

      // Normalize file paths in suppressions for cross-platform consistency
      const normalizedSuppressions = entry.suppressions.map(
        (/** @type {Suppression} */ suppression) => ({
          ...suppression,
          filePath: PathHelpers.toUnixPath(suppression.filePath)
        })
      );

      return {
        rule: path.basename(filePath, '.json'),
        suppressions: normalizedSuppressions
      };
    })
  );
}

// CHECK FOR UNCOMMITTED CHANGES

/**
 * @param {Options} options
 * @returns {void | never}
 */
function checkForUncommittedSuppressions(options) {
  const pathToSuppressedFolder = path.relative(
    options.cwd,
    options.suppressedErrorsFolder()
  );

  const result = childProcess.execSync(
    `git status --short -- ${pathToSuppressedFolder}`
  );

  if (result.toString()) {
    console.log(
      // prettier-ignore
      `You have uncommitted changes in ${chalk.keyword('orange')(pathToSuppressedFolder)}.
However, all tests have passed, so you don't need to run tests again after committing these changes.`
    );

    exit(1);
  }
}

module.exports = {
  read,
  write,
  checkForUncommittedSuppressions
};
