const path = require('path');
const util = require('util');
const fs = require('fs-extra');

const fsMkdirp = util.promisify(fs.mkdirp);
const fsReadJson = util.promisify(fs.readJson);
const fsWriteJson = util.promisify(fs.writeJson);

module.exports = {
  write
};

async function write(options, result) {
  const suppressedErrorsFolder = options.suppressedErrorsFolder();
  await fsMkdirp(suppressedErrorsFolder);

  const writePromises = result.map(({rule, suppressions}) =>
    fsWriteJson(
      path.join(suppressedErrorsFolder, `${rule}.json`),
      suppressions,
      {spaces: 4}
    )
  );
  await Promise.all(writePromises);
}
