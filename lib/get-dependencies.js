/*
 * Credit goes to @zwilias, from his PR here https://github.com/rtfeldman/node-test-runner/pull/356/files
 */

const spawn = require('cross-spawn');

function getDependencies(pathToElmJson) {
  return new Promise(resolve => {
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
      console.error(error);
      // eslint-disable-next-line unicorn/no-process-exit
      process.exit(1);
    });
  });
}

module.exports = getDependencies;
