/**
 * A replacer function for JSON.stringify.
 */
export type Replacer = (key: string, value: unknown) => unknown;

/**
 * A reviver function for JSON.parse.
 */
export type Reviver = (key: string, value: unknown) => unknown;
