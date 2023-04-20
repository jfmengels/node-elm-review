const fs = require('graceful-fs');

module.exports = {
  readJsonFile
};

/**
 * Read a JSON file.
 * @param {string} file
 * @param {((this: any, key: string, value: Object) => Object) | null} reviver
 * @returns {Promise<Object>}
 */
async function readJsonFile(file, reviver = null) {
  const data = await promiseRead(file, {encoding: 'utf8', reviver});

  let json;
  try {
    json = JSON.parse(data, reviver);
  } catch (error) {
    error.message = `${file}: ${error.message}`;
    throw error;
  }

  return json;
}

/**
 * Promisify reading a file.
 * @param {string} file
 * @param {Object} options
 * @returns {Promise<string>}
 */
function promiseRead(file, options) {
  return new Promise((resolve, reject) => {
    fs.readFile(file, options, (err, data) => {
      if (err) {
        reject(err);
      } else {
        resolve(data);
      }
    });
  });
}
