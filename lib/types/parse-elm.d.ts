import {Path} from './path';
import {ElmFile, Source} from './content';
import {SendPort, SubscribePort} from './app';

export type ParseJob = {
  elmParserPath: Path;
  source: Source;
  callback: callback;
};

export function callback(error: Err): void;
export function callback(error: undefined, result: ElmFile): void;

export type ParserApp = {
  ports: ParserPorts;
};

type ParserPorts = {
  requestParsing: SendPort<ElmJson>;
  parseResult: SubscribePort<ElmFile>;
};
