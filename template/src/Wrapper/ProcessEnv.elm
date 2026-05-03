module Wrapper.ProcessEnv exposing
    ( ProcessEnv, from
    , asProcessOptions
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


asProcessOptions : ProcessEnv -> List ( String, String )
asProcessOptions (ProcessEnv processEnv) =
    Dict.toList processEnv
