
/**
 * @typedef { import("./types/options.d.ts").Options } Options
 * @typedef { import("./types/content").ElmFile } ElmFile
 * @typedef { import("./types/content").Ast } Ast
 * @typedef { import("./types/content").Readme } Readme
 * @typedef { import("./types/content").ElmJson } ElmJson
 * @typedef { import("./types/content").Dependencies } Dependencies
 * @typedef { import("./types/content").LinksToRuleDocs } LinksToRuleDocs
 * @typedef { import("./types/suppressed").SuppressedErrorsFile } SuppressedErrorsFile
 */

import { ElmFile, ElmJson } from "./content"
import { SuppressedErrorsFile } from "./suppressed"

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

  acknowledgeFileReceipt: SubscribePort<FileReceipt>
}

export type FileReceipt = {
  path: Path,
  cacheRequest: { source: string, ast: Ast } | null
}

export type SubscribePort = function;
export type SendPort<T> = { send: (T) => void };