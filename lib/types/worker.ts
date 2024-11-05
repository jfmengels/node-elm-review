import type {MessagePort} from 'node:worker_threads';

/**
 * Defines the used shape of the `node:worker_threads` namespace export.
 */
export type WorkerThreads<WorkerData> = {
  parentPort: MessagePort | null;
  workerData: WorkerData;
};
