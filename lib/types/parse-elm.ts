import type {ElmApp, ElmNamespace} from './elm-js.js';
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

export type ParseElm = ElmNamespace<['ParseMain'], undefined, ParserApp>;

export type ParserApp = ElmApp<ParserPorts>;

type ParserPorts = {
  requestParsing: SendPort<string>;
  parseResult: SubscribePort<ElmFile>;
};
