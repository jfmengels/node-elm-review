module Wrapper.Options.InternalOptions exposing (InternalOptions, initialOptions)

import Elm.Review.ReportMode as ReportMode exposing (ReportMode)
import Set exposing (Set)
import Wrapper.Color exposing (Color, Colorize)
import Wrapper.Problem exposing (Problem, ProblemSimple)
import Wrapper.RemoteTemplate exposing (RemoteTemplate)
import Wrapper.Section exposing (Section)
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
    , report : ReportMode
    , version : Bool
    , unsuppressRules : List String
    , rules : List String
    , reviewAppFlags : List String

    -- TODO Custom type
    , ruleType : String
    , directoriesToAnalyze : List String
    , subcommandPossible : Bool
    , configPath : Maybe String
    , remoteTemplate : Maybe RemoteTemplate
    , elmJsonPath : Maybe String
    , compilerPath : Maybe String
    , elmFormatPath : Maybe String
    , prefill : Maybe String
    , namespace : Maybe String
    , githubAuth : Maybe String
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
    , report = ReportMode.HumanReadable
    , version = False
    , unsuppressRules = []
    , rules = []
    , reviewAppFlags = []
    , ruleType = "module"
    , subcommandPossible = True
    , configPath = Nothing
    , remoteTemplate = Nothing
    , elmJsonPath = Nothing
    , compilerPath = Nothing
    , elmFormatPath = Nothing
    , prefill = Nothing
    , namespace = Nothing
    , githubAuth = Nothing
    , directoriesToAnalyze = []
    , flagsNotToUseAnymore = Set.empty
    , problem = Nothing
    }
