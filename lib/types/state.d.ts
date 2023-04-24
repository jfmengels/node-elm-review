export type Model = {
  elmFilesCacheForWatch: Map<FilePath, FileInCache>,
  reviewState: ReviewState,
  readme: Readme | null,
  filesBeingWrittenToCache: Set,
  exitRequest: ExitRequest,
  appUnsubscribeFunctions: AppUnsubscribeFunctions,
  filesProposedByCurrentFix: FilesProposedByCurrentFix
}

// TODO Simplify this to an enum
export type ReviewState
  = { type: 'idle' }
  | { type: 'ongoing', shouldRunAfterNewReview: boolean }
  | { type: 'waiting-for-first-report' }

export type FileInCache = {
  path: FilePath,
  source: Source,
  ast?: Ast,
  lastUpdatedTime?: Date
}

export type ExitRequest = {
  requested: boolean,
  exitCode: 1
};

export type AppUnsubscribeFunctions = Array<function>;

export type FilesProposedByCurrentFix = Array<FileId>;

export type FilePath = string;

export type FileId = string;

export type Source = string;

export type Ast = any;

export type Readme = {
  path: FilePath,
  content: string
}