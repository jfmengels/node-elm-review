module Wrapper.ProcessEnv exposing
    ( ProcessEnv, from
    , asProcessEnv
    )

{-|

@docs ProcessEnv, from
@docs asProcessOptions

-}

import Dict exposing (Dict)


type ProcessEnv
    = ProcessEnv (Dict String String)


from : Dict String String -> ProcessEnv
from =
    ProcessEnv


asProcessEnv : ProcessEnv -> List ( String, String )
asProcessEnv (ProcessEnv processEnv) =
    Dict.toList processEnv
