function promisifyPort({subscribeTo, sendThrough, data}) {
  return new Promise((resolve) => {
    const handler = (result) => {
      subscribeTo.unsubscribe(handler);
      resolve(result);
    };

    subscribeTo.subscribe(handler);
    sendThrough.send(data);
  });
}

module.exports = promisifyPort;
