import type {PortFromElm, PortToElm} from './promisify-port';

export type Ports<T, U> = PortToElm<T> & PortFromElm<U>;

export type Exports = {
  init: (options: Options, elmModulePath: string, flags: Options) => App;
  stop: () => void;
};
