import type {Chalk} from 'chalk';

export type Section =
  | 'regular'
  | 'suppress'
  | 'fix'
  | 'init'
  | 'new-rule'
  | 'new-package'
  | 'hidden'
  | 'suppress-subcommand';

export type Flag = {
  name: string;
  alias?: string;
  color?: Chalk;
  sections: Section[];
  description: string[];
  initDescription?: string[];
  newPackageDescription?: string[];
} & BooleanFlag;

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
