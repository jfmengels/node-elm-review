export type Flags = {
  args: string[];
  env: NodeJS.ProcessEnv;
  logger?: unknown;
};

export type ElmCommunicationFlags = {
  debug: boolean;
  showBenchmark: boolean;
};

