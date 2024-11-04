import type {ApplicationElmJson} from './content.ts';
import type {Path} from './path.ts';

export type BuildResult = {
  elmModulePath: Path | null;
  reviewElmJsonPath: Path | null;
  reviewElmJson: ApplicationElmJson;
  appHash: AppHash;
};

export type AppHash = string;
