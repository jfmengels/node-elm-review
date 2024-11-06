#!/usr/bin/env node

/**
 * @import {Listened, SubscribePort} from './types/promisify-port';
 * @import {Path} from './types/path';
 * @import {Model, Msg} from './types/state';
 * @import {FileId, FilesProposedByCurrentFix} from './types/state';
 * @import {ElmFile, Readme} from './types/content';
 * @import {Options} from './types/options';
 */
const exit = require('../vendor/exit');
const options_ = require('./options');

/**
 * @type {Options}
 */
const options = options_.compute(process.argv);

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
 *
 * @param {Msg} message - What happened
 * @returns {Model | never}
 */
function update(message) {
  switch (message.$) {
    case 'initializedApp': {
      for (const unsubscribeFunction of model.appUnsubscribeFunctions)
        unsubscribeFunction();
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
      model.reviewState = model.reviewState.shouldRunAfterNewReview
        ? {
            type: 'ongoing',
            shouldRunAfterNewReview: false
          }
        : {type: 'idle'};

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
  for (const file of files) {
    if (file.path.endsWith('.elm')) {
      model.elmFilesCacheForWatch.set(file.path, {
        path: file.path,
        source: file.source,
        ast: file.ast,
        lastUpdatedTime: file.lastUpdatedTime
      });
    }
  }
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

/**
 * @returns {FilesProposedByCurrentFix}
 */
function filesProposedByCurrentFix() {
  return model.filesProposedByCurrentFix;
}

// MESSAGES

/** @returns {Model | never} */
function initializedApp() {
  return update({
    $: 'initializedApp'
  });
}

/**
 * @template T
 * @param {SubscribePort<T>} port
 * @param {Listened<T>} subscriptionFunction
 * @returns {Model | never}
 */
function subscribe(port, subscriptionFunction) {
  port.subscribe(subscriptionFunction);

  return update({
    $: 'subscribe',
    unsubscribeFunction: () => {
      port.unsubscribe(subscriptionFunction);
    }
  });
}

/**
 * @param {0 | 1} exitCode
 * @returns {Model | never}
 */
function exitRequested(exitCode) {
  return update({
    $: 'exitRequested',
    exitCode
  });
}

/**
 * @param {ElmFile[]} files
 * @returns {Model | never}
 */
function filesWereUpdated(files) {
  return update({
    $: 'filesWereUpdated',
    files
  });
}

/**
 * @param {Readme | null} readme
 * @returns {boolean | never}
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

/** @returns {Model | never} */
function buildRestarted() {
  return update({
    $: 'buildRestarted'
  });
}

/** @returns {boolean | never} */
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

/** @returns {boolean | never} */
function reviewFinished() {
  update({
    $: 'reviewFinished'
  });
  const shouldReReview = model.reviewState.type === 'ongoing';
  return shouldReReview;
}

/**
 * @param {FileId} fileId
 * @returns {Model | never}
 */
function writingToFileSystemCacheStarted(fileId) {
  return update({
    $: 'writingToFileSystemCacheStarted',
    fileId
  });
}

/**
 * @param {FileId} fileId
 * @returns {Model | never}
 */
function writingToFileSystemCacheFinished(fileId) {
  return update({
    $: 'writingToFileSystemCacheFinished',
    fileId
  });
}

/**
 * @param {FilesProposedByCurrentFix} changedFiles
 * @returns {boolean | never}
 */
function fixProposalReceived(changedFiles) {
  update({
    $: 'fixProposalReceived',
    changedFiles
  });

  const shouldReReview = model.reviewState.type === 'ongoing';
  return shouldReReview;
}

/** @returns {Model | never} */
function fixWasAccepted() {
  return update({
    $: 'fixWasAccepted'
  });
}

/** @returns {Model | never} */
function fixWasRefused() {
  return update({
    $: 'fixWasRefused'
  });
}

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
