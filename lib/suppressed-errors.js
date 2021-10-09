const path = require('path');
const util = require('util');
const fs = require('fs-extra');
const glob = require('glob');

const globAsync = util.promisify(glob);
const fsRemove = util.promisify(fs.remove);
const fsMkdirp = util.promisify(fs.mkdirp);
const fsReadJson = util.promisify(fs.readJson);
const fsWriteFile = util.promisify(fs.writeFile);

module.exports = {
  read,
  write
};

// WRITE

async function write(options, result) {
  const suppressedErrorsFolder = options.suppressedErrorsFolder();
  await fsRemove(suppressedErrorsFolder);
  await fsMkdirp(suppressedErrorsFolder);

  const writePromises = result.map(({rule, suppressions}) =>
    fsWriteFile(
      path.join(suppressedErrorsFolder, `${rule}.json`),
      formatJson(suppressions),
      'utf-8'
    )
  );
  await Promise.all(writePromises);
}

function formatJson(suppressions) {
  return `{
    "version": 1,
    "suppressions": [
        ${suppressions.map(formatCountSuppression).join(',\n        ')}
    ]
}
`;
}

function formatCountSuppression(suppression) {
  return `{ "count": ${suppression.count}, "filePath": "${suppression.filePath}" }`;
}

// READ

async function read(options) {
  if (options.subcommand === 'suppress') {
    return [];
  }

  const files = await globAsync(
    `${options.suppressedErrorsFolder()}/**/*.json`,
    {
      nocase: true,
      ignore: ['**/elm-stuff/**'],
      nodir: false
    }
  );

  return Promise.all(
    files.map(async (filePath) => {
      return {
        rule: path.basename(filePath, '.json'),
        suppressions: (await fsReadJson(filePath)).suppressions
      };
    })
  );
}
