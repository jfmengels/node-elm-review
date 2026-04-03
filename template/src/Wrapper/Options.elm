module Wrapper.Options exposing
    ( ReviewOptions
    , ReviewProject(..)
    , HelpOptions
    , InitOptions
    )

{-|

@docs ReviewOptions
@docs ReviewProject

@docs HelpOptions

@docs InitOptions

-}

import ElmReview.Color as Color
import ElmReview.Path exposing (Path)
import ElmReview.ReportMode exposing (ReportMode)
import Wrapper.ProjectPaths exposing (ProjectPaths)
import Wrapper.RemoteTemplate exposing (RemoteTemplate)
import Wrapper.Subcommand exposing (Subcommand)


type alias ReviewOptions =
    { subcommand : Maybe Subcommand
    , report : ReportMode
    , projectPaths : ProjectPaths
    , debug : Bool
    , forceBuild : Bool
    , color : Color.Support
    , reviewProject : ReviewProject
    , reviewAppFlags : List String
    }


type ReviewProject
    = Local Path
    | Remote RemoteTemplate


type alias HelpOptions =
    { subcommand : Maybe Subcommand
    , forTests : Bool
    , color : Color.Support
    }


type alias InitOptions =
    { configPath : Path
    , template : Maybe RemoteTemplate
    , forTests : Bool
    , debug : Bool
    , color : Color.Support
    }
