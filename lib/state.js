#!/usr/bin/env node

const Options = require('./options');

const options = Options.compute(process.argv);

module.exports = {
  // ACCESS
  getOptions,
  getFileFromCache,
  filesProposedByCurrentFix,

  // Messages
  initializedApp,
  subscribe,
  exitRequested,
  filesWereUpdated,
  readmeChanged,
  writingToFileSystemCacheStarted,
  writingToFileSystemCacheFinished,
  fixProposalReceived,
  fixWasAccepted,
  fixWasRefused
};

// MODEL

const model = {
  // NOTE: elmFilesCacheForWatch sometimes gets mutated in watch.js
  elmFilesCacheForWatch: new Map(),
  readme: null,
  filesBeingWrittenToCache: new Set(),
  exitRequest: {
    requested: false,
    exitCode: 1
  },
  appUnsubscribeFunctions: [],
  filesProposedByCurrentFix: []
};

// UPDATE

const type = Symbol('type');

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
      updateFilesInCache(message.files);
      return model;
    }

    case 'readmeChanged': {
      model.readme = message.readme;
      return model;
    }

    case 'fixProposalReceived': {
      model.filesProposedByCurrentFix = message.changedFiles;
      return model;
    }

    case 'fixWasAccepted': {
      updateFilesInCache(model.filesProposedByCurrentFix);
      model.filesProposedByCurrentFix.length = 0;
      return model;
    }

    case 'fixWasRefused': {
      model.filesProposedByCurrentFix.length = 0;
      return model;
    }

    default: {
      return model;
    }
  }
}

function updateFilesInCache(files) {
  files.forEach(file => {
    if (file.path.endsWith('.elm')) {
      model.elmFilesCacheForWatch.set(file.path, {
        path: file.path,
        source: file.source,
        ast: file.ast
      });
    }
  });
}

// ACCESS

function getOptions() {
  return options;
}

function getFileFromCache(path) {
  return model.elmFilesCacheForWatch.get(path);
}

function filesProposedByCurrentFix() {
  return model.filesProposedByCurrentFix;
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

function readmeChanged(readme) {
  const hasChanged = !model.readme || readme.content !== model.readme.content;

  update({
    [type]: 'readmeChanged',
    readme
  });

  return hasChanged;
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

function fixProposalReceived(changedFiles) {
  return update({
    [type]: 'fixProposalReceived',
    changedFiles
  });
}

function fixWasAccepted(files) {
  return update({
    [type]: 'fixWasAccepted',
    files
  });
}

function fixWasRefused() {
  return update({
    [type]: 'fixWasRefused'
  });
}
