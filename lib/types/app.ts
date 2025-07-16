import type {
  Ast,
  Dependencies,
  ElmFile,
  ElmJsonData,
  LinksToRuleDocs,
  NonElmFiles,
  Readme,
  Source
} from './content.ts';
import type {ElmModule, ElmApp} from './elm-js.js';
import type {ErrorMessageInfo} from './error-message.ts';
import type {Flags} from './flags.ts';
import type {Path} from './path.ts';
import type {SendPort, SubscribePort} from './promisify-port.ts';
import type {ReportedError} from './report.ts';
import type {FilesProposedByCurrentFix} from './state.ts';
import type {StyledMessage} from './styled-message.ts';
import type {SuppressedErrorsFile} from './suppressed.ts';

export type ReviewModule = ElmModule<Ports, Flags, ['Elm', 'Review', 'Main']>;
export type ReviewApp = ElmApp<Ports>;

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
  abortWithDetails: SubscribePort<ErrorMessageInfo>;
  abortForConfigurationErrors: SubscribePort<ReportedError[]>;
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
  removedFiles: Path[];
};

export type FixConfirmation =
  | {answer: false}
  | {
      answer: true;
      files: FilesProposedByCurrentFix;
      dependencies: Dependencies | undefined;
    };
