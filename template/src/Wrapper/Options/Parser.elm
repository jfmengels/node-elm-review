module Wrapper.Options.Parser exposing (OptionsParseResult(..), parse)

import Dict exposing (Dict)
import Elm.Review.Vendor.Levenshtein as Levenshtein
import Set
import Wrapper.Color as Color exposing (Color(..), Colorize)
import Wrapper.Flag as Flag exposing (Argument(..), Display, Flag)
import Wrapper.Options as Options exposing (HelpOptions, Options)
import Wrapper.Options.Flags as Flags
import Wrapper.Options.InternalOptions exposing (InternalOptions, initialOptions)
import Wrapper.Path as Path exposing (Path)
import Wrapper.Problem as Problem exposing (Problem, ProblemSimple)
import Wrapper.Subcommand as Subcommand exposing (Subcommand)


parse : { env | args : List String, env : Dict String String } -> OptionsParseResult
parse { args, env } =
    parseHelp args initialOptions
        |> toOptions env


type OptionsParseResult
    = NeedElmJsonPath { formatOptions : Problem.FormatOptions {}, toOptions : { elmJsonPath : String } -> Options }
    | ParseSuccess Options
    | ShowVersion
    | ShowHelp HelpOptions
    | ParseError (Problem.FormatOptions {}) Problem


toOptions : Dict String String -> InternalOptions -> OptionsParseResult
toOptions env options =
    if options.version then
        ShowVersion

    else
        let
            c : Colorize
            c =
                Color.toAnsi (Color.supportsColor env options.color)
        in
        if options.help then
            ShowHelp
                { subcommand = options.subcommand
                , forTests = options.forTests
                , c = c
                }

        else
            case options.problem of
                Just problem ->
                    ParseError
                        { c = c
                        , report = options.report
                        , debug = options.debug
                        }
                        (Problem.from (problem options.subcommand))

                Nothing ->
                    case options.appBinary of
                        Nothing ->
                            ParseError
                                { c = c
                                , report = options.report
                                , debug = options.debug
                                }
                                (Problem.from
                                    { title = "MISSING BINARY APP"
                                    , message = always "This is temporarily needed"
                                    }
                                )

                        Just appBinary ->
                            case options.elmJsonPath of
                                Nothing ->
                                    NeedElmJsonPath
                                        { formatOptions =
                                            { report = options.report
                                            , debug = options.debug
                                            , c = c
                                            }
                                        , toOptions = \{ elmJsonPath } -> toOptionsWithElmJsonPath c options appBinary elmJsonPath
                                        }

                                Just elmJsonPath ->
                                    ParseSuccess (toOptionsWithElmJsonPath c options appBinary elmJsonPath)


toOptionsWithElmJsonPath : Colorize -> InternalOptions -> String -> String -> Options
toOptionsWithElmJsonPath c options appBinary elmJsonPath =
    let
        projectRoot : Path
        projectRoot =
            Path.dirname elmJsonPath
    in
    { subcommand = options.subcommand
    , projectRoot = projectRoot
    , elmJsonPath = elmJsonPath
    , directoriesToAnalyze = options.directoriesToAnalyze
    , report = options.report
    , debug = options.debug
    , forTests = options.forTests
    , c = c
    , reviewProject =
        case options.remoteTemplate of
            Just remoteTemplate ->
                Options.Remote remoteTemplate

            Nothing ->
                case options.configPath of
                    Just config ->
                        Options.Local config

                    Nothing ->
                        Options.Local (Path.join projectRoot "review")
    , appBinary = appBinary
    }


