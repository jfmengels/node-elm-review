import {Path} from './path';
import {ElmFile, Source} from './content';

export type ParseJob = {
  elmParserPath: Path;
  source: Source;
  callback: callback;
};

export function callback(error: Err): void;
export function callback(error: undefined, result: ElmFile): void;
