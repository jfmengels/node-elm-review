import type {AppHash} from './build.ts';
import type {Path} from './path.ts';

export type OptionsBase = {
  debug: boolean;
  showBenchmark: boolean;
  enableExtract: boolean;
  unsuppress: boolean | string[];
  detailsMode: DetailsMode;
  report: ReportMode;
  rulesFilter: string[] | null;
  ignoreProblematicDependencies: boolean;
};

export type Options = OptionsBase & {
  forTests: boolean;
  version: boolean;
  help: boolean;
  fix: boolean;
  fixLimit: number | undefined;
  fixAll: boolean;
  fixAllWithoutPrompt: boolean;
  suppressCheckAfterTests: boolean;
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
  reportOnOneLine: boolean;
  ignoredDirs: () => string[];
  ignoredFiles: () => string[];
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
  elmModulePath: (appHash: AppHash) => Path;
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
  resultCachePath: (appHash: AppHash) => Path;

  gitHubUser: string | undefined;
  gitHubPassword: string | undefined;
};

export type ReviewOptions = Options & {
  elmJsonPath: Path;
  readmePath: Path;
};

export type DetailsMode = 'without-details' | 'with-details';

export type ReportMode = 'json' | 'ndjson' | 'human' | null;

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
