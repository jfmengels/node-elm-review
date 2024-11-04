import type {FixMode} from './fix.ts';
import type {OptionsBase} from './options.ts';

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
