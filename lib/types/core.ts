export type Result<Error, Value> = Ok<Value> | Err<Error>;
export type Ok<Value> = {tag: 'ok'; value: Value};
export type Err<Error> = {tag: 'err'; error: Error};
