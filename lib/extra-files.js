/**
 * @import {ExtraFileRequest, NonElmFiles} from './types/content';
 */
const FS = require('./fs-wrapper');
const OsHelpers = require('./os-helpers');
const {unique} = require('./utils');

/**
 * Collect the extra files requested by the rules.
 *
 * @param {ExtraFileRequest[]} requests
 * @returns {Promise<NonElmFiles>}
 */
async function collect(requests) {
  const files2D = await Promise.all(
    requests.map((request) => getFiles(request))
  );
  const files = unique(files2D.flat());

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
 * @param {ExtraFileRequest} request
 * @returns {Promise<string[]>}
 */
async function getFiles(request) {
  const {globby} = await import('globby');

  return await globby(
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

module.exports = {
  collect
};
