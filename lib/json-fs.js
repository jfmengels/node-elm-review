const fs = require('graceful-fs');

module.exports = {
  readFile,
  readJsonFile
};

/**
 * Read a JSON file.
 * @param {string} file
 * @param {((this: any, key: string, value: Object) => Object) | null} reviver
 * @returns {Promise<Object>}
 */
async function readJsonFile(file, reviver = null) {
  const data = await readFile(file, {encoding: 'utf8', reviver});

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
 * Read a file using Promises.
 * @param {string} file
 * @param {Object} options
 * @returns {Promise<string>}
 */
function readFile(file, options = 'utf8') {
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
