module Wrapper.Options.InternalOptions exposing (InternalOptions, initialOptions)

import Wrapper.SubCommand exposing (SubCommand)


type alias InternalOptions =
    { subCommand : Maybe SubCommand
    , help : Bool
    , debug : Bool
    , showBenchmark : Bool
    , extract : Bool
    , fileRemovalFixesEnabled : Bool
    , explainFixFailure : Bool
    , ignoreProblematicDependencies : Bool
    , suppressCheckAfterTests : Bool
    , watch : Bool
    , watchConfig : Bool
    , forceBuild : Bool
    , forTests : Bool
    , offline : Bool
    , reportOnOneLine : Bool

    -- TODO Better type for color
    , color : Bool
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
    , directoriesToAnalyze : List String
    , subCommandPossible : Bool
    , -- TODO Remove field
      appBinary : Maybe String
    , unknownFlag : Maybe String
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
    , ignoreProblematicDependencies = False
    , suppressCheckAfterTests = False
    , watch = False
    , watchConfig = False
    , forceBuild = False
    , forTests = False
    , offline = False
    , reportOnOneLine = False
    , color = True
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
    , subCommandPossible = True
    , directoriesToAnalyze = []
    , appBinary = Nothing
    , unknownFlag = Nothing
    }
