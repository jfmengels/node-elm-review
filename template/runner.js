#!/usr/bin/env node

const getElmFiles = require('./elm-files');
const Elm = require('./compiledLintApp');

const elmFiles = getElmFiles([]);
if (elmFiles.length === 0) {
  console.error('Could not find any files to lint.'); // eslint-disable-line no-console
  process.exit(1);
}

const app = Elm.LintApp.worker();

app.ports.linting.send(elmFiles);

app.ports.resultPort.subscribe(function(result) {
  console.log(result.report); // eslint-disable-line no-console
  process.exit(result.success ? 0 : 1);
});
