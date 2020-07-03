const report = require('./report');
const appState = require('./state');
const promisifyPort = require('./promisify-port');

module.exports = {
  runReview,
  startReview,
  requestReview
};

async function runReview(options, app) {
  if (options.watch) {
    startReview(options, app);
    return undefined;
  }

  const result = await promisifyPort({
    subscribeTo: app.ports.reviewReport,
    sendThrough: app.ports.startReview,
    data: null
  });

  report(options, result);

  return result.success;
}

let isVeryFirstRun = true;
function startReview(options, app) {
  if (options.report !== 'json' && !isVeryFirstRun) {
    console.log('Running...');
  }

  isVeryFirstRun = false;
  return app.ports.startReview.send(null);
}

function requestReview(options, app) {
  if (appState.requestReview()) {
    startReview(options, app);
  }
}
