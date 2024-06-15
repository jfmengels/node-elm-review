export type PortsToPromise<DataIn, DataOut> = {
  subscribeTo: PortFromElm<DataOut>;
  sendThrough: PortToElm<DataIn>;
  data: DataIn;
};

export type PortFromElm<DataOut> = {
  subscribe: CallbackFn<DataOut>;
  unsubscribe: CallbackFn<DataOut>;
};

export type CallbackFn<T> = (cb: Listened<T>) => void;

export type Listened<T> = (data: T) => void;

export type PortToElm<DataIn> = {
  send: (data: DataIn) => void;
};
