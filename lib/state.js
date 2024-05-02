#!/usr/bin/env node

/**
 * @typedef { import("./types/app").SubscribePort } SubscribePort
 * @typedef { import("./types/path").Path } Path
 * @typedef { import("./types/state").Model } Model
 * @typedef { import("./types/state").Msg } Msg
 * @typedef { import("./types/state").FileId } FileId
 * @typedef { import("./types/state").FilesProposedByCurrentFix } FilesProposedByCurrentFix
 * @typedef { import("./types/content").ElmFile } ElmFile
 * @typedef { import("./types/content").Readme } Readme
 * @typedef { import("./types/options").Options } Options
 */

const Options = require('./options');
const exit = require('../vendor/exit');

/**
 * @type {Options}
 */
const options = Options.compute(process.argv);

module.exports = {
  // ACCESS
  getOptions,
  getFileFromMemoryCache,
  filesProposedByCurrentFix,

  // Messages
  initializedApp,
  subscribe,
  exitRequested,
  filesWereUpdated,
  readmeChanged,
  buildRestarted,
  requestReview,
  reviewFinished,
  writingToFileSystemCacheStarted,
  writingToFileSystemCacheFinished,
  fixProposalReceived,
  fixWasAccepted,
  fixWasRefused
};

// MODEL

/**
 * @type { Model }
 */
const model = {
  // NOTE: elmFilesCacheForWatch sometimes gets mutated in watch.js
  elmFilesCacheForWatch: new Map(),
  reviewState: {
    type: 'idle'
  },
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

/**
 * Update the state of the application.
 * @param { Msg } message - What happened
 * @returns { Model }
 */
function update(message) {
  switch (message.$) {
    case 'initializedApp': {
      model.appUnsubscribeFunctions.forEach((unsubscribeFunction) =>
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
        exit(message.exitCode);
      }

      model.exitRequest = {
        requested: true,
        exitCode: message.exitCode
      };
      return model;
    }

    case 'writingToFileSystemCacheStarted': {
      model.filesBeingWrittenToCache.add(message.fileId);
      return model;
    }

    case 'writingToFileSystemCacheFinished': {
      model.filesBeingWrittenToCache.delete(message.fileId);

      if (
        model.filesBeingWrittenToCache.size === 0 &&
        model.exitRequest.requested
      ) {
        exit(model.exitRequest.exitCode);
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

    case 'buildRestarted': {
      model.reviewState = {type: 'waiting-for-first-report'};
      return model;
    }

    case 'reviewRequested': {
      switch (model.reviewState.type) {
        case 'idle': {
          model.reviewState = {type: 'ongoing', shouldRunAfterNewReview: false};
          break;
        }

        case 'ongoing': {
          model.reviewState = {
            type: 'ongoing',
            shouldRunAfterNewReview: true
          };
          break;
        }

        case 'waiting-for-first-report': {
          // Stay like this
          break;
        }

        default: {
          break;
        }
      }

      return model;
    }

    case 'reviewFinished': {
      return markReviewAsComplete();
    }

    case 'fixProposalReceived': {
      model.filesProposedByCurrentFix = message.changedFiles;
      return markReviewAsComplete();
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

/**
 * @returns {Model}
 */
function markReviewAsComplete() {
  switch (model.reviewState.type) {
    case 'waiting-for-first-report': {
      model.reviewState = {type: 'idle'};
      return model;
    }

    case 'ongoing': {
      if (model.reviewState.shouldRunAfterNewReview) {
        model.reviewState = {
          type: 'ongoing',
          shouldRunAfterNewReview: false
        };
      } else {
        model.reviewState = {type: 'idle'};
      }

      return model;
    }

    default: {
      return model;
    }
  }
}

/**
 * @param {ElmFile[]} files
 * @returns {void}
 */
function updateFilesInCache(files) {
  files.forEach((file) => {
    if (file.path.endsWith('.elm')) {
      model.elmFilesCacheForWatch.set(file.path, {
        path: file.path,
        source: file.source,
        ast: file.ast,
        lastUpdatedTime: file.lastUpdatedTime
      });
    }
  });
}

// ACCESS

/** @returns {Options} */
function getOptions() {
  return options;
}

/**
 * @param {Path} filePath
 * @returns {ElmFile | undefined}
 */
function getFileFromMemoryCache(filePath) {
  return model.elmFilesCacheForWatch.get(filePath);
}

function filesProposedByCurrentFix() {
  return model.filesProposedByCurrentFix;
}

// MESSAGES

function initializedApp() {
  return update({
    $: 'initializedApp'
  });
}

/**
 * @param {{subscribe: SubscribePort, unsubscribe: (fn: function) => void}} port
 * @param {function} subscriptionFunction
 * @returns {Model}
 */
function subscribe(port, subscriptionFunction) {
  port.subscribe(subscriptionFunction);

  return update({
    $: 'subscribe',
    unsubscribeFunction: () => port.unsubscribe(subscriptionFunction)
  });
}

/**
 * @param {0 | 1} exitCode
 * @returns {Model}
 */
function exitRequested(exitCode) {
  return update({
    $: 'exitRequested',
    exitCode
  });
}

/**
 * @param {ElmFile[]} files
 * @returns {Model}
 */
function filesWereUpdated(files) {
  return update({
    $: 'filesWereUpdated',
    files
  });
}

/**
 * @param {Readme | null} readme
 * @returns {boolean}
 */
function readmeChanged(readme) {
  const hasChanged = model.readme
    ? !readme || readme.content !== model.readme.content
    : Boolean(readme);

  update({
    $: 'readmeChanged',
    readme
  });

  return hasChanged;
}

function buildRestarted() {
  return update({
    $: 'buildRestarted'
  });
}

function requestReview() {
  let canRunReview = null;
  switch (model.reviewState.type) {
    case 'idle': {
      canRunReview = true;
      break;
    }

    case 'ongoing': {
      canRunReview = false;
      break;
    }

    case 'waiting-for-first-report': {
      canRunReview = false;
      break;
    }

    default: {
      canRunReview = true;
      break;
    }
  }

  update({
    $: 'reviewRequested'
  });

  return canRunReview;
}

/**
 * @returns {boolean}
 */
function reviewFinished() {
  update({
    $: 'reviewFinished'
  });
  const shouldReReview = model.reviewState.type === 'ongoing';
  return shouldReReview;
}

/**
 * @param {FileId} fileId
 * @returns {Model}
 */
function writingToFileSystemCacheStarted(fileId) {
  return update({
    $: 'writingToFileSystemCacheStarted',
    fileId
  });
}

/**
 * @param {FileId} fileId
 * @returns {Model}
 */
function writingToFileSystemCacheFinished(fileId) {
  return update({
    $: 'writingToFileSystemCacheFinished',
    fileId
  });
}

/**
 * @param {FilesProposedByCurrentFix} changedFiles
 * @returns {boolean}
 */
function fixProposalReceived(changedFiles) {
  update({
    $: 'fixProposalReceived',
    changedFiles
  });

  const shouldReReview = model.reviewState.type === 'ongoing';
  return shouldReReview;
}

function fixWasAccepted() {
  return update({
    $: 'fixWasAccepted'
  });
}

function fixWasRefused() {
  return update({
    $: 'fixWasRefused'
  });
}
