import type { Path } from "./types/path"

export type BuildResult = {
  elmModulePath: Path | null;
  reviewElmJsonPath: Path;
  reviewElmJson: any;
  appHash: AppHash;
}

export type AppHash = string;

export type ReviewElmJson = {
  dependencies: Record<string, string>
};