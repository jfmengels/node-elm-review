import type {ElmFile, Readme, Source, Ast} from './content';
import type {Path} from './path';

export type Model = {
  elmFilesCacheForWatch: Map<Path, ElmFile>;
  reviewState: ReviewState;
  readme: Readme | null;
  filesBeingWrittenToCache: Set;
  exitRequest: ExitRequest;
  appUnsubscribeFunctions: AppUnsubscribeFunctions;
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

export type AppUnsubscribeFunctions = Array<function>;

export type FilesProposedByCurrentFix = Array<{path: Path; source: Source}>;

export type Msg = any;
