import type { Path } from "./types/path"

export type BuildResult = {
  elmModulePath: Path | null;
  reviewElmJsonPath: Path;
  reviewElmJson: ReviewElmJson;
  appHash: AppHash;
}

export type AppHash = string;

export type ReviewElmJson = {
  "source-directories": Array<Path>,
  dependencies: Record<string, string>
};