export type PortsToPromise<DataIn, DataOut> = {
  subscribeTo: SubscribePort<DataOut>;
  sendThrough: SendPort<DataIn>;
  data: DataIn;
};

export type SubscribePort<DataOut> = {
  subscribe: CallbackFn<DataOut>;
  unsubscribe: CallbackFn<DataOut>;
};

type CallbackFn<T> = (callback: (data: T) => void) => void;

export type SendPort<DataIn> = {
  send: (data: DataIn) => void;
};
