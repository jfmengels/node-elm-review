import type {ReviewApp} from './app.ts';
import type {
  ApplicationElmJson,
  ElmFile,
  ElmJsonData,
  ExtraFileRequest
} from './content.ts';
import type {Path} from './path.ts';

export type WatchOptions = {
  app: ReviewApp;
  elmJsonData: ElmJsonData;
  elmFiles: ElmFile[];
  sourceDirectories: Path[];
  reviewElmJson: ApplicationElmJson;
  reviewElmJsonPath: Path | null;
  requestedExtraFiles: ExtraFileRequest[];
};
