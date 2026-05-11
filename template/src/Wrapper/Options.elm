module Wrapper.Options exposing
    ( ReviewOptions
    , ReviewProject(..)
    , HelpOptions
    , InitOptions
    , NewRuleOptions
    , NewPackageOptions
    , PrepareOfflineOptions
    )

{-|

@docs ReviewOptions
@docs ReviewProject

@docs HelpOptions

@docs InitOptions

@docs NewRuleOptions
@docs NewPackageOptions
@docs PrepareOfflineOptions

-}

import Elm.Module as Module
import ElmReview.Color as Color
import ElmReview.Path exposing (Path)
import ElmReview.ReportMode exposing (ReportMode)
import Wrapper.Options.RuleType exposing (RuleType)
import Wrapper.ProcessEnv exposing (ProcessEnv)
import Wrapper.ProjectPaths exposing (ProjectPaths)
import Wrapper.RemoteTemplate exposing (RemoteTemplate)
import Wrapper.Subcommand exposing (Subcommand)


type alias ReviewOptions =
    { reportMode : ReportMode
    , projectPaths : ProjectPaths
    , debug : Bool
    , forceBuild : Bool
    , offline : Bool
    , color : Color.Support
    , reviewProject : ReviewProject
    , reviewAppFlags : List String
    , localElmReview : Maybe Path
    , watchConfig : Bool
    , processEnv : ProcessEnv
    , binaryRoot : Path
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
    , offline : Bool
    , forTests : Bool
    , debug : Bool
    , color : Color.Support
    }


type alias NewRuleOptions =
    { reviewFolder : Path
    , forTests : Bool
    , debug : Bool
    , color : Color.Support
    , newRuleName : Maybe Module.Name
    , ruleType : Maybe RuleType
    }


type alias NewPackageOptions =
    { forTests : Bool
    , debug : Bool
    , color : Color.Support
    , ruleType : Maybe RuleType
    , binaryRoot : Path
    }


type alias PrepareOfflineOptions =
    { reportMode : ReportMode
    , projectPaths : ProjectPaths
    , debug : Bool
    , forceBuild : Bool
    , offline : Bool
    , reviewProject : ReviewProject
    , color : Color.Support
    , localElmReview : Maybe Path
    , processEnv : ProcessEnv
    , binaryRoot : Path
    }
