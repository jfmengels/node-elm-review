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

import Elm.Review.ReportMode exposing (ReportMode)
import Wrapper.Color as Color exposing (Colorize)
import Wrapper.ProjectPaths exposing (ProjectPaths)
import Wrapper.RemoteTemplate exposing (RemoteTemplate)
import Wrapper.Subcommand exposing (Subcommand)


type alias Options =
    { subcommand : Maybe Subcommand
    , report : ReportMode
    , projectPaths : ProjectPaths
    , debug : Bool
    , forceBuild : Bool
    , forTests : Bool
    , color : Color.Support
    , reviewProject : ReviewProject
    , reviewAppFlags : List String
    }


type ReviewProject
    = Local String
    | Remote RemoteTemplate


type alias HelpOptions =
    { subcommand : Maybe Subcommand
    , forTests : Bool
    , c : Colorize
    }
