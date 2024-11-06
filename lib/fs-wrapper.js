/**
 * @import {Replacer, Reviver} from './types/json';
 * @import {Path} from './types/path';
 */
const fs = require('graceful-fs');
const fsp = fs.promises;

/**
 * Read a JSON file.
 *
 * @param {Path} file
 * @param {Reviver | undefined} [reviver=undefined]
 * @returns {Promise<unknown>}
 */
async function readJsonFile(file, reviver) {
  const data = await readFile(file, {encoding: 'utf8'});

  return parseJsonFromFile(data, file, reviver);
}

/**
 *
 * @param {string} data
 * @param {Path} file
 * @param {Reviver | undefined} reviver
 * @returns {unknown}
 */
function parseJsonFromFile(data, file, reviver) {
  try {
    return JSON.parse(data, reviver);
  } catch (error) {
    error.message = `${file}: ${error.message}`;
    throw error;
  }
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
 * @param {fs.BaseEncodingOptions & { flag?: fs.OpenMode | undefined }} [options={encoding: 'utf8'}]
 * @returns {Promise<string>}
 */
async function readFile(file, options) {
  const data = await fsp.readFile(file, {encoding: 'utf8', ...options});
  return data.toString();
}

/**
 * Write a JSON file.
 *
 * @param {string} file
 * @param {unknown} content
 * @param {string | number | undefined} [space=undefined]
 * @param {Replacer | undefined} [replacer=undefined]
 * @returns {Promise<void>}
 */
async function writeJson(file, content, space, replacer) {
  await fsp.writeFile(file, JSON.stringify(content, replacer, space));
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

/**
 * @param {fs.PathLike} file
 */
async function remove(file) {
  await fsp.rm(
    file,
    // Rimraf compatibility:
    {recursive: true, force: true, maxRetries: 10}
  );
}

module.exports = {
  readFile,
  readJsonFile,
  readJsonFileSync,

  writeFile: fsp.writeFile,
  writeJson,

  mkdirp,
  mkdirpSync,

  remove,

  readdir: fsp.readdir,

  stat: fsp.stat
};
