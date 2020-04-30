const {
  Worker,
  isMainThread,
  parentPort,
  workerData
} = require('worker_threads');

const elmModule = require('../build/parseElm');

if (!isMainThread) {
  const app = elmModule.Elm.ParseMain.init();

  parseElmInWorker(app, workerData).then(result => {
    parentPort.postMessage(result);
  });
}

function parseElmInWorker(app, file) {
  return new Promise(resolve => {
    app.ports.parseResult.subscribe(handleResult);
    function handleResult(result) {
      if (result.path === file.path) {
        app.ports.parseResult.unsubscribe(handleResult);
        resolve(result.ast);
      }
    }

    app.ports.requestParsing.send(file);
  });
}

async function parseElm(file) {
  const worker = new Worker(__filename, {
    workerData: file
  });
  return new Promise((resolve, reject) => {
    worker.on('message', resolve);
    worker.on('error', reject);
    worker.on('exit', code => {
      if (code !== 0)
        reject(new Error(`Worker stopped with exit code ${code}`));
    });
  }).finally(() => worker.terminate());
}

module.exports = parseElm;
