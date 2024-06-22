import type {Path} from './path';

export type SuppressedErrorsFile = {
  rule: string;
  suppressions: Suppression[];
};

export type Suppression = {
  count: number;
  filePath: Path;
};
