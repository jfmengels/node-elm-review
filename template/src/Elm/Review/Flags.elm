module Elm.Review.Flags exposing (FixMode(..), Flags, ReportMode(..), parse)

import Cli exposing (Env)
import Elm.Review.CliCommunication as CliCommunication
import Elm.Review.FixExplanation as FixExplanation exposing (FixExplanation)
import Elm.Review.Reporter as Reporter
import Elm.Review.UnsuppressMode as UnsuppressMode exposing (UnsuppressMode)
import Set exposing (Set)


type alias Flags =
    { fixMode : FixMode
    , fixLimit : Maybe Int
    , fixExplanation : FixExplanation
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
    }


type FixMode
    = Mode_DontFix
    | Mode_Fix Bool
    | Mode_FixAll Bool


type ReportMode
    = HumanReadable
    | Json
    | NDJson


parse : Env -> Result String Flags
parse env =
    parseHelp env.args default


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
            Ok { flags | fixMode = Mode_Fix False }

        [ "--fix-remove-files" ] ->
            Ok { flags | fixMode = Mode_Fix True }

        [ "--fix-all" ] ->
            Ok { flags | fixMode = Mode_FixAll False }

        [ "--fix-all-remove-files" ] ->
            Ok { flags | fixMode = Mode_FixAll True }

        [ "--fix-limit", n ] ->
            case String.toInt n of
                Just fixLimit ->
                    Ok { flags | fixLimit = Just fixLimit }

                Nothing ->
                    Err ("Couldn't parse fix limit `" ++ n ++ "`")

        [ "--explain-fix-failure" ] ->
            Ok { flags | fixExplanation = FixExplanation.Detailed }

        [ "--extract" ] ->
            Ok { flags | enableExtract = True }

        [ "--unsuppress", ruleNames ] ->
            Ok { flags | unsuppressMode = UnsuppressMode.UnsuppressRules (Set.fromList (String.split "," ruleNames)) }

        [ "--unsuppress" ] ->
            Ok { flags | unsuppressMode = UnsuppressMode.UnsuppressAll }

        [ "--no-details" ] ->
            Ok { flags | detailsMode = Reporter.WithoutDetails }

        [ "--report", "human" ] ->
            Ok { flags | reportMode = HumanReadable }

        [ "--report", "json" ] ->
            Ok { flags | reportMode = Json }

        [ "--report", "ndjson" ] ->
            Ok { flags | reportMode = NDJson }

        [ "--ignore-problematic-dependencies" ] ->
            Ok { flags | ignoreProblematicDependencies = True }

        [ "--rules", ruleNames ] ->
            Ok { flags | rulesFilter = Just (Set.fromList (String.split "," ruleNames)) }

        [ "--ignore-dirs", ruleNames ] ->
            Ok { flags | ignoredDirs = String.split "," ruleNames }

        [ "--ignore-files", ruleNames ] ->
            Ok { flags | ignoredFiles = String.split "," ruleNames }

        [ "--suppress" ] ->
            Ok { flags | suppress = True }

        [ "--watch" ] ->
            Ok { flags | watch = True }

        [ "--no-color" ] ->
            Ok { flags | supportsColor = False }

        [ "--debug" ] ->
            Ok { flags | debug = True }

        _ ->
            Err ("Unknown flag `" ++ arg ++ "`")


default : Flags
default =
    { fixMode = Mode_DontFix
    , fixLimit = Nothing
    , enableExtract = False
    , fixExplanation = FixExplanation.Succinct
    , unsuppressMode = UnsuppressMode.UnsuppressNone
    , reportMode = HumanReadable
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
    }
