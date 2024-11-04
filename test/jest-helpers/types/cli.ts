import type {ReportMode} from '../../../lib/types/options.ts';

export type Options = {
  project?: string;
  cwd?: string;
  report?: ReportMode;
  colors?: boolean;
};
