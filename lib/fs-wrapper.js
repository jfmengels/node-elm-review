/**
 * @import {Path} from './types/path';
 * @import {Replacer, Reviver} from './types/json';
 */
const fs = require('graceful-fs');
const fsp = fs.promises;
const {rimraf} = require('rimraf');

/**
 * Read a JSON file.
 *
 * @param {string} file
 * @param {Reviver | undefined} [reviver=undefined]
 * @returns {Promise<unknown>}
 */
async function readJsonFile(file, reviver) {
  const data = await readFile(file, {encoding: 'utf8'});

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
 * @param {object} content
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

module.exports = {
  readFile,
  readJsonFile,
  readJsonFileSync,

  writeFile: fsp.writeFile,
  writeJson,

  mkdirp,
  mkdirpSync,

  readdir: fsp.readdir,

  remove: rimraf,

  stat: fsp.stat
};
