import type {Chalk} from 'chalk';

export type Section =
  | 'regular'
  | 'suppress'
  | 'fix'
  | 'init'
  | 'new-rule'
  | 'new-package'
  | 'suppress-subcommand';

export type Flag = {
  name: string;
  alias?: string;
  description: string[];
  initDescription?: string[];
  newPackageDescription?: string[];
} & BooleanFlag &
  DisplayableFlag;

export type DisplayableFlag =
  | {sections?: null}
  | {
      color: Chalk;
      sections: Section[];
    };

export type BooleanFlag =
  | {
      boolean: true;
      mayBeUsedSeveralTimes?: false;
    }
  | {
      boolean: false;
      argName: string;
      mayBeUsedSeveralTimes: boolean;
      usesEquals: boolean;
    };
