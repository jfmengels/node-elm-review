#!/usr/bin/env node

const path = require('path');
const Ansi = require('./helpers/ansi');
const {execSync} = require('child_process');
const {
  findPreviewConfigurations,
  findExampleAndPreviewConfigurations
} = require('./helpers/find-configurations');

const root = path.dirname(__dirname);
const packageElmJson = require(`${root}/elm.json`);

const hasBeenPublished = false || packageElmJson.version !== '1.0.0';

// Find all elm.json files

const exampleConfigurations = hasBeenPublished
  ? findExampleAndPreviewConfigurations()
  : findPreviewConfigurations();

exampleConfigurations.forEach(checkThatExampleCompiles);

function checkThatExampleCompiles(exampleConfiguration) {
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
          `${Ansi.red('✖')} ${Ansi.yellow(
            `${path.relative(root, exampleConfiguration)}/`
          )} does not compile`
        );
        console.log(
          `Please run
    ${Ansi.yellow(`npx elm-review --config ${exampleConfiguration}/`)}
and make the necessary changes to make it compile.`
        );
        process.exit(1);
      }

      success(exampleConfiguration);
      return;
    } catch {
      console.log(
        `An error occurred while trying to check whether the ${Ansi.yellow(
          path.relative(root, exampleConfiguration)
        )} configuration compiles.`
      );
      console.error(error);
      process.exit(1);
    }
  }
}

// HELPERS

function parseExecOutput(error) {
  // TODO Only parse stdout once we release the next version
  try {
    return JSON.parse(error.stderr);
  } catch {
    return JSON.parse(error.stdout);
  }
}

function success(config) {
  console.log(`${Ansi.green('✔')} ${path.relative(root, config)}/ compiles`);
}
