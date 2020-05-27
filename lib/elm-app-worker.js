// eslint-disable-next-line node/no-unsupported-features/node-builtins
const {parentPort, workerData} = require('worker_threads');
const loadCompiledElmApp = require('./load-compiled-app');

const elmModule = loadCompiledElmApp(workerData.elmModulePath);

const app = elmModule.Elm.Elm.Review.Main.init({
  flags: workerData.flags
});

parentPort.on('message', ([port, data]) => {
  app.ports[port].send(data);
});

app.ports.cacheFile.subscribe((data) => {
  parentPort.postMessage(['cacheFile', data]);
});
app.ports.acknowledgeFileReceipt.subscribe((data) => {
  parentPort.postMessage(['acknowledgeFileReceipt', data]);
});
app.ports.reviewReport.subscribe((data) => {
  parentPort.postMessage(['reviewReport', data]);
});
app.ports.askConfirmationToFix.subscribe((data) => {
  parentPort.postMessage(['askConfirmationToFix', data]);
});
app.ports.fixConfirmationStatus.subscribe((data) => {
  parentPort.postMessage(['fixConfirmationStatus', data]);
});
app.ports.abort.subscribe((data) => {
  parentPort.postMessage(['abort', data]);
});
