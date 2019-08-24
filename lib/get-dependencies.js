/*
 * Credit goes to @zwilias, from his PR here https://github.com/rtfeldman/node-test-runner/pull/356/files
 */

const spawnAsync = require('./spawn-async');

function getDependencies(pathToElmJson) {
  return spawnAsync(
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
  )
    .then(JSON.parse)
    .catch(error => {
      if (error.message.startsWith('phase: retrieve')) {
        throw new Error(
          `I'm sorry, but it looks like you don't have access to the Internet at the moment.

I require an Internet connection for some of my inner workings.
Please connect to the Internet and try again.`
        );
      }

      throw error;
    });
}

module.exports = getDependencies;