parseHelp : List String -> InternalOptions -> InternalOptions
parseHelp args options =
    case args of
        [] ->
            options

        arg :: rest ->
            case parseFlagAndEqual arg of
                NotFlag () ->
                    case checkForSubcommand options arg of
                        Just subcommand ->
                            parseHelp rest
                                { options
                                    | subcommand = Just subcommand
                                    , subcommandPossible = False
                                }

                        Nothing ->
                            parseHelp rest
                                { options
                                    | directoriesToAnalyze = arg :: options.directoriesToAnalyze
                                    , subcommandPossible = False
                                }

                FlagArg { flagName, equalValue } ->
                    case Dict.get flagName Flags.flagsByName of
                        Nothing ->
                            parseHelp rest
                                (markProblem (unknownFlagMessage flagName) options)

                        Just flag ->
                            case flag.argument of
                                ArgumentAbsent apply ->
                                    case equalValue of
                                        Nothing ->
                                            parseHelp rest (apply options)

                                        Just extraValue ->
                                            parseHelp rest
                                                (markProblem (unexpectedValueForFlag flag extraValue) options)

                                ArgumentPresent { mayBeUsedSeveralTimes, apply } ->
                                    if Set.member flagName options.flagsNotToUseAnymore then
                                        parseHelp rest
                                            (markProblem (flagMayNotBeUsedMultipleTimes flag) options)

                                    else
                                        case nextValue equalValue rest of
                                            Just ( value, restOfArgs ) ->
                                                case apply value options of
                                                    Err (Just problem) ->
                                                        parseHelp restOfArgs
                                                            (markProblem (\_ -> problem) options)

                                                    Err Nothing ->
                                                        parseHelp restOfArgs
                                                            (markProblem (problemForFlag flag value) options)

                                                    Ok newOptions ->
                                                        parseHelp restOfArgs
                                                            (if mayBeUsedSeveralTimes then
                                                                newOptions

                                                             else
                                                                { newOptions | flagsNotToUseAnymore = Set.insert flag.name newOptions.flagsNotToUseAnymore }
                                                            )

                                            Nothing ->
                                                markProblem (missingValueForFlag flag) options

                ShorthandFlags [] ->
                    parseHelp rest (markProblem unexpectedDash options)

                ShorthandFlags shorthands ->
                    List.foldl applyShorthand options shorthands


applyShorthand : Char -> InternalOptions -> InternalOptions
applyShorthand shorthand options =
    case shorthand of
        'v' ->
            { options | version = True }

        'h' ->
            { options | help = True }

        _ ->
            markProblem (unknownShorthand shorthand) options


nextValue : Maybe String -> List String -> Maybe ( String, List String )
nextValue equalValue args =
    case equalValue of
        Just v ->
            Just ( v, args )

        Nothing ->
            case args of
                [] ->
                    Nothing

                v :: rest ->
                    Just ( v, rest )


type ArgShape
    = FlagArg { flagName : String, equalValue : Maybe String }
    | ShorthandFlags (List Char)
    | NotFlag ()


parseFlagAndEqual : String -> ArgShape
parseFlagAndEqual arg =
    if String.startsWith "--" arg then
        case String.indexes "=" arg of
            [] ->
                FlagArg
                    { flagName = String.dropLeft 2 arg
                    , equalValue = Nothing
                    }

            index :: _ ->
                FlagArg
                    { flagName = String.slice 2 index arg
                    , equalValue = Just (String.dropLeft (index + 1) arg)
                    }

    else if String.startsWith "-" arg then
        ShorthandFlags (String.toList (String.dropLeft 1 arg))

    else
        notFlag


notFlag : ArgShape
notFlag =
    NotFlag ()


checkForSubcommand : InternalOptions -> String -> Maybe Subcommand
checkForSubcommand options arg =
    if options.subcommandPossible then
        parseSubcommand arg

    else
        Nothing


parseSubcommand : String -> Maybe Subcommand
parseSubcommand arg =
    case arg of
        "init" ->
            Just Subcommand.Init

        "new-package" ->
            Just Subcommand.NewPackage

        "new-rule" ->
            Just Subcommand.NewRule

        "suppress" ->
            Just Subcommand.Suppress

        "prepare-offline" ->
            Just Subcommand.PrepareOffline

        _ ->
            Nothing


