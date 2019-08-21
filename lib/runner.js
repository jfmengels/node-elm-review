#!/usr/bin/env node

const fs = require('fs-extra');
const chalk = require('chalk');
const prompts = require('prompts');
const spawn = require('cross-spawn');
const {getElmFiles, writeElmFiles} = require('./elm-files');

function withColor(part) {
  const chalkWithColor = part.color
    ? chalk.rgb(part.color[0], part.color[1], part.color[2])
    : chalk;
  return part.backgroundColor
    ? chalkWithColor.bgRgb(
        part.backgroundColor[0],
        part.backgroundColor[1],
        part.backgroundColor[2]
      )
    : chalkWithColor;
}

const styleMessage = (args, message) => {
  const colorEnabled = args.color === undefined;
  return message
    .map(part => {
      const chalkWithColor = colorEnabled ? withColor(part) : chalk;
      return chalkWithColor(part.string);
    })
    .join('');
};

function requestLintResult(app, elmFiles) {
  const filesPendingReceiptAcknowledgement = new Set(
    elmFiles.map(file => file.path)
  );

  return new Promise(resolve => {
    app.ports.acknowledgeFileReceipt.subscribe(fileName => {
      filesPendingReceiptAcknowledgement.delete(fileName);

      if (filesPendingReceiptAcknowledgement.size === 0) {
        resolve();
      }
    });

    elmFiles.forEach(file => {
      app.ports.collectFile.send(file);
    });
  });
}

// TODO Format file before saving it.
// eslint-disable-next-line no-unused-vars
function formatFileContent(file) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      'npx',
      ['--no-install', 'elm-format', '--stdin', '--yes', '--elm-version=0.19'],
      {shell: true}
    );

    child.on('data', newSource =>
      resolve({
        file: file.path,
        source: newSource
      })
    );
    child.on('error', reject);
    child.stdin.write(file.source);
    child.stdin.end();
  });
}

function formatExistingFile(args, file) {
  if (args['elm-format-path']) {
    const spawnedUsingPathFromArgs = spawn.sync(
      args['elm-format-path'],
      ['--yes', '--elm-version=0.19', file.path],
      {
        shell: true
      }
    );

    if (spawnedUsingPathFromArgs.status !== 0) {
      const errorMessage = spawnedUsingPathFromArgs.stderr.toString();
      if (errorMessage.includes('not found')) {
        throw new Error(
          `I could not find the executable for \`elm-format\` at: ${
            args['elm-format-path']
          }`
        );
      }
    }
  } else {
    const spawnedUsingNpx = spawn.sync(
      'npx',
      ['--no-install', 'elm-format', '--yes', '--elm-version=0.19', file.path],
      {shell: true}
    );

    if (spawnedUsingNpx.status !== 0) {
      const error = spawnedUsingNpx.stderr.toString();
      if (!error.includes('not found')) {
        throw new Error(error);
      }

      const spawnedUsingGlobal = spawn.sync(
        'elm-format',
        ['--yes', '--elm-version=0.19', file.path],
        {
          shell: true
        }
      );
      if (spawnedUsingGlobal.status !== 0) {
        throw new Error(spawnedUsingGlobal.stderr.toString());
      }
    }
  }

  return {
    path: file.path,
    source: fs.readFileSync(file.path, 'utf8')
  };
}

function startLinting(args, app) {
  return new Promise(resolve => {
    app.ports.askConfirmationToFix.subscribe(async data => {
      console.log(styleMessage(args, data.confirmationMessage));
      const {accepted} = await prompts({
        type: 'confirm',
        name: 'accepted',
        message: 'Do you wish to apply this fix?',
        initial: true
      });
      if (accepted === undefined) {
        // User interrupted the process using Ctrl-C
        process.exit(1);
      }

      if (accepted) {
        // TODO Format file before saving it.
        // I could not manage to make this work at the moment
        //
        // const file = await formatFileContent(data.file)
        // await writeElmFiles([file])
        await writeElmFiles([data.file]);
        const file = formatExistingFile(args, data.file);
        app.ports.userConfirmedFix.send({
          answer: true,
          file
        });
      } else {
        app.ports.userConfirmedFix.send({
          answer: false
        });
      }
    });
    app.ports.lintReport.subscribe(resolve);
    app.ports.requestToLint.send(true);
  });
}

async function runLinting(args, Elm) {
  const elmFiles = getElmFiles([]);

  if (elmFiles.length === 0) {
    console.error('I could not find any files to lint.');
    process.exit(1);
  }

  const app = Elm.Elm.Main.init({
    flags: {
      fixMode: args.fix ? 'fix' : 'dontfix'
    }
  });

  app.ports.abort.subscribe(errorMessage => {
    console.error(errorMessage);
    process.exit(1);
  });

  await requestLintResult(app, elmFiles);
  const result = await startLinting(args, app);
  console.log(styleMessage(args, result.report));
  process.exit(result.success ? 0 : 1);
}

module.exports = runLinting;
