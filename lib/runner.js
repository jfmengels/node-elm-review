#!/usr/bin/env node

const fs = require('fs-extra');
const chalk = require('chalk');
const prompts = require('prompts');
const spawn = require('cross-spawn');
const dependencies = require('./dependencies');
const cache = require('./cache');
const {getProjectFiles} = require('./elm-files');
const {getElmBinary, getElmVersion} = require('./elm-binary');

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

const styleMessage = (options, message) => {
  const colorEnabled = options.color === undefined;
  return message
    .map(part => {
      const chalkWithColor = colorEnabled ? withColor(part) : chalk;
      return chalkWithColor(part.string);
    })
    .join('');
};

function sendProjectContent(app, elmJson, elmFiles, dependencies) {
  const filesPendingReceiptAcknowledgement = new Set(
    elmFiles.map(file => file.path)
  );

  app.ports.collectElmJson.send(elmJson);
  if (dependencies.length > 0) {
    app.ports.collectDependencies.send(dependencies);
  }

  return new Promise(resolve => {
    app.ports.acknowledgeFileReceipt.subscribe(acknowledgeFileReceipt);
    elmFiles.forEach(file => {
      app.ports.collectFile.send(file);
    });

    function acknowledgeFileReceipt(fileName) {
      filesPendingReceiptAcknowledgement.delete(fileName);

      if (filesPendingReceiptAcknowledgement.size === 0) {
        app.ports.acknowledgeFileReceipt.unsubscribe(acknowledgeFileReceipt);
        resolve();
      }
    }
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

async function formatExistingFile(options, file) {
  if (options.elmFormatPath) {
    const spawnedUsingPathFromArgs = spawn.sync(
      options.elmFormatPath,
      ['--yes', '--elm-version=0.19', file.path],
      {
        shell: true
      }
    );

    if (spawnedUsingPathFromArgs.status !== 0) {
      const errorMessage = spawnedUsingPathFromArgs.stderr.toString();
      if (errorMessage.includes('not found')) {
        throw new Error(
          `I could not find the executable for \`elm-format\` at: ${options.elmFormatPath}`
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

function runReview(options, app) {
  return new Promise(resolve => {
    // TODO unsubscribe
    app.ports.askConfirmationToFix.subscribe(async data => {
      console.log(styleMessage(options, data.confirmationMessage));
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
        // fs.writeFileSync(file)
        fs.writeFileSync(data.file.path, data.file.source);
        const file = await formatExistingFile(options, data.file);
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

    // TODO unsubscribe
    app.ports.reviewReport.subscribe(result => {
      console.log(styleMessage(options, result.report));
      return resolve(result.success);
    });
    app.ports.startReview.send(true);
  });
}

async function initializeApp(options, elmModule) {
  const app = elmModule.Elm.Elm.Review.Main.init({
    flags: {
      fixMode: options.fix ? 'fix' : 'dontfix'
    }
  });

  app.ports.abort.subscribe(errorMessage => {
    throw new Error(errorMessage);
  });
  cache.forApp(options, app);

  const [
    {elmJson, elmFiles, sourcesDirectories},
    elmVersion
  ] = await Promise.all([
    getProjectFiles(options),
    getElmBinary(options).then(getElmVersion)
  ]);
  const projectDependencies = await dependencies.collect(elmJson, elmVersion);
  await sendProjectContent(app, elmJson, elmFiles, projectDependencies);

  return {
    app,
    elmJson,
    elmFiles,
    sourcesDirectories,
    projectDependencies
  };
}

module.exports = {
  initializeApp,
  runReview
};
