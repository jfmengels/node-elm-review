// @flow
/* eslint-disable unicorn/no-process-exit */

process.title = 'elm-review';

const stripAnsi = require('strip-ansi');
const help = require('./help');
const initializeProject = require('./init');
const watch = require('./watch');
const builder = require('./build');
const runner = require('./runner');
const appState = require('./state');
const Options = require('./options');
const appWrapper = require('./app-wrapper');

const options = Options.compute(process.argv);

process.on('uncaughtException', errorHandler);
function errorHandler(err) {
  if (options.report === 'json') {
    if (options.debug) {
      console.log(JSON.stringify(reportErrorForJson(err), 0, 2));
    } else {
      console.log(JSON.stringify(reportErrorForJson(err)));
    }
  } else if (options.debug) {
    console.error(err);
  } else {
    console.error(err.message || err);
  }

  process.exit(1);
}

function reportErrorForJson(err) {
  const errorMessage = stripAnsi((err.message || err).toString());
  const titleRegex = /-- (.*) -+/;
  const titleRegexResult = titleRegex.exec(errorMessage);
  if (titleRegexResult) {
    const bodyLines = errorMessage.split('\n');
    bodyLines.shift();
    return [
      {
        title: titleRegexResult[1],
        body: bodyLines.join('\n').trim()
      }
    ];
  }

  return {
    title: 'UNEXPECTED ERROR',
    body: errorMessage
  };
}

async function runElmReview() {
  const {elmModulePath} = await builder.build(options);
  const {app} = await runner.initializeApp(options, elmModulePath);
  const success = await runner.runReview(options, app);
  appState.exitRequested(success ? 0 : 1);
}

async function runElmReviewInWatchMode() {
  appWrapper.stop();
  const {elmModulePath, reviewElmJson, reviewElmJsonPath} = await builder.build(
    options
  );
  const initialization = await runner.initializeApp(options, elmModulePath);
  watch(
    options,
    {...initialization, reviewElmJson, reviewElmJsonPath},
    runElmReviewInWatchMode,
    errorHandler
  );
  await runner.runReview(options, initialization.app).catch(errorHandler);
}

module.exports = () => {
  if (options.version) {
    console.log(options.packageJsonVersion);
    return;
  }

  if (options.subcommand === 'init') {
    if (options.help) {
      return help.init();
    }

    return initializeProject(options).catch(errorHandler);
  }

  if (options.help) {
    return help.review(options);
  }

  if (options.watch) {
    return runElmReviewInWatchMode().catch(errorHandler);
  }

  runElmReview().catch(errorHandler);
};
