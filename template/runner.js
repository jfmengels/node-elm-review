#!/usr/bin/env node

const getElmFiles = require('./elm-files');
const Elm = require('./compiledLintApp');

const elmFiles = getElmFiles([]);
if (elmFiles.length === 0) {
  console.error('I could not find any files to lint.'); // eslint-disable-line no-console
  process.exit(1);
}

const app = Elm.Elm.LintApp.init();

elmFiles.forEach(file => {
  app.ports.collectFile.send(file);
})

setTimeout(() => {
  app.ports.finishedCollecting.send(true);
}, 500)

app.ports.resultPort.subscribe(function(result) {
  console.log(result.report.join('')); // eslint-disable-line no-console
  process.exit(result.success ? 0 : 1);
});
