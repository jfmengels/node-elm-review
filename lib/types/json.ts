/**
 * A replacer function for {@linkcode JSON.stringify}.
 */
export type Replacer = (key: string, value: unknown) => unknown;

/**
 * A reviver function for {@linkcode JSON.parse}.
 */
export type Reviver = (key: string, value: unknown) => unknown;
