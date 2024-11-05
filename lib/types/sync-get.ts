import type {MessagePort} from 'node:worker_threads';
import type {Result} from './core.ts';

export type WorkerData = {
  sharedLock: SharedArrayBuffer;
  requestPort: MessagePort;
};

export type PortResponse = Result<unknown, string>;
