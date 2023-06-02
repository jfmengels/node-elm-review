const {glob} = require('glob');
const FS = require('./fs-wrapper');
const OsHelpers = require('./os-helpers');

/**
 * @typedef { import("./types/options").Options } Options
 * @typedef { import("./types/path").Path } Path
 * @typedef { import("./types/content").ExtraFile } ExtraFile
 */

/**
 * Collect the extra files requested by the rules.
 * @param {Options} options
 * @param {Path[]} requestedFiles
 * @returns {Promise<ExtraFile[]>}
 */
async function collect(options, requestedFiles) {
  let files = await glob(
    requestedFiles.map((file) => OsHelpers.makePathOsAgnostic(file)),
    {
      nocase: true,
      ignore: ['**/elm-stuff/**'],
      nodir: false
    }
  );

  return Promise.all(
    files.map(async (filePath) => {
      const content = await FS.readFile(filePath);
      return {
        path: filePath,
        content: content
      };
    })
  );
}

module.exports = {
  collect
};
