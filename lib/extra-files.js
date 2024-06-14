const FS = require('./fs-wrapper');
const OsHelpers = require('./os-helpers');

/**
 * @typedef { import("./types/options").Options } Options
 * @typedef { import("./types/path").Path } Path
 * @typedef { import("./types/content").NonElmFiles } NonElmFiles
 * @typedef { import("./types/content").ExtraFileRequest } ExtraFileRequest
 */

/**
 * Collect the extra files requested by the rules.
 * @param {ExtraFileRequest[]} requests
 * @returns {Promise<NonElmFiles>}
 */
async function collect(requests) {
  // eslint-disable-next-line @typescript-eslint/ban-ts-comment
  // @ts-ignore
  const {globby} = await import('globby');
  const files = await Promise.all(
    requests.map((request) => getFiles(globby, request))
  )
    .then((files) => files.reduce((acc, items) => acc.concat(items), []))
    .then(unique);

  const filesAndContents = await Promise.all(
    files.map(async (filePath) => {
      const content = await FS.readFile(filePath);
      return {
        path: filePath,
        content: content
      };
    })
  );
  return filesAndContents.reduce((dict, {path, content}) => {
    dict[path] = content;
    return dict;
  }, {});
}

/** .
 * @param {any} globby
 * @param {ExtraFileRequest} request
 * @returns {Promise<File[]>}
 */
function getFiles(globby, request) {
  return globby(
    request.files.map(
      (file) =>
        (file.included ? '' : '!') + OsHelpers.makePathOsAgnostic(file.pattern)
    ),
    {
      ignore: request.excludedDirectories,
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
