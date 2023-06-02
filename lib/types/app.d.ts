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
import type {SuppressedErrorsFile} from './suppressed';
import {ExtraFile} from './content';
import {StyledMessage} from './styled-message';

export type Elm = {
  Elm: {
    Elm: {
      Review: {
        Main: {
          init: (flags: Flags) => App;
        };
      };
    };
  };
};

export type App = {
  ports: Ports;
};

export type Ports = {
  requestReadingFiles: SubscribePort<string[]>;
  collectElmJson: SendPort<ElmJson>;
  collectReadme: SendPort<Readme>;
  collectDependencies: SendPort<Dependencies>;
  collectFile: SendPort<ElmFile>;
  removeFile: SendPort<Path>;
  collectSuppressedErrors: SendPort<SuppressedErrorsFile[]>;
  updateSuppressedErrors: SendPort<SuppressedErrorsFile[]>;
  collectLinks: SendPort<LinksToRuleDocs>;
  collectExtraFiles: SendPort<ExtraFile[]>;
  userConfirmedFix: SendPort<FixConfirmation>;

  startGeneratingSuppressions: SendPort<null>;
  suppressionsResponse: SubscribePort<unknown>;

  startReview: SendPort<null>;
  reviewReport: SubscribePort<unknown>;

  acknowledgeFileReceipt: SubscribePort<FileReceipt>;
  askConfirmationToFix: SubscribePort<AutofixRequest>;
  cacheFile: SubscribePort<unknown>;
  fixConfirmationStatus: SubscribePort<unknown>;
  abort: SubscribePort<unknown>;
  abortWithDetails: SubscribePort<unknown>;
  abortForConfigurationErrors: SubscribePort<unknown>;
};

export type FileReceipt = {
  path: Path;
  cacheRequest: {source: string; ast: Ast} | null;
};

export type AutofixRequest = {
  confirmationMessage: StyledMessage;
  clearFixLine: boolean;
  changedFiles: FilesProposedByCurrentFix;
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
