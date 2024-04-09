import type {App} from './app';
import type {Path} from './path';
import type {
  ApplicationElmJson,
  ElmFile,
  ElmJsonData,
  ExtraFileRequest
} from './content';

export type WatchOptions = {
  app: App;
  elmJsonData: ElmJsonData;
  elmFiles: ElmFile[];
  sourceDirectories: Path[];
  reviewElmJson: ApplicationElmJson;
  reviewElmJsonPath: Path;
  requestedExtraFiles: ExtraFileRequest[];
};
