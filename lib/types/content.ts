import type {VersionRange, VersionString} from './version.ts';
import type {Path} from './path.ts';

export type File = {
  path: Path;
  source: Source;
};

export type ElmFile = {
  path: Path;
  source: Source;
  ast?: Ast | null;
  lastUpdatedTime?: Date | null;
};

export type NonElmFile = {
  path: Path;
  content: string;
};

export type NonElmFiles = Record<string, string>;

export type Readme = NonElmFile;

export type ElmJsonData = {
  path: Path;
  raw: string;
  project: ElmJson;
};

export type ElmJson = ApplicationElmJson | PackageElmJson;

export type ApplicationElmJson = {
  type: 'application';
  'elm-version': VersionString;
  'source-directories': Path[];
  dependencies: ApplicationDependencies;
  'test-dependencies': ApplicationDependencies;
};

export type ApplicationDependencies = {
  direct: ApplicationDependencyList;
  indirect: ApplicationDependencyList;
};

export type ApplicationDependencyList = Record<PackageName, VersionString>;
export type PackageDependencyList = Record<PackageName, VersionRange>;

export type PackageName = `${string}/${string}`;

export type PackageElmJson = {
  type: 'package';
  name: PackageName;
  summary: string;
  license: string;
  version: VersionString;
  'exposed-modules': string[] | Record<string, string[]>;
  'elm-version': VersionRange;
  dependencies: PackageDependencyList;
  'test-dependencies': PackageDependencyList;
};

export type SourceDirectories = Path[];

export type ExtraFileRequest = {
  files: {pattern: string; included: boolean}[];
  excludedDirectories: string[];
};

export type ProjectFiles = {
  elmJsonData: ElmJsonData;
  readme: Readme | null;
  elmFiles: ElmFile[];
  sourceDirectories: Path[];
};

export type Dependencies = Dependency[];

export type Dependency = {
  name: PackageName;
  docsJson: unknown;
  elmJson: PackageElmJson;
};

export type LinksToRuleDocs = Record<string, string>;

export type Source = Path;

export type Ast = Record<string, unknown>;
