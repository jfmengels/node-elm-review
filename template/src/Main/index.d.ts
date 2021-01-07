type FromElm = { tag : "Alert"; message : string } | { tag : "SendPresenceHeartbeat" }

type Flags = null

export type JsonObject = {[Key in string]?: JsonValue};
export interface JsonArray extends Array<JsonValue> {}
/**
Matches any valid JSON value.
Source: https://github.com/sindresorhus/type-fest/blob/master/source/basic.d.ts
*/
export type JsonValue = string | number | boolean | null | JsonObject | JsonArray;

export interface ElmApp {
  ports: {
    interopFromElm: {
      subscribe(callback: (fromElm: FromElm) => void): void;
    };
    interopToElm: {
      send(data: string): void;
    };
  };
}

declare const Elm: {
  Main: {
    init(options: { node?: HTMLElement | null; flags: Flags }): ElmApp;
  };
};
export { Elm };
    