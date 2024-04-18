import type {Path} from './path';
import type {ApplicationElmJson} from './content';

export type BuildResult = {
  elmModulePath: Path | null;
  reviewElmJsonPath: Path;
  reviewElmJson: ApplicationElmJson;
  appHash: AppHash;
};

export type AppHash = string;
