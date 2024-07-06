export type Value = null | ValueStruct | number | string;
export type ValueStruct = {
  $: 1 | -1 | 0 | `$L`;
  a?: string[] | string;
  b?: ValueStruct;
  c?: unknown;
};
