import type {Path} from './types/path';
import type {ElmVersion} from './types/elm-version';
import type {ApplicationDependencies, SourceDirectories} from "./content";

export type BuildResult = {
  elmModulePath: Path | null;
  reviewElmJsonPath: Path;
  reviewElmJson: ReviewElmJson;
  appHash: AppHash;
};

export type AppHash = string;

export type ReviewElmJson = {
  type: 'application';
  'elm-version': ElmVersion;
  'source-directories': SourceDirectories;
  dependencies: ApplicationDependencies;
  'test-dependencies': ApplicationDependencies;
};
