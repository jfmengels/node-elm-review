import type {ElmFile, File, Readme} from './content.ts';
import type {Path} from './path.ts';

export type Model = {
  elmFilesCacheForWatch: Map<Path, ElmFile>;
  reviewState: ReviewState;
  readme: Readme | null;
  filesBeingWrittenToCache: Set<FileId>;
  exitRequest: ExitRequest;
  appUnsubscribeFunctions: AppUnsubscribeFunction[];
  filesProposedByCurrentFix: FilesProposedByCurrentFix;
};

export type ReviewState =
  | {type: 'idle'}
  | {type: 'ongoing'; shouldRunAfterNewReview: boolean}
  | {type: 'waiting-for-first-report'};

export type ExitRequest = {
  requested: boolean;
  exitCode: 0 | 1;
};

export type AppUnsubscribeFunction = () => void;

export type FilesProposedByCurrentFix = File[];

export type FileId = string;

export type Msg =
  | {$: 'initializedApp'}
  | {$: 'subscribe'; unsubscribeFunction: AppUnsubscribeFunction}
  | {$: 'exitRequested'; exitCode: 0 | 1}
  | {$: 'writingToFileSystemCacheStarted'; fileId: FileId}
  | {$: 'writingToFileSystemCacheFinished'; fileId: FileId}
  | {$: 'filesWereUpdated'; files: ElmFile[]}
  | {$: 'readmeChanged'; readme: Readme | null}
  | {$: 'buildRestarted'}
  | {$: 'reviewRequested'}
  | {$: 'reviewFinished'}
  | {$: 'fixProposalReceived'; changedFiles: FilesProposedByCurrentFix}
  | {$: 'fixWasAccepted'}
  | {$: 'fixWasRefused'};
