import type { Path } from './path';

export type ElmFile = {
  path: Path,
  source: Source,
  ast: Ast | null,
  lastUpdatedTime?: Date | null
}

export type Ast = any;

export type Readme = {
  path: Path,
  content: string
}

export type ElmJson = {};

export type Dependencies = Dependency[];

export type Dependency = {};

export type LinksToRuleDocs = { [string]: string };

export type Source = string;

export type Ast = any;