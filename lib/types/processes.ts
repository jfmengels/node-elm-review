import type {ChildProcess} from "@types/node/child_process";

export type Pid = number;

export type SpawnResult = {
  spawned: ChildProcess;
  stdout: string | null;
  stderr: string | null;
};