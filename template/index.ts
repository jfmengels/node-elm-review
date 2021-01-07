import { Elm, Flags } from "./src/Main";

const str = "";

const flags: Flags = null;

const app = Elm.Main.init({ flags });

app.ports.interopFromElm.subscribe(fromElm => {
    switch (fromElm.tag) {
        case "Alert": {
            return fromElm.message;
        }
        case "SendPresenceHeartbeat": {
            return "";
        }
    }
})