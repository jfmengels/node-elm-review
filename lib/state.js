#!/usr/bin/env node

const type = Symbol('type');

const model = {
  filesBeingWrittenToCache: new Set(),
  exitRequest: {
    requested: false,
    exitCode: 1
  }
};

function update(message) {
  switch (message[type]) {
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

    default: {
      return model;
    }
  }
}

function getModel() {
  return model;
}

// Messages

function exitRequested(exitCode) {
  return update({
    [type]: 'exitRequested',
    exitCode
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
  getModel,

  // Messages
  exitRequested,
  writingToFileSystemCacheStarted,
  writingToFileSystemCacheFinished
};
