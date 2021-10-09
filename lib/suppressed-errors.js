const path = require('path');
const util = require('util');
const fs = require('fs-extra');
const glob = require('glob');

const globAsync = util.promisify(glob);
const fsMkdirp = util.promisify(fs.mkdirp);
const fsReadJson = util.promisify(fs.readJson);
const fsWriteFile = util.promisify(fs.writeFile);

module.exports = {
  read,
  write
};

// WRITE

async function write(options, result) {
  await read(options);
  const suppressedErrorsFolder = options.suppressedErrorsFolder();
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
  const suppressedErrorsFolder = options.suppressedErrorsFolder();
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
