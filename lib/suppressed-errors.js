const path = require('path');
const childProcess = require('child_process');
const {glob} = require('glob');
const chalk = require('chalk');
const FS = require('./fs-wrapper');
const OsHelpers = require('./os-helpers');
const ErrorMessage = require('./error-message');
const exit = require('../vendor/exit');

/**
 * @typedef { import("./types/options").Options } Options
 * @typedef { import("./types/path").Path } Path
 * @typedef { import("./types/suppressed").Suppression } Suppression
 * @typedef { import("./types/suppressed").SuppressedErrorsFile } SuppressedErrorsFile
 */

module.exports = {
  read,
  write,
  checkForUncommittedSuppressions
};

// WRITE

const orange = chalk.keyword('orange');

/**
 * @param {Options} options
 * @param {Array<SuppressedErrorsFile>} suppressionFiles
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
        return FS.writeFile(filePath, newContents).catch((error) => {
          const relativeFolderPath =
            path.relative(process.cwd(), options.suppressedErrorsFolder()) +
            '/';
          const relativeFilePath = path.relative(process.cwd(), filePath);
          throw new ErrorMessage.CustomError(
            'FAILED TO UPDATE SUPPRESSION FILE',
            // prettier-ignore
            `I tried updating the suppression file in the ${orange(relativeFolderPath)} folder, but failed to write to ${orange(relativeFilePath)}.

Please check that ${chalk.greenBright('elm-review')} has write permissions to that file and folder. In case it helps, here's the error I encountered:

  ${error.toString()}`,
            filePath
          );
        });
      }

      return null;
    }

    if (deleteAllRules) {
      return null;
    }

    return FS.remove(filePath);
  });
  await Promise.all(writePromises);
}

/**
 * @param {Array<Suppression>} suppressions
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

  return a.filePath.localeCompare(b.filePath);
}

/**
 * @param {Suppression} suppression
 * @returns {string}
 */
function formatCountSuppression(suppression) {
  return `{ "count": ${suppression.count}, "filePath": "${suppression.filePath}" }`;
}

// READ

/**
 * @param {Options} options
 * @returns {Promise<Array<SuppressedErrorsFile>>}
 */
async function read(options) {
  if (options.subcommand === 'suppress') {
    return [];
  }

  const pattern = OsHelpers.makePathOsAgnostic(
    `${options.suppressedErrorsFolder()}/**/*.json`
  );
  let files = await glob(pattern, {
    nocase: true,
    ignore: ['**/elm-stuff/**'],
    nodir: false
  });

  if (options.rulesFilter) {
    const {rulesFilter} = options;
    files = files.filter((/** @type {Path} */ filePath) =>
      rulesFilter.includes(path.basename(filePath, '.json'))
    );
  }

  return Promise.all(
    files.map(async (/** @type {Path} */ filePath) => {
      /** @type {{version: number, suppressions: Suppression[]}} */
      const entry = await FS.readJsonFile(filePath);
      if (entry.version !== 1) {
        throw new ErrorMessage.CustomError(
          // prettier-ignore
          'UNKNOWN VERSION FOR SUPPRESSION FILE',
          // prettier-ignore
          `I was trying to read ${chalk.keyword('orange')(filePath)} but the version of that file is ${chalk.red(`"${entry.version}"`)} whereas I only support version ${chalk.yellowBright(`"1"`)}.

Try updating ${chalk.greenBright('elm-review')} to a version that supports this version of suppression files.`
        );
      }

      return {
        rule: path.basename(filePath, '.json'),
        suppressions: entry.suppressions
      };
    })
  );
}

// CHECK FOR UNCOMMITTED CHANGES

/**
 * @param {Options} options
 */
function checkForUncommittedSuppressions(options) {
  const pathToSuppressedFolder = path.relative(
    process.cwd(),
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
