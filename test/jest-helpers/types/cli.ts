import type {ReportMode} from '../../../lib/types/options.js';

export type Options = {
  project?: string;
  cwd?: string;
  report?: ReportMode;
  colors?: boolean;
};
