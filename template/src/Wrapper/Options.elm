module Wrapper.Options exposing
    ( Options
    , HelpOptions
    )

{-|

@docs Options
@docs HelpOptions

-}

import Wrapper.Color exposing (Colorize)
import Wrapper.ReportMode exposing (ReportMode)
import Wrapper.Subcommand exposing (Subcommand)


type alias Options =
    { subcommand : Maybe Subcommand
    , directoriesToAnalyze : List String
    , report : ReportMode
    , debug : Bool
    , forTests : Bool
    , c : Colorize
    , -- TODO Remove field
      appBinary : String
    }


type alias HelpOptions =
    { subcommand : Maybe Subcommand
    , forTests : Bool
    , c : Colorize
    }
