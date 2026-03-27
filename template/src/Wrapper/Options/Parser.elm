module Wrapper.Options.Parser exposing (OptionsParseResult(..), parse)

import Dict exposing (Dict)
import Elm.Review.Vendor.Levenshtein as Levenshtein
import Wrapper.Color as Color exposing (Color(..), Colorize)
import Wrapper.Options exposing (Argument(..), Display, Flag, Options)
import Wrapper.Options.Flags as Flags
import Wrapper.Options.InternalOptions exposing (InternalOptions, ProblemData, initialOptions)
import Wrapper.Subcommand as Subcommand exposing (Subcommand)


parse : { env | args : List String, env : Dict String String } -> OptionsParseResult
parse { args, env } =
    parseHelp args initialOptions
        |> toOptions env


type OptionsParseResult
    = ParseSuccess Options
    | ShowHelp Colorize (Maybe Subcommand)
    | ParseError { title : String, message : String }


toOptions : Dict String String -> InternalOptions -> OptionsParseResult
toOptions env options =
    let
        c : Colorize
        c =
            Color.toAnsi (Color.supportsColor env options.color)
    in
    if options.help then
        ShowHelp c options.subcommand

    else
        case options.problem of
            Just problem ->
                ParseError
                    (problem
                        { c = c
                        , subcommand = options.subcommand
                        }
                    )

            Nothing ->
                case options.appBinary of
                    Nothing ->
                        ParseError
                            { title = "MISSING BINARY APP"
                            , message = "This is temporarily needed"
                            }

                    Just appBinary ->
                        ParseSuccess
                            { subcommand = options.subcommand
                            , help = options.help
                            , directoriesToAnalyze = options.directoriesToAnalyze
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
                                                (markProblem (unexpectedValueForFlag flagName extraValue) options)

                                ArgumentPresent { apply } ->
                                    case Dict.get flagName options.flagsNotToUseAnymore of
                                        Just display ->
                                            parseHelp rest
                                                (markProblem (flagMayNotBeUsedMultipleTimes flag display) options)

                                        Nothing ->
                                            case nextValue equalValue rest of
                                                Just ( value, restOfArgs ) ->
                                                    case apply value options of
                                                        Err () ->
                                                            parseHelp restOfArgs
                                                                (markProblem (problemForFlag flagName) options)

                                                        Ok newOptions ->
                                                            parseHelp restOfArgs
                                                                (case flag.display of
                                                                    Just display ->
                                                                        { newOptions | flagsNotToUseAnymore = Dict.insert flag.name display newOptions.flagsNotToUseAnymore }

                                                                    Nothing ->
                                                                        newOptions
                                                                )

                                                Nothing ->
                                                    markProblem (missingValueForFlag flagName) options

                ShorthandFlags [] ->
                    parseHelp rest (markProblem (\_ -> Debug.todo "Plain - used alone") options)

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
            markProblem (\_ -> Debug.todo "Unknown shorthand") options


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


markProblem : (ProblemData -> { title : String, message : String }) -> InternalOptions -> InternalOptions
markProblem problem internalOptions =
    case internalOptions.problem of
        Just _ ->
            internalOptions

        Nothing ->
            { internalOptions | problem = Just problem }


unknownFlagMessage : String -> ProblemData -> { title : String, message : String }
unknownFlagMessage flagName { c } =
    let
        hint : String
        hint =
            if flagName == "suppress" then
                "There is a " ++ c Orange "suppress" ++ " subcommand available, did you mean that? Or do you want one of these instead?"

            else
                "Maybe you want one of these instead?"
    in
    { title = "UNKNOWN FLAG"
    , message = "I did not recognize this flag:\n\n    " ++ c RedBright ("--" ++ flagName) ++ "\n\n" ++ hint ++ "\n\n" ++ suggestions flagName c
    }


suggestions : String -> Colorize -> String
suggestions flagName c =
    Flags.flags
        |> List.sortBy (\flag -> Levenshtein.distance flagName flag.name)
        |> List.take 3
        |> List.map (\flag -> c GreenBright ("    --" ++ flag.name ++ Flags.buildFlagArgs flag))
        |> String.join "\n"


missingValueForFlag : String -> ProblemData -> { title : String, message : String }
missingValueForFlag flagName c =
    Debug.todo "missingValueForFlag"


unexpectedValueForFlag : String -> String -> ProblemData -> { title : String, message : String }
unexpectedValueForFlag flagName extraValue c =
    Debug.todo "unexpectedValueForFlag"


problemForFlag : String -> ProblemData -> { title : String, message : String }
problemForFlag flagName c =
    Debug.todo "missingValueForFlag"


flagMayNotBeUsedMultipleTimes : Flag -> Display -> ProblemData -> { title : String, message : String }
flagMayNotBeUsedMultipleTimes flag display { c, subcommand } =
    { title = "FLAG USED SEVERAL TIMES"
    , message = "The " ++ c RedBright ("--" ++ flag.name) ++ """ flag may not be used several times. I need a single value for this flag but I got several, and I don't know which one to choose.

In case it helps, here is the documentation for this flag:

""" ++ Flags.buildFlag c subcommand flag display
    }
