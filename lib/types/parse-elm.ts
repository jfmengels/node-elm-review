import type {Ast, ElmFile, Source} from './content.ts';
import type {Path} from './path.ts';
import type {SendPort, SubscribePort} from './promisify-port.ts';

export type ParseJob = {
  elmParserPath: Path;
  source: Source;

  callback: {
    (error: Error): void;
    (error: undefined, result: Ast): void;
  };
};

export type ParserApp = {
  ports: ParserPorts;
};

type ParserPorts = {
  requestParsing: SendPort<string>;
  parseResult: SubscribePort<ElmFile>;
};
