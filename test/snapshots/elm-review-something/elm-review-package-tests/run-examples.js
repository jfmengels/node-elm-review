#!/usr/bin/env node

const path = require('path');
const glob = require('glob');
const {execSync} = require('child_process');

const root = path.dirname(__dirname);
const packageElmJson = require(`${root}/elm.json`);

const hasBeenPublished = false || packageElmJson.version !== '1.0.0';

// Find all elm.json files

const globPattern = hasBeenPublished
  ? `${root}/@(example|preview)*/**/elm.json`
  : `${root}/preview*/**/elm.json`;
const exampleConfigurations = glob
  .sync(makePathOsAgnostic(globPattern), {
    nocase: true,
    ignore: ['**/elm-stuff/**'],
    nodir: false
  })
  .map(path.dirname);

exampleConfigurations.forEach((exampleConfiguration) => {
  try {
    execSync(`npx elm-review --config ${exampleConfiguration} --report=json`, {
      encoding: 'utf8',
      stdio: 'pipe',
      cwd: path.resolve(__dirname, '..')
    }).toString();
    success(exampleConfiguration);
  } catch (error) {
    try {
      const output = parseExecOutput(error);
      // We don't care whether there were any reported errors.
      // If the root type is not "error", then the configuration compiled
      // successfully, which is all we care about in this test.
      if (output.type !== 'review-errors') {
        console.log(
          `${red('✖')} ${yellow(
            `${path.relative(root, exampleConfiguration)}/`
          )} does not compile`
        );
        console.log(
          `Please run ${yellow(
            `npx elm-review --config ${exampleConfiguration}/`
          )} and make the necessary changes to make it compile.`
        );
        process.exit(1);
      }

      success(exampleConfiguration);
      return;
    } catch {
      console.log(
        `An error occurred while trying to check whether the ${yellow(
          path.relative(root, exampleConfiguration)
        )} configuration compiles.`
      );
      console.error(error);
      process.exit(1);
    }
  }
});

// HELPERS

function parseExecOutput(error) {
  // TODO Only parse stdout once we release the next version
  try {
    return JSON.parse(error.stderr);
  } catch {
    return JSON.parse(error.stdout);
  }
}

function red(text) {
  return "\033[31m" + text + "\033[39m"
}

function green(text) {
  return "\033[32m" + text + "\033[39m"
}

function yellow(text) {
  return "\033[33m" + text + "\033[39m"
}

function success(config) {
  console.log(`${green('✔')} ${path.relative(root, config)}/ compiles`);
}

function makePathOsAgnostic(path_) {
  return path_.replace(/.:/, '').replace(/\\/g, '/');
}
