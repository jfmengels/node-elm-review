#!/usr/bin/env node

const type = Symbol('type');

let appModel = {
  filesBeingWrittenToCache: new Set(),
  exitRequest: {
    requested: false,
    exitCode: 1
  }
};

function update(message, model) {
  switch (message[type]) {
    case 'exitRequested': {
      if (model.filesBeingWrittenToCache.size === 0) {
        process.exit(message.exitCode);
      }

      return {
        ...model,
        exitRequest: {
          requested: true,
          exitCode: message.exitCode
        }
      };
    }

    case 'writingToFileSystemCacheStarted': {
      // Sets are not immutable, no point in cloning the model :(
      model.filesBeingWrittenToCache.add(message.sourceHash);
      return model;
    }

    case 'writingToFileSystemCacheFinished': {
      // Sets are not immutable, no point in cloning the model :(
      model.filesBeingWrittenToCache.delete(message.sourceHash);

      if (
        model.filesBeingWrittenToCache.size === 0 &&
        model.exitRequest.requested
      ) {
        process.exit(model.exitRequest.exitCode);
      }

      return model;
    }

    default: {
      return model;
    }
  }
}

function getModel() {
  return appModel;
}

function sendMessage(message) {
  appModel = update(message, appModel);
  return appModel;
}

// Messages

function exitRequested(exitCode) {
  return sendMessage({
    [type]: 'exitRequested',
    exitCode
  });
}

function writingToFileSystemCacheStarted(hash) {
  return sendMessage({
    [type]: 'writingToFileSystemCacheStarted',
    hash
  });
}

function writingToFileSystemCacheFinished(hash) {
  return sendMessage({
    [type]: 'writingToFileSystemCacheFinished',
    hash
  });
}

module.exports = {
  getModel,

  // Messages
  exitRequested,
  writingToFileSystemCacheStarted,
  writingToFileSystemCacheFinished
};
