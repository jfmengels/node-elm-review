export type ElmModule<P, F, Entrypoints extends string[] = ['Main']> = {
  Elm: NestedEntrypoints<Entrypoints, P, F>;
};

export type NestedEntrypoints<
  Entrypoints extends string[],
  P,
  F
> = Entrypoints extends [
  infer First extends string,
  ...infer Rest extends string[]
]
  ? {[K in First]: NestedEntrypoints<Rest, P, F>}
  : ElmMain<P, F>;

export type ElmMain<P, F> = {
  init(options?: {node?: undefined; flags: F} | undefined): ElmApp<P>;
};

export type ElmApp<P> = {
  ports: P;
};

export type PortToElm<V> = {
  send(value: V): void;
};

export type PortFromElm<V> = {
  subscribe(handler: (value: V) => void): void;
  unsubscribe(handler: (value: V) => void): void;
};
