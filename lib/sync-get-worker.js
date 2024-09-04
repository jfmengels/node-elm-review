const https = require('node:https');
const {parentPort, workerData} = require('node:worker_threads');

const {sharedLock, requestPort} = workerData;
const sharedLockArray = new Int32Array(sharedLock);

if (parentPort) {
  parentPort.on('message', async (url) => {
    try {
      const response = await getBody(url);
      requestPort.postMessage(response);
    } catch (error) {
      requestPort.postMessage({error});
    }

    Atomics.notify(sharedLockArray, 0, Number.POSITIVE_INFINITY);
  });
}

/**
 * @param {string} url
 * @returns {Promise<string>}
 */
async function getBody(url) {
  return await new Promise((resolve, reject) => {
    https
      .get(url, (res) => {
        let body = '';
        res.on('data', (chunk) => {
          body += chunk;
        });
        res.on('end', () => {
          resolve(body);
        });
      })
      .on('error', (err) => {
        reject(err);
      });
  });
}
