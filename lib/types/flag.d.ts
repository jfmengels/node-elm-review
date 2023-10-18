import type {Chalk} from 'chalk';

export type Section =
  | 'regular'
  | 'suppress'
  | 'fix'
  | 'init'
  | 'new-rule'
  | 'new-package'
  | 'suppress-subcommand'
  | 'prepare-offline';

export type Flag = BaseFlag & SingleOrMulti & Display;

export type BaseFlag = {
  name: string;
  alias?: string;
};

type Display = {sections: null} | DisplayableFlag;

export type DisplayableFlag = {
  sections: Section[];
  color: Chalk;
  description: string[];
  initDescription?: string[];
  newPackageDescription?: string[];
};

export type SingleOrMulti = Single | Multi;

export type Single = {
  boolean: true;
};

export type Multi = {
  boolean: false;
  argName: string;
  mayBeUsedSeveralTimes: boolean;
  usesEquals: boolean;
};
