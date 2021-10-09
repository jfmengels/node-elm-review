const path = require('path');
const util = require('util');
const fs = require('fs-extra');

const fsMkdirp = util.promisify(fs.mkdirp);
const fsWriteFile = util.promisify(fs.writeFile);

module.exports = {
  write
};

async function write(options, result) {
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
