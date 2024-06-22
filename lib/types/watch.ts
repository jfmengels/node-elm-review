import type {App} from './app.js';
import type {
  ApplicationElmJson,
  ElmFile,
  ElmJsonData,
  ExtraFileRequest
} from './content.js';
import type {Path} from './path.js';

export type WatchOptions = {
  app: App;
  elmJsonData: ElmJsonData;
  elmFiles: ElmFile[];
  sourceDirectories: Path[];
  reviewElmJson: ApplicationElmJson;
  reviewElmJsonPath: Path | null;
  requestedExtraFiles: ExtraFileRequest[];
};
