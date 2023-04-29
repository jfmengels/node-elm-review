const path = require('path');
const util = require('util');
const childProcess = require('child_process');
const glob = require('glob');
const chalk = require('chalk');
const FS = require('./fs-wrapper');
const OsHelpers = require('./os-helpers');
const ErrorMessage = require('./error-message');

const globAsync = util.promisify(glob);

module.exports = {
  read,
  write,
  checkForUncommittedSuppressions
};

// WRITE

async function write(options, items) {
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

  const writePromises = items.map(async ({rule, suppressions}) => {
    const filePath = path.join(suppressedErrorsFolder, `${rule}.json`);
    if (suppressions.length > 0) {
      const newContents = formatJson(suppressions);

      const previousContents = await FS.readFile(filePath).catch(() => '');
      if (previousContents !== newContents) {
        return FS.writeFile(filePath, newContents);
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

function suppressionSorting(a, b) {
  const tallyDifference = b.count - a.count;
  if (tallyDifference !== 0) {
    return tallyDifference;
  }

  return a.filePath.localeCompare(b.filePath);
}

function formatCountSuppression(suppression) {
  return `{ "count": ${suppression.count}, "filePath": "${suppression.filePath}" }`;
}

// READ

async function read(options) {
  if (options.subcommand === 'suppress') {
    return [];
  }

  const glob = OsHelpers.makePathOsAgnostic(
    `${options.suppressedErrorsFolder()}/**/*.json`
  );
  let files = await globAsync(glob, {
    nocase: true,
    ignore: ['**/elm-stuff/**'],
    nodir: false
  });

  if (options.rulesFilter) {
    files = files.filter((filePath) =>
      options.rulesFilter.includes(path.basename(filePath, '.json'))
    );
  }

  return Promise.all(
    files.map(async (filePath) => {
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

    process.exit(1);
  }
}