markProblem : (Maybe Subcommand -> ProblemSimple) -> InternalOptions -> InternalOptions
markProblem problem internalOptions =
    case internalOptions.problem of
        Just _ ->
            internalOptions

        Nothing ->
            { internalOptions | problem = Just problem }


unknownFlagMessage : String -> a -> ProblemSimple
unknownFlagMessage flagName _ =
    let
        hint : Colorize -> String
        hint c =
            if flagName == "suppress" then
                "There is a " ++ c Orange "suppress" ++ " subcommand available, did you mean that? Or do you want one of these instead?"

            else
                "Maybe you want one of these instead?"
    in
    { title = "UNKNOWN FLAG"
    , message = \c -> "I did not recognize this flag:\n\n    " ++ c RedBright ("--" ++ flagName) ++ "\n\n" ++ hint c ++ "\n\n" ++ suggestions flagName c
    }


unknownShorthand : Char -> a -> ProblemSimple
unknownShorthand flag _ =
    { title = "UNKNOWN FLAG"
    , message = \c -> "I did not recognize this flag:\n\n    " ++ c RedBright ("-" ++ String.fromChar flag) ++ ". Did you mean -h or -v?"
    }


suggestions : String -> Colorize -> String
suggestions flagName c =
    Flags.flags
        |> List.sortBy (\flag -> Levenshtein.distance flagName flag.name)
        |> List.take 3
        |> List.map (\flag -> c GreenBright ("    --" ++ flag.name ++ Flags.buildFlagArgs flag))
        |> String.join "\n"


missingValueForFlag : Flag -> Maybe Subcommand -> ProblemSimple
missingValueForFlag flag subcommand =
    { title = "MISSING FLAG ARGUMENT"
    , message = \c -> "The " ++ c (Flag.color flag) ("--" ++ flag.name) ++ """ flag needs more information.

Here is the documentation for this flag:

""" ++ Flags.buildFlag c subcommand flag
    }


unexpectedValueForFlag : Flag -> String -> Maybe Subcommand -> ProblemSimple
unexpectedValueForFlag flag extraValue subcommand =
    { title = "UNEXPECTED FLAG VALUE"
    , message = \c -> "You assigned the value " ++ c RedBright extraValue ++ " to " ++ c (Flag.color flag) ("--" ++ flag.name) ++ """, but this flag does not expected a value.

In case it helps, here is the documentation for this flag:

""" ++ Flags.buildFlag c subcommand flag
    }


unexpectedDash : a -> ProblemSimple
unexpectedDash _ =
    { title = "UNEXPECTED - IN ARGS"
    , message = \c -> "I found a lone " ++ c RedBright "-" ++ """ in the arguments. This does not however mean anything to me.

I recommend you remove it."""
    }


problemForFlag : Flag -> String -> Maybe Subcommand -> ProblemSimple
problemForFlag flag value subcommand =
    { title = "INVALID FLAG ARGUMENT"
    , message = \c -> "The value " ++ c RedBright value ++ """ passed to """ ++ c (Flag.color flag) flag.name ++ """ may not be used several times. I need a single value for this flag but I got several, and I don't know which one to choose.

In case it helps, here is the documentation for this flag:

""" ++ Flags.buildFlag c subcommand flag
    }


flagMayNotBeUsedMultipleTimes : Flag -> Maybe Subcommand -> ProblemSimple
flagMayNotBeUsedMultipleTimes flag subcommand =
    { title = "FLAG USED SEVERAL TIMES"
    , message = \c -> "The " ++ c RedBright ("--" ++ flag.name) ++ """ flag may not be used several times. I need a single value for this flag but I got several, and I don't know which one to choose.

In case it helps, here is the documentation for this flag:

""" ++ Flags.buildFlag c subcommand flag
    }
