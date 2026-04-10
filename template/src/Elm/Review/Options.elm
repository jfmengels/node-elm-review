module Elm.Review.Options exposing (Options, parse, toReviewOptions)

import Elm.Review.CliCommunication as CliCommunication
import Elm.Review.FixOptions as FixOptions
import Elm.Review.RefusedErrorFixes as RefusedErrorFixes exposing (RefusedErrorFixes)
import Elm.Review.ReporterOptions as ReporterOptions
import Elm.Review.UnsuppressMode as UnsuppressMode exposing (UnsuppressMode)
import ElmReview.Color as Color
import ElmReview.Path exposing (Path)
import ElmReview.ReportMode as ReportMode exposing (ReportMode)
import Review.Options
import Set exposing (Set)


type alias Options =
    { fixMode : FixOptions.Mode
    , fileRemovalFixesEnabled : Bool
    , fixLimit : Maybe Int
    , fixExplanation : FixOptions.Explanation
    , reportFixMode : ReporterOptions.ReportFixMode
    , enableExtract : Bool
    , unsuppressMode : UnsuppressMode
    , detailsMode : ReporterOptions.DetailsMode
    , reportMode : ReportMode
    , ignoreProblematicDependencies : Bool
    , rulesFilter : Maybe (Set String)
    , ignoredDirs : List Path
    , ignoredFiles : List Path
    , writeSuppressionFiles : Bool
    , communicationKey : CliCommunication.Key
    , suppress : Bool
    , watch : Bool
    , supportsColor : Bool
    , color : Color.Support
    , debug : Bool
    , reviewFolder : Path
    , usesRemoteTemplate : Bool
    , namespace : String
    , directoriesToAnalyze : List Path
    }


type alias InternalOptions =
    { fixMode : FixOptions.Mode
    , fileRemovalFixesEnabled : Bool
    , fixLimit : Maybe Int
    , fixExplanation : FixOptions.Explanation
    , enableExtract : Bool
    , unsuppressMode : UnsuppressMode
    , detailsMode : ReporterOptions.DetailsMode
    , reportMode : ReportMode
    , ignoreProblematicDependencies : Bool
    , rulesFilter : Maybe (Set String)
    , ignoredDirs : List Path
    , ignoredFiles : List Path
    , writeSuppressionFiles : Bool
    , communicationKey : CliCommunication.Key
    , suppress : Bool
    , watch : Bool
    , color : Color.Support
    , debug : Bool
    , reviewFolder : Path
    , usesRemoteTemplate : Bool
    , namespace : String
    , directoriesToAnalyze : List Path
    }


toOptions : InternalOptions -> Options
toOptions options =
    let
        fileRemovalFixesEnabled : Bool
        fileRemovalFixesEnabled =
            options.fileRemovalFixesEnabled && options.fixMode /= FixOptions.DontFix
    in
    { fixMode = options.fixMode
    , fileRemovalFixesEnabled = fileRemovalFixesEnabled
    , fixLimit = options.fixLimit
    , fixExplanation = options.fixExplanation
    , reportFixMode = fixModeToReportFixMode options.fixMode
    , enableExtract = options.enableExtract
    , unsuppressMode = options.unsuppressMode
    , detailsMode = options.detailsMode
    , reportMode = options.reportMode
    , ignoreProblematicDependencies = options.ignoreProblematicDependencies
    , rulesFilter = options.rulesFilter
    , ignoredDirs = options.ignoredDirs
    , ignoredFiles = options.ignoredFiles
    , writeSuppressionFiles = options.writeSuppressionFiles
    , communicationKey = options.communicationKey
    , suppress = options.suppress
    , watch = options.watch
    , supportsColor = Color.doesSupportColor options.color
    , color = options.color
    , debug = options.debug
    , reviewFolder = options.reviewFolder
    , usesRemoteTemplate = options.usesRemoteTemplate
    , namespace = options.namespace
    , directoriesToAnalyze = options.directoriesToAnalyze
    }


fixModeToReportFixMode : FixOptions.Mode -> ReporterOptions.ReportFixMode
fixModeToReportFixMode fixMode =
    case fixMode of
        FixOptions.DontFix ->
            ReporterOptions.Reviewing

        FixOptions.Fix ->
            ReporterOptions.Fixing

        FixOptions.FixAll ->
            ReporterOptions.Fixing


parse : List String -> Result String Options
parse args =
    parseHelp args default
        |> Result.map toOptions


parseHelp : List String -> InternalOptions -> Result String InternalOptions
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


applyArg : String -> InternalOptions -> Result String InternalOptions
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
            Ok { flags | detailsMode = ReporterOptions.WithoutDetails }

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
            Ok { flags | color = Color.noColors }

        [ "--debug" ] ->
            Ok { flags | debug = True }

        [ "--namespace", namespace ] ->
            Ok { flags | namespace = namespace }

        [ "--review-folder", reviewFolder ] ->
            Ok { flags | reviewFolder = reviewFolder }

        [ "--template" ] ->
            Ok { flags | usesRemoteTemplate = True }

        [ "--dirs-to-analyze", dirs ] ->
            Ok { flags | directoriesToAnalyze = String.split "," dirs }

        _ ->
            Err ("Unknown flag `" ++ arg ++ "`")


default : InternalOptions
default =
    { fixMode = FixOptions.DontFix
    , fileRemovalFixesEnabled = False
    , fixLimit = Nothing
    , enableExtract = False
    , fixExplanation = FixOptions.Succinct
    , unsuppressMode = UnsuppressMode.UnsuppressNone
    , reportMode = ReportMode.HumanReadable
    , detailsMode = ReporterOptions.WithDetails
    , ignoreProblematicDependencies = False
    , rulesFilter = Nothing
    , ignoredDirs = []
    , ignoredFiles = []
    , writeSuppressionFiles = False
    , communicationKey = CliCommunication.dummy
    , suppress = False
    , watch = False
    , color = Color.yesColors
    , debug = False
    , namespace = "cli"
    , reviewFolder = "review"
    , usesRemoteTemplate = False
    , directoriesToAnalyze = []
    }


toReviewOptions : Options -> { fixesAllowed : Bool } -> RefusedErrorFixes -> Review.Options.ReviewOptions
toReviewOptions options { fixesAllowed } refusedErrorFixes =
    Review.Options.defaults
        |> Review.Options.withDataExtraction (options.enableExtract && options.reportMode == ReportMode.Json)
        |> Review.Options.withLogger (Just (CliCommunication.send options.communicationKey))
        |> Review.Options.withFixes (FixOptions.fixModeToReviewOptions fixesAllowed options)
        |> Review.Options.withFileRemovalFixes options.fileRemovalFixesEnabled
        |> Review.Options.withIgnoredFixes (\error -> RefusedErrorFixes.memberUsingRecord error refusedErrorFixes)
