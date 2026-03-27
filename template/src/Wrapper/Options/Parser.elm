module Wrapper.Options.Parser exposing (OptionsParseResult(..), parse)

import Wrapper.Options exposing (Options)
import Wrapper.Options.InternalOptions exposing (InternalOptions, initialOptions)
import Wrapper.SubCommand as SubCommand exposing (SubCommand)


parse : { env | args : List String, env : b } -> OptionsParseResult
parse { args, env } =
    parseHelp args initialOptions
        |> toOptions


type OptionsParseResult
    = ParseSuccess Options
      -- | Help Section
    | ParseError { title : String, message : String }


toOptions : InternalOptions -> OptionsParseResult
toOptions options =
    case options.problem of
        Just problem ->
            ParseError problem

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


markProblem : { title : String, message : String } -> InternalOptions -> InternalOptions
markProblem problem internalOptions =
    case internalOptions.problem of
        Just _ ->
            internalOptions

        Nothing ->
            { internalOptions | problem = Just problem }


unknownFlagMessage : String -> String
unknownFlagMessage name =
    Debug.todo "unknownFlagMessage"
