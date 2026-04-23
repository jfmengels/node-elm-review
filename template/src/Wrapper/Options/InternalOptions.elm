module Wrapper.Options.InternalOptions exposing (InternalOptions, initialOptions)

import ElmReview.Problem exposing (ProblemSimple)
import ElmReview.ReportMode as ReportMode exposing (ReportMode)
import Set exposing (Set)
import Wrapper.Auth exposing (Auth)
import Wrapper.Options.RuleType exposing (RuleType)
import Wrapper.RemoteTemplate exposing (RemoteTemplate)
import Wrapper.Subcommand exposing (Subcommand)


type alias InternalOptions =
    { subcommand : Maybe Subcommand
    , help : Bool
    , debug : Bool
    , showBenchmark : Bool
    , ignoredDirs : List String
    , ignoredFiles : List String
    , suppressCheckAfterTests : Bool
    , watchConfig : Bool
    , forceBuild : Bool
    , forTests : Bool
    , offline : Bool
    , color : Maybe Bool
    , reportMode : ReportMode
    , version : Bool
    , unsuppressRules : List String
    , rules : List String
    , reviewAppFlags : List String
    , ruleType : Maybe RuleType
    , restOfArgs : List String
    , subcommandPossible : Bool
    , configPath : Maybe String
    , remoteTemplate : Maybe { raw : String, remoteTemplate : RemoteTemplate }
    , elmJsonPath : Maybe String
    , compilerPath : Maybe String
    , elmFormatPath : Maybe String
    , prefill : Maybe String
    , namespace : String
    , auth : Maybe Auth
    , flagsNotToUseAnymore : Set String
    , problem : Maybe (Maybe Subcommand -> ProblemSimple)
    }


initialOptions : InternalOptions
initialOptions =
    { subcommand = Nothing
    , help = False
    , debug = False
    , showBenchmark = False
    , ignoredDirs = []
    , ignoredFiles = []
    , suppressCheckAfterTests = False
    , watchConfig = False
    , forceBuild = False
    , forTests = False
    , offline = False
    , color = Nothing
    , reportMode = ReportMode.HumanReadable
    , version = False
    , unsuppressRules = []
    , rules = []
    , reviewAppFlags = []
    , ruleType = Nothing
    , subcommandPossible = True
    , configPath = Nothing
    , remoteTemplate = Nothing
    , elmJsonPath = Nothing
    , compilerPath = Nothing
    , elmFormatPath = Nothing
    , prefill = Nothing
    , namespace = "cli"
    , auth = Nothing
    , restOfArgs = []
    , flagsNotToUseAnymore = Set.empty
    , problem = Nothing
    }
