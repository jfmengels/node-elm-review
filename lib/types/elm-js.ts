export type ElmNamespace<
  Entrypoints extends string[],
  Flags,
  App extends ElmApp<Record<string, unknown>>
> = {
  Elm: NestedEntrypoints<
    Entrypoints,
    {
      init: Flags extends undefined
        ? () => App
        : (flags: {flags: Flags}) => App;
    }
  >;
};

type NestedEntrypoints<Entrypoints extends string[], T> = Entrypoints extends [
  infer First extends string,
  ...infer Rest extends string[]
]
  ? {[K in First]: NestedEntrypoints<Rest, T>}
  : T;

export type ElmApp<Ports extends Record<string, unknown>> = {
  ports: Ports;
};
