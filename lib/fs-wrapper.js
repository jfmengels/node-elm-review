const fs = require('graceful-fs');
const fsp = fs.promises;
const {rimraf} = require('rimraf');

/**
 * @import {Path} from "./types/path"
 */

/**
 * Read a JSON file.
 *
 * @param {string} file
 * @param {((key: string, value: unknown) => unknown) | undefined} reviver
 * @returns {Promise<unknown>}
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

/**
 * @param {Path} file
 * @returns {unknown}
 */
function readJsonFileSync(file) {
  const data = fs.readFileSync(file, 'utf8');
  return JSON.parse(data);
}

/**
 * Read a file using Promises.
 *
 * @param {string} file
 * @param {object} options
 * @returns {Promise<string>}
 */
async function readFile(file, options = {encoding: 'utf8'}) {
  const data = await fsp.readFile(file, options);
  return data.toString();
}

/**
 * Write a JSON file.
 *
 * @param {string} file
 * @param {object} content
 * @param {string | number | undefined} space
 * @param {((key: string, value: unknown) => unknown) | undefined} [replacer]
 * @returns {Promise<void>}
 */
async function writeJson(file, content, space, replacer = undefined) {
  return await fsp.writeFile(file, JSON.stringify(content, replacer, space));
}

/**
 * @param {Path} dir
 * @returns {Promise<void>}
 */
async function mkdirp(dir) {
  await fsp.mkdir(dir, {recursive: true});
}

/**
 * @param {Path} dir
 * @returns {void}
 */
function mkdirpSync(dir) {
  fs.mkdirSync(dir, {recursive: true});
}

module.exports = {
  readFile,
  readJsonFile,
  readJsonFileSync,

  writeFile: fsp.writeFile,
  writeJson,

  mkdirp,
  mkdirpSync,

  readdir: fsp.readdir,

  remove: rimraf
};
