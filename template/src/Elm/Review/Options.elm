module Elm.Review.Options exposing (Options, parse)

import Elm.Review.CliCommunication as CliCommunication
import Elm.Review.FixOptions as FixOptions
import Elm.Review.Reporter as Reporter
import Elm.Review.UnsuppressMode as UnsuppressMode exposing (UnsuppressMode)
import ElmReview.Path exposing (Path)
import ElmReview.ReportMode as ReportMode exposing (ReportMode)
import Set exposing (Set)


type alias Options =
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
    , ignoredDirs : List Path
    , ignoredFiles : List Path
    , writeSuppressionFiles : Bool
    , logger : CliCommunication.Key
    , suppress : Bool
    , watch : Bool
    , supportsColor : Bool
    , debug : Bool
    , reviewFolder : Path
    , namespace : String
    , directoriesToAnalyze : List Path
    }


parse : List String -> Result String Options
parse args =
    parseHelp args default


parseHelp : List String -> Options -> Result String Options
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


applyArg : String -> Options -> Result String Options
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

        [ "--review-folder", reviewFolder ] ->
            Ok { flags | reviewFolder = reviewFolder }

        [ "--dirs-to-analyze", dirs ] ->
            Ok { flags | directoriesToAnalyze = String.split "," dirs }

        _ ->
            Err ("Unknown flag `" ++ arg ++ "`")


default : Options
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
    , reviewFolder = "review"
    , directoriesToAnalyze = []
    }
