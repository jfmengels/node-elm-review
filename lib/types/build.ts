import type {ApplicationElmJson} from './content.js';
import type {Path} from './path.js';

export type BuildResult = {
  elmModulePath: Path | null;
  reviewElmJsonPath: Path | null;
  reviewElmJson: ApplicationElmJson;
  appHash: AppHash;
};

export type AppHash = string;
