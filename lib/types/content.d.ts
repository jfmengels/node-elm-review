import type { Path } from './path';

export type ElmFile = {
  path: Path,
  source: Source,
  ast: Ast | null,
  lastUpdatedTime?: Date
}

export type Ast = object;

export type Readme = {
  path: Path,
  content: string
}

export type ElmJson = {};

export type Dependencies = Dependency[];

export type Dependency = {};

export type LinksToRuleDocs = { [string]: string };