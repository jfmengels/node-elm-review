/**
 * @file A fast `npx` alternative.
 */

/**
 * @import {Path} from './types/path';
 */

const path = require('pathe');
const getPathKey = require('path-key');

/**
 * The key for `process.env` containing the path, generally `PATH`.
 *
 * @type {string}
 */
const pathKey = getPathKey();

/**
 * Prepends `node_modules/.bin` up to the root directory to the PATH.
 *
 * @remarks
 * When `--elm-format-path` was _not_ provided, we used to execute
 * `elm-format` like this:
 *
 * 1. Try `npx elm-format`
 * 2. Try `elm-format`
 *
 * Just starting `npx` takes 200 ms though. Luckily, `npx` isn’t even
 * necessary, because the common ways of running `elm-review` are:
 *
 * 1. Install everything globally and run just `elm-review`.
 * 2. Install everything locally and run `npx elm-review`.
 * 3. Use the `--elm-format-path`.
 *
 * However, `npx` adds all potential `node_modules/.bin` up to current directory to the
 * beginning of PATH, for example:
 *
 * ```sh
 * $ npx node -p 'process.env.PATH.split(require("path").delimiter)'
 * [
 *   '/Users/you/stuff/node_modules/.bin',
 *   '/Users/you/node_modules/.bin',
 *   '/Users/node_modules/.bin',
 *   '/node_modules/.bin',
 *   '/usr/bin',
 *   'etc'
 * ]
 * ```
 *
 * So if a user runs `npx elm-review`, when we later try to spawn just
 * `elm-format`, it’ll be found since when spawning we inherit the same PATH.
 *
 * The `npx elm-format` approach has been removed to avoid those unnecessary 200 ms,
 * but to stay backwards compatible we prepend the same paths to the beginning
 * of PATH just like `npx` would (see above). This is needed when:
 *
 * - Executing `elm-review` _without_ `npx`/`npm exec`, npm scripts, or `--elm-format-path`.
 * - And expecting a _local_ `elm-format` to be used.
 *   That’s an odd use case, but was supported due to the `npx` approach.
 *
 * This can be removed in a major version.
 *
 * @param {Path | undefined} providedBinaryPath
 * @param {string} cwd
 * @returns {Path}
 */
function backwardsCompatiblePath(providedBinaryPath, cwd) {
  return [
    ...cwd
      .split(path.sep)
      .map((_, index, parts) =>
        [...parts.slice(0, index + 1), 'node_modules', '.bin'].join(path.sep)
      )
      .reverse(),
    [
      ...(providedBinaryPath
        ? [path.resolve(path.dirname(providedBinaryPath))]
        : [])
    ],
    process.env[pathKey]
  ].join(path.delimiter);
}

module.exports = {
  backwardsCompatiblePath,
  pathKey
};
