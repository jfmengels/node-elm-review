import type {ApplicationElmJson} from './content.ts';
import type {Path} from './path.ts';
import type {RunOptions} from './runner.ts';

export type WatchOptions = RunOptions & {
  reviewElmJson: ApplicationElmJson;
  reviewElmJsonPath: Path | null;
};
