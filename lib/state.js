#!/usr/bin/env node

const type = Symbol('type');

const model = {
  // NOTE: elmFilesCacheForWatch sometimes gets mutated in watch.js
  elmFilesCacheForWatch: new Map(),
  filesBeingWrittenToCache: new Set(),
  exitRequest: {
    requested: false,
    exitCode: 1
  },
  appUnsubscribeFunctions: []
};

// UPDATE

function update(message) {
  switch (message[type]) {
    case 'initializedApp': {
      model.appUnsubscribeFunctions.forEach(unsubscribeFunction =>
        unsubscribeFunction()
      );
      model.appUnsubscribeFunctions.length = 0;
      return model;
    }

    case 'subscribe': {
      model.appUnsubscribeFunctions.push(message.unsubscribeFunction);
      return model;
    }

    case 'exitRequested': {
      if (model.filesBeingWrittenToCache.size === 0) {
        process.exit(message.exitCode);
      }

      model.exitRequest = {
        requested: true,
        exitCode: message.exitCode
      };
      return model;
    }

    case 'writingToFileSystemCacheStarted': {
      model.filesBeingWrittenToCache.add(message.sourceHash);
      return model;
    }

    case 'writingToFileSystemCacheFinished': {
      model.filesBeingWrittenToCache.delete(message.sourceHash);

      if (
        model.filesBeingWrittenToCache.size === 0 &&
        model.exitRequest.requested
      ) {
        process.exit(model.exitRequest.exitCode);
      }

      return model;
    }

    case 'filesWereUpdated': {
      message.files.forEach(file => {
        model.elmFilesCacheForWatch.set(file.path, {
          path: file.path,
          source: file.source,
          ast: file.ast
        });
      });
      return model;
    }

    default: {
      return model;
    }
  }
}

// ACCESS

function getFileFromCache(path) {
  return model.elmFilesCacheForWatch.get(path);
}

// MESSAGES

function initializedApp() {
  return update({
    [type]: 'initializedApp'
  });
}

function subscribe(port, subscriptionFunction) {
  port.subscribe(subscriptionFunction);

  return update({
    [type]: 'subscribe',
    unsubscribeFunction: () => port.unsubscribe(subscriptionFunction)
  });
}

function exitRequested(exitCode) {
  return update({
    [type]: 'exitRequested',
    exitCode
  });
}

function filesWereUpdated(files) {
  return update({
    [type]: 'filesWereUpdated',
    files
  });
}

function writingToFileSystemCacheStarted(hash) {
  return update({
    [type]: 'writingToFileSystemCacheStarted',
    hash
  });
}

function writingToFileSystemCacheFinished(hash) {
  return update({
    [type]: 'writingToFileSystemCacheFinished',
    hash
  });
}

module.exports = {
  getFileFromCache,

  // Messages
  initializedApp,
  subscribe,
  exitRequested,
  filesWereUpdated,
  writingToFileSystemCacheStarted,
  writingToFileSystemCacheFinished
};
