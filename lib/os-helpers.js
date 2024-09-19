// @ts-expect-error(TS6133): There's a bug in noUnusedLocals (microsoft/TypeScript#58368).
/** @import {Path} from './types/path'; */

/**
 * @param {Path} path_
 * @returns {Path}
 */
function makePathOsAgnostic(path_) {
  return path_.replace(/.:/, '').replace(/\\/g, '/');
}

module.exports = {
  makePathOsAgnostic
};
