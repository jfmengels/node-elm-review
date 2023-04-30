import type {App} from './app';
import type {Path} from './path';
import type {ReviewElmJson} from './build';
import type {ElmFile, ElmJsonData} from './content';

export type WatchOptions = {
  app: App;
  elmJsonData: ElmJsonData;
  elmFiles: ElmFile[];
  sourceDirectories: Path[];
  reviewElmJson: ReviewElmJson;
  reviewElmJsonPath: Path;
};
