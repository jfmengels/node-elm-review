import {ElmFile, Source, type ElmJson} from './content.js';
import {Path} from './path.js';
import type {SendPort, SubscribePort} from './promisify-port.js';

export type ParseJob = {
  elmParserPath: Path;
  source: Source;
  callback: callback;
};

interface callback {
  (error: Error): void;
  (error: undefined, result: ElmFile): void;
}

export type ParserApp = {
  ports: ParserPorts;
};

type ParserPorts = {
  requestParsing: SendPort<ElmJson>;
  parseResult: SubscribePort<ElmFile>;
};
