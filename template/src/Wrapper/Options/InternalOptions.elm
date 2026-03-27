module Wrapper.Options.InternalOptions exposing (InternalOptions, initialOptions)

import Wrapper.SubCommand exposing (SubCommand)


type alias InternalOptions =
    { subCommand : Maybe SubCommand
    , help : Bool
    , directoriesToAnalyze : List String
    , subCommandPossible : Bool
    , -- TODO Remove field
      appBinary : Maybe String
    , unknownFlag : Maybe String
    }


initialOptions : InternalOptions
initialOptions =
    { subCommand = Nothing
    , help = False
    , directoriesToAnalyze = []
    , subCommandPossible = True
    , appBinary = Nothing
    , unknownFlag = Nothing
    }
