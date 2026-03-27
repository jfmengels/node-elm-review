module Wrapper.Options.InternalOptions exposing (InternalOptions, ProblemData, initialOptions)

import Dict exposing (Dict)
import Wrapper.Color exposing (Color, Colorize)
import Wrapper.Section exposing (Section)
import Wrapper.Subcommand exposing (Subcommand)


type alias InternalOptions =
    { subcommand : Maybe Subcommand
    , help : Bool
    , debug : Bool
    , showBenchmark : Bool
    , extract : Bool
    , fileRemovalFixesEnabled : Bool
    , explainFixFailure : Bool
    , ignoredDirs : List String
    , ignoredFiles : List String
    , ignoreProblematicDependencies : Bool
    , suppressCheckAfterTests : Bool
    , watch : Bool
    , watchConfig : Bool
    , forceBuild : Bool
    , forTests : Bool
    , offline : Bool
    , reportOnOneLine : Bool
    , color : Maybe Bool
    , details : Bool

    -- TODO Custom type
    , report : String
    , version : Bool
    , fix : Bool
    , fixAll : Bool
    , fixAllWithoutPrompt : Bool
    , fixLimit : Maybe Int
    , unsuppress : Bool
    , unsuppressRules : List String
    , rules : List String

    -- TODO Custom type
    , ruleType : String
    , directoriesToAnalyze : List String
    , subcommandPossible : Bool
    , configPath : String
    , elmJsonPath : String
    , compilerPath : Maybe String
    , elmFormatPath : Maybe String
    , namespace : Maybe String
    , githubAuth : Maybe String
    , -- TODO Remove field
      appBinary : Maybe String
    , flagsNotToUseAnymore : Dict String Display
    , problem : Maybe (ProblemData -> { title : String, message : String })
    }


type alias Display =
    { sections : List Section
    , color : Color
    , description : Colorize -> List String
    , initDescription : Maybe (Colorize -> List String)
    , newPackageDescription : Maybe (Colorize -> List String)
    }


type alias ProblemData =
    { c : Colorize
    , subcommand : Maybe Subcommand
    }


initialOptions : InternalOptions
initialOptions =
    { subcommand = Nothing
    , help = False
    , debug = False
    , showBenchmark = False
    , extract = False
    , fileRemovalFixesEnabled = False
    , explainFixFailure = False
    , ignoredDirs = []
    , ignoredFiles = []
    , ignoreProblematicDependencies = False
    , suppressCheckAfterTests = False
    , watch = False
    , watchConfig = False
    , forceBuild = False
    , forTests = False
    , offline = False
    , reportOnOneLine = False
    , color = Nothing
    , details = True
    , report = "human"
    , version = False
    , fix = False
    , fixAll = False
    , fixAllWithoutPrompt = False
    , fixLimit = Nothing
    , unsuppress = False
    , unsuppressRules = []
    , rules = []
    , ruleType = "module"
    , subcommandPossible = True
    , configPath = "elm.json"
    , elmJsonPath = "elm.json"
    , compilerPath = Nothing
    , elmFormatPath = Nothing
    , namespace = Nothing
    , githubAuth = Nothing
    , directoriesToAnalyze = []
    , appBinary = Nothing
    , flagsNotToUseAnymore = Dict.empty
    , problem = Nothing
    }
