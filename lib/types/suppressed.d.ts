import type {Path} from './path';

export type SuppressedErrorsFile = {
  version: number;
  rule: string;
  suppressions: Suppression[];
};

export type Suppression = {
  count: number;
  filePath: Path;
};
