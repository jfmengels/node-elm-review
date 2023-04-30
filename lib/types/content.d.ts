import type {Path} from './path';

export type File = {
  path: Path;
  source: Source;
};

export type ElmFile = {
  path: Path;
  source: Source;
  ast: Ast | null;
  lastUpdatedTime?: Date | null;
};

export type Readme = {
  path: Path;
  content: string;
};

export type ElmJsonData = {
  path: Path;
  raw: string;
  project: unknown;
};

export type Dependencies = Dependency[];

export type Dependency = unknown;

export type LinksToRuleDocs = {[string]: string};

export type Source = string;

export type Ast = unknown;
