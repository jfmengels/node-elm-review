const util = require('util');
const fs = require('graceful-fs');
const {rimraf} = require('rimraf');

// TODO When we drop support for Node.js v10, use natively promisified functions

/**
 * Read a JSON file.
 * @param {string} file
 * @param {((this: any, key: string, value: any) => any) | undefined} reviver
 * @returns {Promise<Object>}
 */
async function readJsonFile(file, reviver = undefined) {
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

function readJsonFileSync(file) {
  const data = fs.readFileSync(file, 'utf8');
  return JSON.parse(data);
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
        resolve(data.toString());
      }
    });
  });
}

const writeFile = util.promisify(fs.writeFile);

/**
 * Write a JSON file.
 * @param {string} file
 * @param {Object} content
 * @param {string | number | undefined} space
 * @param {((this: any, key: string, value: any) => any) | undefined} [replacer=undefined]
 * @returns {Promise<void>}
 */
function writeJson(file, content, space, replacer) {
  return writeFile(file, JSON.stringify(content, replacer, space));
}

const promisifiedMkdir = util.promisify(fs.mkdir);

function mkdirp(dir) {
  return promisifiedMkdir(dir, {recursive: true});
}

function mkdirpSync(dir) {
  return fs.mkdirSync(dir, {recursive: true});
}

module.exports = {
  readFile,
  readJsonFile,
  readJsonFileSync,

  writeFile,
  writeJson,

  mkdirp,
  mkdirpSync,

  readdir: util.promisify(fs.readdir),

  remove: rimraf
};
