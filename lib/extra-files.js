/**
 * @import {ExtraFileRequest, NonElmFiles} from './types/content';
 */
const {glob} = require('tinyglobby');
const FS = require('./fs-wrapper');
const {unique} = require('./utils');
const PathHelpers = require('./path-helpers');

/**
 * Collect the extra files requested by the rules.
 *
 * @param {ExtraFileRequest[]} requests
 * @returns {Promise<NonElmFiles>}
 */
async function collect(requests) {
  const files2D = await Promise.all(
    requests.map(async (request) => await getFiles(request))
  );
  const files = unique(files2D.flat());

  const filesAndContents = await Promise.all(
    files.map(async (filePath) => {
      const content = await FS.readFile(filePath);
      // Normalize paths for cross-platform consistency
      const normalizedPath = PathHelpers.toUnixPath(filePath);
      return {
        path: normalizedPath,
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
  return await glob(
    request.files.map((file) => `${file.included ? '' : '!'}${file.pattern}`),
    {
      ignore: request.excludedDirectories,
      followSymbolicLinks: true,
      expandDirectories: false,
      caseSensitiveMatch: true,
      dot: true
    }
  );
}

module.exports = {
  collect
};
