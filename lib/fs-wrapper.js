/**
 * @import {Replacer, Reviver} from './types/json';
 * @import {Path} from './types/path';
 */
const path = require('node:path');
const fs = require('graceful-fs');
const fsp = fs.promises;

/**
 * Read a JSON file.
 *
 * @param {Path} file
 * @param {Reviver} [reviver]
 * @returns {Promise<unknown>}
 */
async function readJsonFile(file, reviver) {
  const data = await readFile(file, {encoding: 'utf8'});

  return parseJsonFromFile(data, file, reviver);
}

/**
 * @param {string} data
 * @param {Path} file
 * @param {Reviver} [reviver]
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
 * @param {Path} file
 * @param {fs.BaseEncodingOptions & { flag?: fs.OpenMode | undefined }} [options={encoding: 'utf8'}]
 * @returns {Promise<string>}
 */
async function readFile(file, options = {}) {
  const data = await fsp.readFile(file, {encoding: 'utf8', ...options});
  return data.toString();
}

/**
 * Write a JSON file.
 *
 * @param {Path} file
 * @param {unknown} content
 * @param {string | number | undefined} [space]
 * @param {Replacer} [replacer]
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
 * @param {Path} file
 * @returns {Promise<void>}
 */
async function remove(file) {
  await fsp.rm(
    file,
    // Rimraf compatibility:
    {recursive: true, force: true, maxRetries: 10}
  );
}

/**
 * Copy files from srcFolder to destFolder.
 * @param {Path} srcFolder
 * @param {Path} destFolder
 * @param {Path[]} files
 * @returns {Promise<void>}
 */
async function copyFiles(srcFolder, destFolder, files) {
  const promises = files.map(async (file) => {
    const src = path.join(srcFolder, file);
    const srcContents = await readFile(src);
    const dest = path.join(destFolder, file);
    await fsp.writeFile(dest, srcContents);
  });

  await Promise.all(promises);
}

module.exports = {
  readFile,
  readJsonFile,
  readJsonFileSync,

  writeFile: fsp.writeFile,
  writeJson,

  mkdirp,
  mkdirpSync,

  // TODO(@lishaduck) [engine:node@>=16.7.0]: Use native `cp`.
  copyFiles,

  remove,

  readdir: fsp.readdir,

  stat: fsp.stat
};
