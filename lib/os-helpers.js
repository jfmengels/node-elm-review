// eslint-disable-next-line @typescript-eslint/ban-ts-comment -- the noUnusedLocals bug is non-deterministic.
// @ts-ignore(TS6133): There's a bug in noUnusedLocals (microsoft/TypeScript#58368).
/** @import {Path} from './types/path'; */

/**
 * @param {Path} path
 * @returns {Path}
 */
function makePathOsAgnostic(path) {
  return path.replace(/.:/, '').replace(/\\/g, '/');
}

module.exports = {
  makePathOsAgnostic
};
