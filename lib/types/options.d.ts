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
  unsuppress: boolean;
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
  rulesFilter: string[];
  ignoredDirs: string[];
  ignoredFiles: string[];
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
  elmModulePath: (string) => Path;
  elmParserPath: (string) => Path;
  generatedCodePackageJson: () => Path;
  templateElmModulePath: (string) => Path;
  pathToTemplateElmJson: (string) => Path;
  dependenciesCachePath: (string) => Path;
  elmJsonPath: Path;
  elmJsonPathWasSpecified: boolean;
  readmePath: Path;
  projectToReview: () => Path;
  directoriesToAnalyze: Path[];
  fileCachePath: () => Path;
  resultCachePath: (string) => Path;

  gitHubUser: string | undefined;
  gitHubPassword: string | undefined;
};

export type DetailsMode = 'without-details' | 'with-details';

export type ReportMode = 'json' | null;

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

export type Subcommand = 'init' | 'new-package' | 'new-rule' | 'suppress';
