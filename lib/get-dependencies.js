/*
 * Credit goes to @zwilias, from his PR here https://github.com/rtfeldman/node-test-runner/pull/356/files
 */

const spawn = require('cross-spawn');

function getDependencies(pathToElmJson) {
  const result = spawn.sync(
    'elm-json',
    [
      'solve',
      '--extra',
      'elm/core',
      'elm/json',
      'stil4m/elm-syntax',
      'jinjor/elm-diff',
      'elm/project-metadata-utils',
      '--',
      pathToElmJson
    ],
    {
      silent: true,
      env: process.env
    }
  );

  if (result.status != 0) {
    console.error(result.stderr.toString());
    process.exit(1);
    return {};
  }

  return JSON.parse(result.stdout.toString());
}

module.exports = getDependencies;
