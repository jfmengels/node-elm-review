/*
 * Credit goes to @zwilias, from his PR here https://github.com/rtfeldman/node-test-runner/pull/356/files
 */

const spawn = require('cross-spawn');

function getDependencies(pathToElmJson) {
  return new Promise((resolve, reject) => {
    const child = spawn(
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
    child.stdout.on('data', data => {
      return resolve(JSON.parse(data.toString()));
    });

    child.stderr.on('data', error => {
      const errorMessage = error.toString();
      if (errorMessage.startsWith('phase: retrieve')) {
        reject(
          new Error(
            `I'm sorry, but it looks like you don't have access to the Internet at the moment.

I require an Internet connection for some of my inner workings.
Please connect to the Internet and try again.`
          )
        );
      }

      reject(new Error(error.toString()));
    });
  });
}

module.exports = getDependencies;
