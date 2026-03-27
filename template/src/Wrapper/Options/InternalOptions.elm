module Wrapper.Options.InternalOptions exposing (InternalOptions, initialOptions)

import Wrapper.Color exposing (Colorize)
import Wrapper.SubCommand exposing (SubCommand)


type alias InternalOptions =
    { subCommand : Maybe SubCommand
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
    , subCommandPossible : Bool
    , configPath : String
    , elmJsonPath : String
    , compilerPath : Maybe String
    , elmFormatPath : Maybe String
    , namespace : Maybe String
    , githubAuth : Maybe String
    , -- TODO Remove field
      appBinary : Maybe String
    , problem : Maybe (Colorize -> { title : String, message : String })
    }


initialOptions : InternalOptions
initialOptions =
    { subCommand = Nothing
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
    , subCommandPossible = True
    , configPath = "elm.json"
    , elmJsonPath = "elm.json"
    , compilerPath = Nothing
    , elmFormatPath = Nothing
    , namespace = Nothing
    , githubAuth = Nothing
    , directoriesToAnalyze = []
    , appBinary = Nothing
    , problem = Nothing
    }
