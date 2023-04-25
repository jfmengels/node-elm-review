
import type { Options } from "./types/options"
import type { Path } from "./types/path"
import type { FilesProposedByCurrentFix } from "./types/state"
import type { Ast, ElmFile, Readme, ElmJson, Dependencies, LinksToRuleDocs } from "./types/content"
import type { SuppressedErrorsFile } from "./types/suppressed"

export type App = {
  ports: Ports
}

export type Ports = {
  collectElmJson: SendPort<ElmJson>,
  collectReadme: SendPort<Readme>,
  collectDependencies: SendPort<Dependencies>,
  collectFile: SendPort<ElmFile>,
  collectSuppressedErrors: SendPort<SuppressedErrorsFile[]>,
  collectLinks: SendPort<LinksToRuleDocs>,
  userConfirmedFix: SendPort<FixConfirmation>,

  acknowledgeFileReceipt: SubscribePort<FileReceipt>,
  askConfirmationToFix: SubscribePort<AutofixRequest>,
}

export type FileReceipt = {
  path: Path,
  cacheRequest: { source: string, ast: Ast } | null
}

export type AutofixRequest = {
  confirmationMessage: any,
  clearFixLine: boolean,
  changedFiles: any,
  count: number
}

export type FixConfirmation
  = { answer: false }
  | { answer: true, files: FilesProposedByCurrentFix, dependencies: Dependencies }

export type SubscribePort = function;
export type SendPort<T> = { send: (data: T) => void };