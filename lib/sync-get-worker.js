const {parentPort, workerData} = require('worker_threads');
const https = require('https');

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

    Atomics.notify(sharedLockArray, 0, Infinity);
  });
}

/**
 * @param {string} url
 * @return {Promise<string>}
 */
async function getBody(url) {
  return new Promise((resolve, reject) => {
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
