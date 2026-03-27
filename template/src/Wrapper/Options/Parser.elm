module Wrapper.Options.Parser exposing (parse)

import Dict exposing (Dict)
import Wrapper.Options exposing (Options, SubCommand(..))


type alias TmpFlags =
    { subCommand : Maybe SubCommand
    , help : Bool
    , directoriesToAnalyze : List String
    , subCommandPossible : Bool
    , -- TODO Remove field
      appBinary : Maybe String
    , unknownFlag : Maybe String
    }


default : TmpFlags
default =
    { subCommand = Nothing
    , help = False
    , subCommandPossible = True
    , directoriesToAnalyze = []
    , appBinary = Nothing
    , unknownFlag = Nothing
    }


parse : { env | args : List String, env : Dict String String } -> Result { title : String, message : String } Options
parse { args, env } =
    let
        flags : TmpFlags
        flags =
            parseHelp args default
    in
    case checkForUnknownArg flags of
        Just error ->
            Err error

        Nothing ->
            case flags.appBinary of
                Nothing ->
                    Err
                        { title = "MISSING BINARY APP"
                        , message = "This is temporarily needed"
                        }

                Just appBinary ->
                    Ok
                        { subCommand = flags.subCommand
                        , help = flags.help
                        , directoriesToAnalyze = flags.directoriesToAnalyze
                        , appBinary = appBinary
                        }


parseHelp : List String -> TmpFlags -> TmpFlags
parseHelp args flags =
    case args of
        [] ->
            flags

        arg :: rest ->
            case arg of
                "--help" ->
                    parseHelp rest { flags | help = True }

                "--app" ->
                    parseHelp (List.drop 1 rest) { flags | appBinary = List.head rest }

                _ ->
                    -- TODO Support concatenated flags like -hv
                    if String.startsWith "--" arg then
                        Debug.todo "flags"

                    else
                        case checkIfIsSubCommand flags arg of
                            Just subCommand ->
                                parseHelp rest
                                    { flags
                                        | subCommand = Just subCommand
                                        , subCommandPossible = False
                                    }

                            Nothing ->
                                parseHelp rest
                                    { flags
                                        | directoriesToAnalyze = arg :: flags.directoriesToAnalyze
                                        , subCommandPossible = False
                                    }


checkIfIsSubCommand : TmpFlags -> String -> Maybe SubCommand
checkIfIsSubCommand flags arg =
    if flags.subCommandPossible then
        parseSubCommand arg

    else
        Nothing


parseSubCommand : String -> Maybe SubCommand
parseSubCommand arg =
    case arg of
        "init" ->
            Just Init

        "new-package" ->
            Just NewPackage

        "new-rule" ->
            Just NewRule

        "suppress" ->
            Just Suppress

        "prepare-offline" ->
            Just PrepareOffline

        _ ->
            Nothing


checkForUnknownArg : TmpFlags -> Maybe { title : String, message : String }
checkForUnknownArg flags =
    case flags.unknownFlag of
        Just unknown ->
            if flags.help then
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
