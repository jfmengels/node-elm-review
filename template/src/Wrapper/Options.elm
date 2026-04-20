module Wrapper.Options exposing
    ( ReviewOptions
    , ReviewProject(..)
    , HelpOptions
    , InitOptions
    , NewRuleOptions
    , NewPackageOptions
    )

{-|

@docs ReviewOptions
@docs ReviewProject

@docs HelpOptions

@docs InitOptions

@docs NewRuleOptions
@docs NewPackageOptions

-}

import ElmReview.Color as Color
import ElmReview.Path exposing (Path)
import ElmReview.ReportMode exposing (ReportMode)
import Wrapper.Options.RuleType exposing (RuleType)
import Wrapper.ProjectPaths exposing (ProjectPaths)
import Wrapper.RemoteTemplate exposing (RemoteTemplate)
import Wrapper.Subcommand exposing (Subcommand)


type alias ReviewOptions =
    { subcommand : Maybe Subcommand
    , reportMode : ReportMode
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
    , remoteTemplate : Maybe RemoteTemplate
    , forTests : Bool
    , debug : Bool
    , color : Color.Support
    }


type alias NewRuleOptions =
    { reviewFolder : Path
    , forTests : Bool
    , debug : Bool
    , color : Color.Support
    , newRuleName : Maybe String
    , ruleType : Maybe RuleType
    }


type alias NewPackageOptions =
    { forTests : Bool
    , debug : Bool
    , color : Color.Support
    , ruleType : Maybe RuleType
    }
