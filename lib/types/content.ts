import type {ElmVersion} from './elm-version.js';
import type {Path} from './path.js';

export type File = {
  path: Path;
  source: Source;
};

export type ElmFile = {
  path: Path;
  source: Source;
  ast?: Ast;
  lastUpdatedTime?: Date | null;
};

export type NonElmFile = {
  path: Path;
  content: string;
};

export type NonElmFiles = {[x: string]: string};

export type Readme = NonElmFile;

export type ElmJsonData = {
  path: Path;
  raw: string;
  project: ElmJson;
};

export type ElmJson = ApplicationElmJson | PackageElmJson;

export type ApplicationElmJson = {
  type: 'application';
  'elm-version': ElmVersion;
  'source-directories': Path[];
  dependencies: ApplicationDependencies;
  'test-dependencies': ApplicationDependencies;
};

export type ApplicationDependencies = {
  direct: Record<string, string>;
  indirect: Record<string, string>;
};

export type PackageElmJson = {
  type: 'package';
};

export type SourceDirectories = Path[];

export type ExtraFileRequest = {
  files: {pattern: string; included: boolean}[];
  excludedDirectories: string[];
};

export type Dependencies = Dependency[];

export type Dependency = unknown;

export type LinksToRuleDocs = {[x: string]: string};

export type Source = string;

export type Ast = unknown;
