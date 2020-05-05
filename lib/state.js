#!/usr/bin/env node

const type = Symbol('type');

const model = {
  // NOTE: elmFilesCacheForWatch sometimes gets mutated in watch.js
  elmFilesCacheForWatch: new Map(),
  filesBeingWrittenToCache: new Set(),
  exitRequest: {
    requested: false,
    exitCode: 1
  }
};

// UPDATE

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
  exitRequested,
  filesWereUpdated,
  writingToFileSystemCacheStarted,
  writingToFileSystemCacheFinished
};
