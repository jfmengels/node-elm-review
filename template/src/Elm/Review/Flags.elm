module Elm.Review.Flags exposing (Flags, parse)

import Elm.Review.CliCommunication as CliCommunication
import Elm.Review.FixOptions as FixOptions
import Elm.Review.Reporter as Reporter
import Elm.Review.UnsuppressMode as UnsuppressMode exposing (UnsuppressMode)
import ElmReview.ReportMode as ReportMode exposing (ReportMode)
import Set exposing (Set)


type alias Flags =
    { fixMode : FixOptions.Mode
    , fileRemovalFixesEnabled : Bool
    , fixLimit : Maybe Int
    , fixExplanation : FixOptions.Explanation
    , enableExtract : Bool
    , unsuppressMode : UnsuppressMode
    , detailsMode : Reporter.DetailsMode
    , reportMode : ReportMode
    , ignoreProblematicDependencies : Bool
    , rulesFilter : Maybe (Set String)
    , ignoredDirs : List String
    , ignoredFiles : List String
    , writeSuppressionFiles : Bool
    , logger : CliCommunication.Key
    , suppress : Bool
    , watch : Bool
    , supportsColor : Bool
    , debug : Bool
    , namespace : String
    , directoriesToAnalyze : List String
    }


parse : List String -> Result String Flags
parse args =
    parseHelp args default


parseHelp : List String -> Flags -> Result String Flags
parseHelp args flags =
    case args of
        [] ->
            Ok flags

        arg :: rest ->
            case applyArg arg flags of
                Ok newFlags ->
                    parseHelp rest newFlags

                Err err ->
                    Err err


applyArg : String -> Flags -> Result String Flags
applyArg arg flags =
    case String.split "=" arg of
        [ "--fix" ] ->
            Ok { flags | fixMode = FixOptions.Fix }

        [ "--fix-all" ] ->
            Ok { flags | fixMode = FixOptions.FixAll }

        [ "--allow-remove-files" ] ->
            Ok { flags | fileRemovalFixesEnabled = True }

        [ "--fix-limit", n ] ->
            case String.toInt n of
                Just fixLimit ->
                    Ok { flags | fixLimit = Just fixLimit }

                Nothing ->
                    Err ("Couldn't parse fix limit `" ++ n ++ "`")

        [ "--explain-fix-failure" ] ->
            Ok { flags | fixExplanation = FixOptions.Detailed }

        [ "--extract" ] ->
            Ok { flags | enableExtract = True }

        [ "--unsuppress" ] ->
            Ok { flags | unsuppressMode = UnsuppressMode.UnsuppressAll }

        [ "--unsuppress-rules", ruleNames ] ->
            Ok { flags | unsuppressMode = UnsuppressMode.UnsuppressRules (Set.fromList (String.split "," ruleNames)) }

        [ "--no-details" ] ->
            Ok { flags | detailsMode = Reporter.WithoutDetails }

        [ "--report", "human" ] ->
            Ok { flags | reportMode = ReportMode.HumanReadable }

        [ "--report", "json" ] ->
            Ok { flags | reportMode = ReportMode.Json }

        [ "--report", "ndjson" ] ->
            Ok { flags | reportMode = ReportMode.NDJson }

        [ "--ignore-problematic-dependencies" ] ->
            Ok { flags | ignoreProblematicDependencies = True }

        [ "--rules", ruleNames ] ->
            Ok { flags | rulesFilter = Just (Set.fromList (String.split "," ruleNames)) }

        [ "--ignore-dirs", dirs ] ->
            Ok { flags | ignoredDirs = String.split "," dirs }

        [ "--ignore-files", files ] ->
            Ok { flags | ignoredFiles = String.split "," files }

        [ "--suppress" ] ->
            Ok { flags | suppress = True }

        [ "--watch" ] ->
            Ok { flags | watch = True }

        [ "--no-color" ] ->
            Ok { flags | supportsColor = False }

        [ "--debug" ] ->
            Ok { flags | debug = True }

        [ "--namespace", namespace ] ->
            Ok { flags | namespace = namespace }

        [ "--dirs-to-analyze", dirs ] ->
            Ok { flags | directoriesToAnalyze = String.split "," dirs }

        _ ->
            Err ("Unknown flag `" ++ arg ++ "`")


default : Flags
default =
    { fixMode = FixOptions.DontFix
    , fileRemovalFixesEnabled = False
    , fixLimit = Nothing
    , enableExtract = False
    , fixExplanation = FixOptions.Succinct
    , unsuppressMode = UnsuppressMode.UnsuppressNone
    , reportMode = ReportMode.HumanReadable
    , detailsMode = Reporter.WithDetails
    , ignoreProblematicDependencies = False
    , rulesFilter = Nothing
    , ignoredDirs = []
    , ignoredFiles = []
    , writeSuppressionFiles = False
    , logger = CliCommunication.dummy
    , suppress = False
    , watch = False
    , supportsColor = True
    , debug = False
    , namespace = "cli"
    , directoriesToAnalyze = []
    }
