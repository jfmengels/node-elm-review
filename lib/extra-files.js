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
  const {globby} = await import('globby');
  const files = await globby(
    requestedFiles.map((file) => OsHelpers.makePathOsAgnostic(file)),
    {
      followSymbolicLinks: true,
      expandDirectories: false,
      caseSensitiveMatch: true,
      onlyFiles: true,
      dot: true,
      extglob: false
    }
  );
  console.log(files.sort())

  return Promise.all(
    files.sort().map(async (filePath) => {
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
