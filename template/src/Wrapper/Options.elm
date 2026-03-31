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

import Wrapper.Color as Color exposing (Colorize)
import Wrapper.ProjectPaths exposing (ProjectPaths)
import Wrapper.RemoteTemplate exposing (RemoteTemplate)
import Wrapper.ReportMode exposing (ReportMode)
import Wrapper.Subcommand exposing (Subcommand)


type alias Options =
    { subcommand : Maybe Subcommand
    , directoriesToAnalyze : List String
    , report : ReportMode
    , projectPaths : ProjectPaths
    , debug : Bool
    , forceBuild : Bool
    , forTests : Bool
    , color : Color.Support
    , reviewProject : ReviewProject
    }


type ReviewProject
    = Local String
    | Remote RemoteTemplate


type alias HelpOptions =
    { subcommand : Maybe Subcommand
    , forTests : Bool
    , c : Colorize
    }
