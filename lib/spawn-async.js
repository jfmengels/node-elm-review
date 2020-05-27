const crossSpawn = require('cross-spawn');

function spawnAsync(...spawnArgs) {
  return new Promise((resolve, reject) => {
    const child = crossSpawn(...spawnArgs);
    child.stdout.on('data', (data) => {
      return resolve(data.toString());
    });

    child.stderr.on('data', (error) => {
      return reject(new Error(error.toString()));
    });
  });
}

module.exports = spawnAsync;
