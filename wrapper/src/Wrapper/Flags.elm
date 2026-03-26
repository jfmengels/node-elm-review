module Wrapper.Flags exposing (Flags, parse)

import Cli exposing (Env)


type alias Flags =
    { appBinary : String
    }


parse : Env -> Result String Flags
parse env =
    case env.args of
        [] ->
            Err "Missing app binary path"

        appBinary :: _ ->
            Ok { appBinary = appBinary }
