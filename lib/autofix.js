const fs = require('fs-extra');
const prompts = require('prompts');
const spawn = require('cross-spawn');
const styledMessage = require('./styled-message');

let currentApp = null;
let askConfirmationToFix = null;

function subscribe(options, app) {
  if (currentApp) {
    app.ports.askConfirmationToFix.unsubscribe(askConfirmationToFix);
  }

  currentApp = app;
  askConfirmationToFix =
    askConfirmationToFix || askConfirmationToFixWithOptions(options, app);
  app.ports.askConfirmationToFix.subscribe(askConfirmationToFix);
}

module.exports = {
  subscribe
};

function askConfirmationToFixWithOptions(options, app) {
  return async data => {
    console.log(styledMessage(options, data.confirmationMessage));
    const {accepted} = await prompts({
      type: 'confirm',
      name: 'accepted',
      message: 'Do you wish to apply this fix?',
      initial: true
    });
    if (accepted === undefined) {
      // User interrupted the process using Ctrl-C
      // eslint-disable-next-line unicorn/no-process-exit
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
  };
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
