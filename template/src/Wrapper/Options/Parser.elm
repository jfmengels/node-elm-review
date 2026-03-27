module Wrapper.Options.Parser exposing (OptionsParseResult(..), parse)

import Dict exposing (Dict)
import Elm.Review.Vendor.Levenshtein as Levenshtein
import Wrapper.Color as Color exposing (Color(..), Colorize)
import Wrapper.Options exposing (Argument(..), Flag, Options)
import Wrapper.Options.Flags as Flags
import Wrapper.Options.InternalOptions exposing (InternalOptions, initialOptions)
import Wrapper.SubCommand as SubCommand exposing (SubCommand)


parse : { env | args : List String, env : Dict String String } -> OptionsParseResult
parse { args, env } =
    parseHelp args initialOptions
        |> toOptions env


type OptionsParseResult
    = ParseSuccess Options
      -- | Help Section
    | ParseError { title : String, message : String }


toOptions : Dict String String -> InternalOptions -> OptionsParseResult
toOptions env options =
    let
        supportsColor_ : Bool
        supportsColor_ =
            Color.supportsColor env options.color
    in
    case options.problem of
        Just problem ->
            ParseError (problem (Color.toAnsi supportsColor_))

        Nothing ->
            case options.appBinary of
                Nothing ->
                    ParseError
                        { title = "MISSING BINARY APP"
                        , message = "This is temporarily needed"
                        }

                Just appBinary ->
                    ParseSuccess
                        { subCommand = options.subCommand
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
                    case checkIfIsSubCommand options arg of
                        Just subCommand ->
                            parseHelp rest
                                { options
                                    | subCommand = Just subCommand
                                    , subCommandPossible = False
                                }

                        Nothing ->
                            parseHelp rest
                                { options
                                    | directoriesToAnalyze = arg :: options.directoriesToAnalyze
                                    , subCommandPossible = False
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
                                    case nextValue equalValue rest of
                                        Just ( value, restOfArgs ) ->
                                            case apply value options of
                                                Err () ->
                                                    parseHelp restOfArgs
                                                        (markProblem (problemForFlag flagName) options)

                                                Ok newOptions ->
                                                    parseHelp restOfArgs newOptions

                                        Nothing ->
                                            markProblem (missingValueForFlag flagName) options


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

    else
        notFlag


notFlag : ArgShape
notFlag =
    NotFlag ()


checkIfIsSubCommand : InternalOptions -> String -> Maybe SubCommand
checkIfIsSubCommand options arg =
    if options.subCommandPossible then
        parseSubCommand arg

    else
        Nothing


parseSubCommand : String -> Maybe SubCommand
parseSubCommand arg =
    case arg of
        "init" ->
            Just SubCommand.Init

        "new-package" ->
            Just SubCommand.NewPackage

        "new-rule" ->
            Just SubCommand.NewRule

        "suppress" ->
            Just SubCommand.Suppress

        "prepare-offline" ->
            Just SubCommand.PrepareOffline

        _ ->
            Nothing


markProblem : (Colorize -> { title : String, message : String }) -> InternalOptions -> InternalOptions
markProblem problem internalOptions =
    case internalOptions.problem of
        Just _ ->
            internalOptions

        Nothing ->
            { internalOptions | problem = Just problem }


unknownFlagMessage : String -> Colorize -> { title : String, message : String }
unknownFlagMessage flagName c =
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


missingValueForFlag : String -> Colorize -> { title : String, message : String }
missingValueForFlag flagName c =
    Debug.todo "missingValueForFlag"


unexpectedValueForFlag : String -> String -> Colorize -> { title : String, message : String }
unexpectedValueForFlag flagName extraValue c =
    Debug.todo "unexpectedValueForFlag"


problemForFlag : String -> Colorize -> { title : String, message : String }
problemForFlag flagName c =
    Debug.todo "missingValueForFlag"
