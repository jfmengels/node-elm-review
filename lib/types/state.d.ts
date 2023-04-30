import type {ElmFile, Readme, Source} from './content';
import type {Path} from './path';
import type from './state-type.js';

export type Model = {
  elmFilesCacheForWatch: Map<Path, ElmFile>;
  reviewState: ReviewState;
  readme: Readme | null;
  filesBeingWrittenToCache: Set<FileId>;
  exitRequest: ExitRequest;
  appUnsubscribeFunctions: Array<AppUnsubscribeFunction>;
  filesProposedByCurrentFix: FilesProposedByCurrentFix;
};

export type ReviewState =
  | {type: 'idle'}
  | {type: 'ongoing'; shouldRunAfterNewReview: boolean}
  | {type: 'waiting-for-first-report'};

export type ExitRequest = {
  requested: boolean;
  exitCode: 1;
};

export type AppUnsubscribeFunction = function;

export type FilesProposedByCurrentFix = Array<{path: Path; source: Source}>;

export type FileId = string;

export type Msg =
  | {[type]: 'initializedApp'}
  | {[type]: 'subscribe'; unsubscribeFunction: AppUnsubscribeFunction}
  | {[type]: 'exitRequested'; exitCode: number}
  | {[type]: 'writingToFileSystemCacheStarted'; fileId: FileId}
  | {[type]: 'writingToFileSystemCacheFinished'; fileId: FileId}
  | {[type]: 'filesWereUpdated'; files: ElmFile[]}
  | {[type]: 'readmeChanged'; readme: Readme | null}
  | {[type]: 'buildRestarted'}
  | {[type]: 'reviewRequested'}
  | {[type]: 'reviewFinished'}
  | {[type]: 'fixProposalReceived'; changedFiles: FilesProposedByCurrentFix}
  | {[type]: 'fixWasAccepted'}
  | {[type]: 'fixWasRefused'};
