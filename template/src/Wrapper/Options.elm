module Wrapper.Options exposing
    ( Options
    , ReviewProject(..)
    , HelpOptions
    )

{-|

@docs Options
@docs ReviewProject

@docs HelpOptions

-}

import Wrapper.Color exposing (Colorize)
import Wrapper.RemoteTemplate exposing (RemoteTemplate)
import Wrapper.ReportMode exposing (ReportMode)
import Wrapper.Subcommand exposing (Subcommand)


type alias Options =
    { subcommand : Maybe Subcommand
    , directoriesToAnalyze : List String
    , report : ReportMode
    , elmJsonPath : String
    , debug : Bool
    , forTests : Bool
    , c : Colorize
    , reviewProject : ReviewProject
    , -- TODO Remove field
      appBinary : String
    }


type ReviewProject
    = Local String
    | Remote RemoteTemplate


type alias HelpOptions =
    { subcommand : Maybe Subcommand
    , forTests : Bool
    , c : Colorize
    }
