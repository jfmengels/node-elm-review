import type {FixMode} from './fix.js';
import type {OptionsBase} from './options.js';

export type Flags = OptionsBase & {
  resultCacheFolder: string;
  fixMode: FixMode;
  fixLimit: number | null;
  directoriesToAnalyze: string[];
  ignoredDirs: string[];
  ignoredFiles: string[];
  writeSuppressionFiles: boolean;
  logger?: unknown;
};
