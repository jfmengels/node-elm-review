module Wrapper.Options.Parser exposing (parse)

import Dict exposing (Dict)
import Wrapper.Options exposing (Options)
import Wrapper.Options.InternalOptions exposing (InternalOptions, initialOptions)
import Wrapper.SubCommand as SubCommand exposing (SubCommand)


parse : { env | args : List String, env : Dict String String } -> Result { title : String, message : String } Options
parse { args, env } =
    parseHelp args initialOptions
        |> toOptions


toOptions : InternalOptions -> Result { title : String, message : String } Options
toOptions options =
    case checkForUnknownArg options of
        Just error ->
            Err error

        Nothing ->
            case options.appBinary of
                Nothing ->
                    Err
                        { title = "MISSING BINARY APP"
                        , message = "This is temporarily needed"
                        }

                Just appBinary ->
                    Ok
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
            case arg of
                "--help" ->
                    parseHelp rest { options | help = True }

                "--app" ->
                    parseHelp (List.drop 1 rest) { options | appBinary = List.head rest }

                _ ->
                    -- TODO Support concatenated options like -hv
                    if String.startsWith "--" arg then
                        Debug.todo "options"

                    else
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


checkForUnknownArg : InternalOptions -> Maybe { title : String, message : String }
checkForUnknownArg options =
    case options.unknownFlag of
        Just unknown ->
            if options.help then
                Nothing

            else
                Just
                    { title = "UNKNOWN FLAG"
                    , message = unknownFlagMessage unknown
                    }

        Nothing ->
            Nothing


unknownFlagMessage : String -> String
unknownFlagMessage name =
    Debug.todo "unknownFlagMessage"
