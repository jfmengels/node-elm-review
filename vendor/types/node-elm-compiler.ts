import type {MessagePort} from 'worker_threads';
import type {ReportMode} from '../../lib/types/options';

export type CompileOptions = {
  spawn?: Spawner;

  cwd: string;
  output: string;
  debug: boolean;
  optimize: boolean;
  verbose: boolean;
  warn: boolean;
  report: ReportMode;
  pathToElm: string;
  help?: undefined;
  docs?: undefined;
  processOpts: ProcessOptions;
};

export interface ProcessOptions {
  env: NodeJS.ProcessEnv;
  stdio: ('ignore' | 'inherit' | 'pipe')[];
}

export type Spawner = (
  pathToElm: string,
  processArgs: string[],
  processOpts: ProcessOptions
) => NodeJS.Process;

export type Sources = string | string[];
