import type {ChildProcess, SpawnOptions} from 'node:child_process';
import type {ReportMode} from '../../lib/types/options';
import type {Path} from '../../lib/types/path';
import type {Source} from '../../lib/types/content';

export type CompileOptions = {
  spawn?: Spawner;

  cwd: Path;
  output: Path;
  debug: boolean;
  optimize: boolean;
  verbose: boolean;
  warn: boolean;
  report: ReportMode;
  pathToElm: Path;
  help?: undefined;
  docs?: undefined;
  processOpts: ProcessOptions;
};

export interface ProcessOptions {
  env: NodeJS.ProcessEnv;
  stdio: ('ignore' | 'inherit' | 'pipe')[];
}

export type Spawner = (
  pathToElm: Path,
  processArgs: SpawnOptions,
  processOpts: ProcessOptions
) => ChildProcess;

export type Sources = Source | Source[];
