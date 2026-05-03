module Wrapper.ProcessEnv exposing
    ( ProcessEnv, from
    , get
    )

{-|

@docs ProcessEnv, from
@docs get

-}

import Dict exposing (Dict)


type ProcessEnv
    = ProcessEnv (Dict String String)


from : Dict String String -> ProcessEnv
from =
    ProcessEnv


get : String -> ProcessEnv -> Maybe String
get key (ProcessEnv dict) =
    Dict.get key dict
