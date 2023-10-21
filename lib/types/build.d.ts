import type {Path} from './types/path';
import type {ElmVersion} from './types/elm-version';

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
  'source-directories': Array<Path>;
  dependencies: ApplicationDependencies;
  'test-dependencies': ApplicationDependencies;
};

export type ApplicationDependencies = {
  direct: Record<string, string>;
  indirect: Record<string, string>;
};
