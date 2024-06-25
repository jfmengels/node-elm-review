export type PortsToPromise<DataIn, DataOut> = {
  subscribeTo: SubscribePort<DataOut>;
  sendThrough: SendPort<DataIn>;
  data: DataIn;
};

export type SubscribePort<DataOut> = {
  subscribe: CallbackFn<DataOut>;
  unsubscribe: CallbackFn<DataOut>;
};

export type CallbackFn<T> = (callback: Listened<T>) => void;

export type Listened<T> = (data: T) => void;

export type SendPort<DataIn> = {
  send: (data: DataIn) => void;
};

export type Port<T, U> = SendPort<T> & SubscribePort<U>;
