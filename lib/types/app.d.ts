import type {Path} from './types/path';
import type {FilesProposedByCurrentFix} from './types/state';
import type {
  Ast,
  ElmFile,
  Readme,
  ElmJson,
  Dependencies,
  LinksToRuleDocs
} from './types/content';
import type {SuppressedErrorsFile} from './types/suppressed';

export type App = {
  ports: Ports;
};

export type Ports = {
  collectElmJson: SendPort<ElmJson>;
  collectReadme: SendPort<Readme>;
  collectDependencies: SendPort<Dependencies>;
  collectFile: SendPort<ElmFile>;
  removeFile: SendPort<Path>;
  collectSuppressedErrors: SendPort<SuppressedErrorsFile[]>;
  updateSuppressedErrors: SendPort<SuppressedErrorsFile[]>;
  collectLinks: SendPort<LinksToRuleDocs>;
  userConfirmedFix: SendPort<FixConfirmation>;

  acknowledgeFileReceipt: SubscribePort<FileReceipt>;
  askConfirmationToFix: SubscribePort<AutofixRequest>;
};

export type FileReceipt = {
  path: Path;
  cacheRequest: {source: string; ast: Ast} | null;
};

export type AutofixRequest = {
  confirmationMessage: unknown;
  clearFixLine: boolean;
  changedFiles: unknown;
  count: number;
};

export type FixConfirmation =
  | {answer: false}
  | {
      answer: true;
      files: FilesProposedByCurrentFix;
      dependencies: Dependencies;
    };

export type SubscribePort = function;
export type SendPort<T> = {send: (data: T) => void};
