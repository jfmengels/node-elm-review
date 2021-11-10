const path = require('path');
const util = require('util');
const childProcess = require('child_process');
const fs = require('fs-extra');
const glob = require('glob');
const chalk = require('chalk');

const globAsync = util.promisify(glob);
const fsRemove = util.promisify(fs.remove);
const fsMkdir = util.promisify(fs.mkdir);
const fsReadJson = util.promisify(fs.readJson);
const fsWriteFile = util.promisify(fs.writeFile);

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

  const deleteAllRules = requestedSuppress && options.rules === null;
  const suppressedErrorsFolder = options.suppressedErrorsFolder();
  // TODO Update only the files that have been changed.
  //      We need the list of those files from Elm's side
  if (deleteAllRules) {
    await fsRemove(suppressedErrorsFolder);
  }

  await fsMkdir(suppressedErrorsFolder).catch((error) => {
    if (error.code === 'EEXIST') return;
    throw error;
  });

  const writePromises = items.map(({rule, suppressions}) => {
    const filePath = path.join(suppressedErrorsFolder, `${rule}.json`);
    if (suppressions.length > 0) {
      return fsWriteFile(filePath, formatJson(suppressions), 'utf-8');
    }

    if (deleteAllRules) {
      return null;
    }

    return fsRemove(filePath);
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

  let files = await globAsync(`${options.suppressedErrorsFolder()}/**/*.json`, {
    nocase: true,
    ignore: ['**/elm-stuff/**'],
    nodir: false
  });

  if (options.rules) {
    files = files.filter((filePath) =>
      options.rules.includes(path.basename(filePath, '.json'))
    );
  }

  return Promise.all(
    files.map(async (filePath) => {
      return {
        rule: path.basename(filePath, '.json'),
        suppressions: (await fsReadJson(filePath)).suppressions
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
        `You have uncommitted changes in ${chalk.keyword('orange')(
          pathToSuppressedFolder
        )}.
However, all tests have passed, so you don't need to run tests again after committing these changes.`
      );
      // eslint-disable-next-line unicorn/no-process-exit
      process.exit(1);
  }
}
