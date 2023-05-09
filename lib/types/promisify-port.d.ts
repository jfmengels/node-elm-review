export type PortsToPromise<DataIn, DataOut> = {
  subscribeTo: PortFromElm<DataOut>;
  sendThrough: PortToElm<DataIn>;
  data: DataIn;
};

export type PortFromElm<DataOut> = {
  subscribe: CallbackFn<DataOut>;
  unsubscribe: CallbackFn<DataOut>;
};

type CallbackFn<T> = (cb: (data: T) => void) => void;

export type PortToElm<DataIn> = {
  send: (data: DataIn) => void;
};
