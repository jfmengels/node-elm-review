const FS = require('./fs-wrapper');
const OsHelpers = require('./os-helpers');

/**
 * @import {ExtraFileRequest, NonElmFiles} from "./types/content"
 */

// microsoft/TypeScript#58955
/** @typedef {import("globby", {with: {'resolution-mode': 'import'}}).globby} globby */

/**
 * Collect the extra files requested by the rules.
 *
 * @param {ExtraFileRequest[]} requests
 * @returns {Promise<NonElmFiles>}
 */
async function collect(requests) {
  const {globby} = await import('globby');
  const files2D = await Promise.all(
    requests.map((request) => getFiles(globby, request))
  );
  const flatFiles = files2D.flat();
  const files = unique(flatFiles);

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
  }, /** @type {NonElmFiles} */ ({}));
}

/**
 * @param {globby} globby
 * @param {ExtraFileRequest} request
 * @returns {Promise<string[]>}
 */
function getFiles(globby, request) {
  return globby(
    request.files.map(
      (file) =>
        `${file.included ? '' : '!'}${OsHelpers.makePathOsAgnostic(
          file.pattern
        )}`
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

/**
 * @template T
 * @param {T[]} array
 * @returns {T[]}
 */
function unique(array) {
  return [...new Set(array)];
}

module.exports = {
  collect
};
