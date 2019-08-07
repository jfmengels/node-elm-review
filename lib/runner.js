#!/usr/bin/env node

const chalk = require('chalk');
const {getElmFiles, writeElmFiles} = require('./elm-files');

const interpretReport = (args, report) => {
  // TODO Document color disabling
  const colorEnabled = args.color === undefined;
  return report
    .map(part => {
      const chalkWithColor =
        part.color && colorEnabled
          ? chalk.rgb(part.color[0], part.color[1], part.color[2])
          : chalk;
      return chalkWithColor(part.string);
    })
    .join('');
};

const errorTimeout = () => {
  console.error(
    'Something went wrong, and it took me too long to analyze your codebase, which is unexpected'
  );
  process.exit(1);
};

function runLinting(args, Elm) {
  const elmFiles = getElmFiles([]);

  if (elmFiles.length === 0) {
    console.error('I could not find any files to lint.');
    process.exit(1);
  }

  const filesPendingReceiptAcknowledgement = new Set(
    elmFiles.map(file => file.path)
  );

  const app = Elm.Elm.Main.init({
    flags: {
      fixMode: args['fix-all'] ? 'fix-all' : 'dontfix'
    }
  });

  app.ports.abort.subscribe(errorMessage => {
    console.error(errorMessage);
    process.exit(1);
  });

  app.ports.acknowledgeFileReceipt.subscribe(fileName => {
    filesPendingReceiptAcknowledgement.delete(fileName);
    clearTimeout(timeout);
    timeout = setTimeout(errorTimeout, 3000);

    if (filesPendingReceiptAcknowledgement.size === 0) {
      app.ports.requestToLint.send(true);
    }
  });

  app.ports.resultPort.subscribe(result => {
    console.log(interpretReport(args, result.report));
    writeElmFiles(result.fixedFiles)
      .then(() => {
        if (result.fixedFiles.length > 0) {
          // TODO Add header like `-- ELM-LINT FIX REPORT ------`
          // TODO Use module name for each file instead of the path
          const fixedFiles = result.fixedFiles
            .map(file => `  - ${file.path}`)
            .join('\n');

          console.log(
            `I automatically fixed some problems in the following files:\n${fixedFiles}\n`
          );
        }

        process.exit(result.success ? 0 : 1);
      })
      .catch(error => {
        console.error(error);
        process.exit(1);
      });
  });

  let timeout = setTimeout(errorTimeout, 3000);

  elmFiles.forEach(file => {
    app.ports.collectFile.send(file);
  });
}

module.exports = runLinting;
