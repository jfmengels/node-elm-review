export type Value = null | ValueStruct | number | string;
export type ValueStruct = {
  readonly $: 1 | -1 | 0 | '$L';
  readonly a?: ElmArray;
  readonly b?: ValueStruct;
  readonly c?: unknown;
};
export type ElmArray = string[] | string;
