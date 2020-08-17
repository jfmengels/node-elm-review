#!/usr/bin/env node

const Ansi = require('./helpers/ansi');
const {execSync} = require('child_process');
const updateExamplesFromPreview = require('../maintenance/update-example-from-preview');

const preCheckGitStatus = execSync('git status --porcelain').toString().trim();
if (preCheckGitStatus !== '') {
  console.error(
    `${Ansi.red(
      '✖'
    )} Check aborted: There are uncommitted changes in the project.`
  );
  process.exit(1);
}

updateExamplesFromPreview();

const postCheckGitStatus = execSync('git status --porcelain').toString().trim();
if (postCheckGitStatus !== '') {
  console.error('\u001B[31m✖\u001B[39m Your examples need to be updated.');
  console.log(
    `Please run ${Ansi.yellow(
      'node maintenance/update-examples-from-preview.js'
    )}`
  );
  process.exit(1);
}

process.exit(0);
