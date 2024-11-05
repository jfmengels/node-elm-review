import type {MessagePort} from 'node:worker_threads';

export type WorkerData = {
  sharedLock: SharedArrayBuffer;
  requestPort: MessagePort;
};
