import type {ChildProcess} from "@types/node/child_process";

export type Pid = number;

export type SpawnResult = {
  spawned: ChildProcess;
  stdout: string | null;
  stderr: string | null;
};

export type Completed = CompletedData | CompletedError;

export type CompletedData = {
  pid: Pid;
  exitCode: number;
  stdout: string | null;
  stderr: string | null;
};

export type CompletedError = {
  error: {
    code: "ProcessError",
    data: string;
  };
};