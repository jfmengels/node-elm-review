import type {ReviewApp} from './app.ts';
import type {ElmFile, ElmJsonData, ExtraFileRequest} from './content.ts';
import type {VersionString} from './version.js';

export type RunOptions = {
  app: ReviewApp;
  elmVersion: VersionString;
  elmJsonData: ElmJsonData;
  elmFiles: ElmFile[];
  sourceDirectories: string[];
  requestedExtraFiles: ExtraFileRequest[];
};
