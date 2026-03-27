module Wrapper.Options.InternalOptions exposing (InternalOptions)

import Wrapper.Options exposing (SubCommand)


type alias InternalOptions =
    { subCommand : Maybe SubCommand
    , help : Bool
    , directoriesToAnalyze : List String
    , subCommandPossible : Bool
    , -- TODO Remove field
      appBinary : Maybe String
    , unknownFlag : Maybe String
    }
