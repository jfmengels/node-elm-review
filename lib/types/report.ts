import type {StyledMessagePart} from './styled-message.ts';
import type {SuppressedErrorsFile} from './suppressed.ts';

export type ReportedError = StyledMessagePart & {
  errors: object[];
  path: unknown;
  extracts?: unknown;
};

export type Report = {
  errors?: ReportedError[];
  extracts?: unknown;
  suppressedErrors?: SuppressedErrorsFile[];
};
