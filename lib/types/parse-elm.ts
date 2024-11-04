import type {Ast, ElmFile, Source} from './content.js';
import type {Path} from './path.js';
import type {SendPort, SubscribePort} from './promisify-port.js';

export type ParseJob = {
  elmParserPath: Path;
  source: Source;
  callback: Callback;
};

type Callback = {
  (error: Error): void;
  (error: undefined, result: Ast): void;
};

export type ParserApp = {
  ports: ParserPorts;
};

type ParserPorts = {
  requestParsing: SendPort<string>;
  parseResult: SubscribePort<ElmFile>;
};
