import type {Path} from './path';

export type Options = {
  debug: boolean;
  showBenchmark: boolean;
  forTests: boolean;
  enableExtract: boolean;
  version: boolean;
  help: boolean;
  fix: boolean;
  fixLimit: number | undefined;
  fixAll: boolean;
  fixAllWithoutPrompt: boolean;
  fixMode?: 'fix' | 'fixAll' | 'dontfix';
  unsuppress: boolean | Array<string>;
  suppressCheckAfterTests: boolean;
  detailsMode: DetailsMode;
  watch: boolean;
  watchConfig: boolean;
  color: boolean;
  subcommand: Subcommand | null;
  namespace: string;
  compiler: string | undefined;
  elmFormatPath: string | undefined;
  packageJsonVersion: string;
  localElmReviewSrc: string | undefined;
  forceBuild: boolean;
  offline: boolean;
  report: ReportMode;
  reportOnOneLine: boolean;
  rulesFilter: string[] | null;
  ignoredDirs: () => string[];
  ignoredFiles: () => string[];
  ignoreProblematicDependencies: boolean;
  prefilledAnswers: NewPackagePrefilledAnswers;

  newRuleName: string | null;
  ruleType: RuleType | undefined;

  userSrc: () => Path;
  usedConfig: boolean;
  template: Template | null;
  initPath: () => Path;
  suppressedErrorsFolder: () => Path;
  buildFolder: () => Path;
  buildFolderForParserApp: () => Path;
  elmModulePath: (appHash: string) => Path;
  elmParserPath: (elmSyntaxVersion: string) => Path;
  generatedCodePackageJson: () => Path;
  templateElmModulePath: (commit: string) => Path;
  pathToTemplateElmJson: (commit: string) => Path;
  elmJsonPathWasSpecified: boolean;
  elmJsonPath: Path | null;
  readmePath: Path | null;
  projectToReview: () => Path;
  directoriesToAnalyze: Path[];
  fileCachePath: () => Path;
  resultCachePath: (string) => Path;
  resultCacheFolder?: string;

  gitHubUser: string | undefined;
  gitHubPassword: string | undefined;

  writeSuppressionFiles?: boolean;
};

export type ReviewOptions = Options & {
  elmJsonPath: Path;
  readmePath: Path;
};

export type DetailsMode = 'without-details' | 'with-details';

export type ReportMode = 'json' | 'human' | null;

export type NewPackagePrefilledAnswers = {
  authorName: string | undefined;
  packageName: string | undefined;
  license: string | undefined;
};

export type RuleType = 'module' | 'project';

export type Template = {
  repoName: string;
  pathToFolder: Path | null;
  reference: string | null;
};

export type Subcommand =
  | 'init'
  | 'new-package'
  | 'new-rule'
  | 'suppress'
  | 'prepare-offline';
