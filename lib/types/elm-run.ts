import type {Path} from "../../lib/types/path";

export type ElmRunOptions = {
  cwd: Path;
  output: Path;
  target: Path;
  verbose: boolean;
  pathToElmRun: Path;
  processOpts: ElmRunProcessOptions;
};

export interface ElmRunProcessOptions {
  env: NodeJS.ProcessEnv;
  stdio: ("ignore" | "inherit" | "pipe")[];
}
