const FS = require('./fs-wrapper');
const OsHelpers = require('./os-helpers');

/**
 * @typedef { import("./types/options").Options } Options
 * @typedef { import("./types/path").Path } Path
 * @typedef { import("./types/content").ExtraFile } ExtraFile
 */

/**
 * Collect the extra files requested by the rules.
 * @param {{ files : { pattern: string, included: boolean }[], excludedFolders: string[] }[]} requests
 * @returns {Promise<ExtraFile[]>}
 */
async function collect(requests) {
  const {globby} = await import('globby');
  const files = await Promise.all(
    requests.map((request) => getFiles(globby, request))
  )
    .then((files) => files.reduce((acc, items) => acc.concat(items), []))
    .then(unique);

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

/** .
 * @param {any} globby
 * @param {{ files : { pattern: string, included: boolean }[], excludedFolders: string[] }} request
 * @returns {Promise<ExtraFile[]>}
 */
function getFiles(globby, request) {
  return globby(
    request.files.map(
      (file) =>
        (file.included ? '' : '!') + OsHelpers.makePathOsAgnostic(file.pattern)
    ),
    {
      ignore: request.excludedFolders,
      followSymbolicLinks: true,
      expandDirectories: false,
      caseSensitiveMatch: true,
      onlyFiles: true,
      dot: true,
      extglob: false
    }
  );
}

function unique(array) {
  return [...new Set(array)];
}

module.exports = {
  collect
};
