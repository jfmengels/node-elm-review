import type {Replacer} from './json.ts';
import type {Path} from './path.ts';

declare global {
  // eslint-disable-next-line no-var -- See discussion at typescript-eslint/typescript-eslint#7941.
  var loadResultFromCache:
    | (() => null)
    | ((ruleName: RuleName, ruleId: RuleId) => CacheEntry);

  // eslint-disable-next-line no-var -- See discussion at typescript-eslint/typescript-eslint#7941.
  var saveResultToCache:
    | (() => void)
    | ((
        ruleName: RuleName,
        ruleId: RuleId,
        cacheEntry: CacheEntry
      ) => Promise<void>);

  // eslint-disable-next-line no-var -- See discussion at typescript-eslint/typescript-eslint#7941.
  var elmJsonReplacer: Replacer;
}

export type RuleName = string;
export type RuleId = string;
export type CacheEntry = unknown;
export type CacheKey = `${RuleName}-${RuleId}`;

export type CacheData = {
  filePath: Path;
  cacheEntry: CacheEntry;
  cacheKey: CacheKey;
};
