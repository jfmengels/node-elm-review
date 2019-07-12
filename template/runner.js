#!/usr/bin/env node

const chalk = require('chalk')
const getElmFiles = require('./elm-files');
const Elm = require('./compiledLintApp');

const colorEnabled = process.argv.includes("color=1")

const elmFiles = getElmFiles([]);
if (elmFiles.length === 0) {
  console.error('I could not find any files to lint.'); // eslint-disable-line no-console
  process.exit(1);
}

const app = Elm.Elm.LintApp.init();

const interpretReport = report => {
  return report.map(part => {
    const chalkWithColor = part.color && colorEnabled ? chalk[part.color] : chalk
    return chalkWithColor(part.string)
  }).join('')
}

elmFiles.forEach(file => {
  app.ports.collectFile.send(file);
})

setTimeout(() => {
  app.ports.finishedCollecting.send(true);
}, 500)

app.ports.resultPort.subscribe(function(result) {
  console.log(interpretReport(result.report)) // eslint-disable-line no-console
  process.exit(result.success ? 0 : 1);
});
