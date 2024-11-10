export type Result<Error, Value> = Success<Value> | Fail<Error>;
export type Success<Value> = {tag: 'ok'; value: Value};
export type Fail<Failure> = {tag: 'fail'; failure: Failure};
