import type {
  Ast,
  Dependencies,
  ElmFile,
  ElmJsonData,
  LinksToRuleDocs,
  NonElmFiles,
  Readme,
  Source
} from './content.js';
import type {Flags} from './flags.js';
import type {Path} from './path.js';
import type {SendPort, SubscribePort} from './promisify-port.js';
import type {FilesProposedByCurrentFix} from './state.js';
import type {StyledMessage} from './styled-message.js';
import type {SuppressedErrorsFile} from './suppressed.js';

export type Elm = {
  Elm: {
    Elm: {
      Review: {
        Main: {
          init: (flags: {flags: Flags}) => App;
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
  collectElmJson: SendPort<ElmJsonData>;
  collectReadme: SendPort<Readme>;
  collectDependencies: SendPort<Dependencies>;
  collectFile: SendPort<ElmFile>;
  removeFile: SendPort<Path>;
  collectSuppressedErrors: SendPort<SuppressedErrorsFile[]>;
  updateSuppressedErrors: SendPort<SuppressedErrorsFile[]>;
  collectLinks: SendPort<LinksToRuleDocs>;
  collectExtraFiles: SendPort<NonElmFiles>;
  userConfirmedFix: SendPort<FixConfirmation>;

  startGeneratingSuppressions: SendPort<null>;
  suppressionsResponse: SubscribePort<SuppressedErrorsFile[]>;

  startReview: SendPort<null>;
  reviewReport: SubscribePort<{
    suppressedErrors: SuppressedErrorsFile[];
    success: boolean;
  }>;

  acknowledgeFileReceipt: SubscribePort<FileReceipt>;
  askConfirmationToFix: SubscribePort<AutofixRequest>;
  cacheFile: SubscribePort<CacheRequest>;
  fixConfirmationStatus: SubscribePort<boolean>;
  askForFixConfirmationStatus: SendPort<null>;
  abort: SubscribePort<string>;
  abortWithDetails: SubscribePort<{title: string; message: string}>;
  abortForConfigurationErrors: SubscribePort<
    {errors: unknown[]; path: unknown}[] & StyledMessage
  >;
};

export type FileReceipt = {
  path: Path;
  cacheRequest: CacheRequest | null;
};

export type CacheRequest = {source: Source; ast: Ast};

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
      dependencies: Dependencies | undefined;
    };
