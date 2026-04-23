module Wrapper.Options.Parser exposing (OptionsParseResult(..), parse)

import Dict exposing (Dict)
import Elm.Review.Vendor.Levenshtein as Levenshtein
import ElmReview.Color as Color exposing (Color(..), Colorize)
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem, ProblemSimple)
import Set
import Wrapper.Flag as Flag exposing (Argument(..), Flag)
import Wrapper.Options as Options exposing (HelpOptions, InitOptions, NewPackageOptions, NewRuleOptions, ReviewOptions)
import Wrapper.Options.Flags as Flags
import Wrapper.Options.InternalOptions exposing (InternalOptions, initialOptions)
import Wrapper.ProjectPaths as ProjectPaths exposing (ProjectPaths)
import Wrapper.Subcommand as Subcommand exposing (Subcommand)


parse : { env | args : List String, env : Dict String String } -> OptionsParseResult
parse { args, env } =
    parseHelp args initialOptions
        |> toOptions env


type OptionsParseResult
    = NeedElmJsonPath { formatOptions : Problem.FormatOptions {}, toOptions : { elmJsonPath : Path } -> OptionsParseResult }
    | Review ReviewOptions
    | ShowVersion
    | ShowHelp HelpOptions
    | Init InitOptions
    | NewRule NewRuleOptions
    | NewPackage NewPackageOptions
    | ParseError (Problem.FormatOptions {}) Problem


toOptions : Dict String String -> InternalOptions -> OptionsParseResult
toOptions env options =
    if options.version then
        ShowVersion

    else
        let
            color : Color.Support
            color =
                Color.supportsColor env options.color
        in
        if options.help then
            ShowHelp
                { subcommand = options.subcommand
                , forTests = options.forTests
                , color = color
                }

        else
            let
                parseError : Problem -> OptionsParseResult
                parseError problem =
                    ParseError
                        { color = color
                        , reportMode = options.reportMode
                        , debug = options.debug
                        }
                        problem
            in
            case options.problem of
                Just problem ->
                    Problem.from (problem options.subcommand)
                        |> parseError

                Nothing ->
                    let
                        requiresElmJsonPath_ : (Path -> OptionsParseResult) -> OptionsParseResult
                        requiresElmJsonPath_ =
                            requiresElmJsonPath options color
                    in
                    case options.subcommand of
                        Nothing ->
                            requiresElmJsonPath_
                                (\elmJsonPath ->
                                    Review (toReviewOptions color options (Path.dirname elmJsonPath))
                                )

                        Just Subcommand.Suppress ->
                            requiresElmJsonPath_
                                (\elmJsonPath ->
                                    Review (toReviewOptions color options (Path.dirname elmJsonPath))
                                )

                        Just Subcommand.Init ->
                            requiresElmJsonPath_
                                (\elmJsonPath ->
                                    Init (toInitOptions color options (Path.dirname elmJsonPath))
                                )

                        Just Subcommand.NewRule ->
                            requiresElmJsonPath_
                                (\elmJsonPath ->
                                    NewRule (toNewRuleOptions color options (Path.dirname elmJsonPath))
                                )

                        Just Subcommand.NewPackage ->
                            if options.offline then
                                { title = "COMMAND REQUIRES NETWORK ACCESS"
                                , message = \c -> "I can't use " ++ c Yellow "new-package" ++ " in " ++ c Cyan "offline" ++ """ mode, as I need network access to perform a number of steps.

I recommend you try to gain network access and try again."""
                                }
                                    |> Problem.from
                                    |> parseError

                            else
                                NewPackage (toNewPackageOptions color options)

                        Just Subcommand.PrepareOffline ->
                            requiresElmJsonPath_
                                (\elmJsonPath ->
                                    Problem.notImplementedYet "prepare-offline subcommand"
                                        |> parseError
                                )


requiresElmJsonPath : InternalOptions -> Color.Support -> (Path -> OptionsParseResult) -> OptionsParseResult
requiresElmJsonPath options color createOptions =
    case options.elmJsonPath of
        Nothing ->
            NeedElmJsonPath
                { formatOptions =
                    { reportMode = options.reportMode
                    , debug = options.debug
                    , color = color
                    }
                , toOptions = \{ elmJsonPath } -> createOptions elmJsonPath
                }

        Just elmJsonPath ->
            createOptions elmJsonPath


toReviewOptions : Color.Support -> InternalOptions -> Path -> ReviewOptions
toReviewOptions color options projectRoot =
    let
        projectPaths : ProjectPaths
        projectPaths =
            ProjectPaths.from
                { projectRoot = projectRoot
                , namespace = options.namespace
                }
    in
    { subcommand = options.subcommand
    , projectPaths = projectPaths
    , reportMode = options.reportMode
    , forceBuild = options.forceBuild
    , debug = options.debug
    , color = color
    , reviewProject = reviewProject projectRoot options
    , reviewAppFlags = reviewAppFlags color options
    , auth = options.auth
    }


reviewProject : Path -> InternalOptions -> Options.ReviewProject
reviewProject projectRoot options =
    case options.remoteTemplate of
        Just { remoteTemplate } ->
            Options.Remote remoteTemplate

        Nothing ->
            case options.configPath of
                Just config ->
                    Options.Local config

                Nothing ->
                    Options.Local (Path.join2 projectRoot "review")


reviewAppFlags : Color.Support -> InternalOptions -> List String
reviewAppFlags color options =
    addJusts
        [ if List.isEmpty options.restOfArgs then
            Nothing

          else
            Just ("--dirs-to-analyze=" ++ uniqueList options.restOfArgs)
        , if List.isEmpty options.ignoredFiles then
            Nothing

          else
            Just ("--ignore-files=" ++ uniqueList options.ignoredFiles)
        , if List.isEmpty options.ignoredDirs then
            Nothing

          else
            Just ("--ignore-dirs=" ++ uniqueList options.ignoredDirs)
        , if List.isEmpty options.rules then
            Nothing

          else
            Just ("--rules=" ++ uniqueList options.rules)
        , if List.isEmpty options.unsuppressRules then
            Nothing

          else
            Just ("--unsuppress-rules=" ++ uniqueList options.unsuppressRules)
        , case options.subcommand of
            Just Subcommand.Suppress ->
                Just "--suppress"

            _ ->
                Nothing
        , if Color.doesSupportColor color then
            Nothing

          else
            Just "--no-color"
        ]
        options.reviewAppFlags


toInitOptions : Color.Support -> InternalOptions -> Path -> InitOptions
toInitOptions color options projectRoot =
    { configPath = Path.join2 projectRoot "review"
    , remoteTemplate = Maybe.map .remoteTemplate options.remoteTemplate
    , forTests = options.forTests
    , debug = options.debug
    , color = color
    }


toNewRuleOptions : Color.Support -> InternalOptions -> Path -> NewRuleOptions
toNewRuleOptions color options projectRoot =
    { reviewFolder = projectRoot
    , forTests = options.forTests
    , debug = options.debug
    , color = color
    , newRuleName = List.reverse options.restOfArgs |> List.head
    , ruleType = options.ruleType
    }


toNewPackageOptions : Color.Support -> InternalOptions -> NewPackageOptions
toNewPackageOptions color options =
    { forTests = options.forTests
    , debug = options.debug
    , color = color
    , ruleType = options.ruleType
    }


addJusts : List (Maybe a) -> List a -> List a
addJusts list initial =
    List.foldl
        (\maybe acc ->
            case maybe of
                Nothing ->
                    acc

                Just v ->
                    v :: acc
        )
        initial
        list


uniqueList : List String -> String
uniqueList list =
    list
        |> Set.fromList
        |> Set.toList
        |> String.join ","


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
                                    | restOfArgs = arg :: options.restOfArgs
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
                                            parseHelp rest (apply flagName options)

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
                                                case apply flagName value options of
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
                                                                { newOptions | flagsNotToUseAnymore = Set.insert flagName newOptions.flagsNotToUseAnymore }
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
    , message = \c -> "The " ++ formatFlag c flag ++ """ flag needs more information.

Here is the documentation for this flag:

""" ++ Flags.buildFlag c subcommand flag
    }


unexpectedValueForFlag : Flag -> String -> Maybe Subcommand -> ProblemSimple
unexpectedValueForFlag flag extraValue subcommand =
    { title = "UNEXPECTED FLAG VALUE"
    , message = \c -> "You assigned the value " ++ c RedBright extraValue ++ " to " ++ formatFlag c flag ++ """, but this flag does not expected a value.

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


formatFlag : Colorize -> Flag -> String
formatFlag c flag =
    c (Flag.color flag) ("--" ++ flag.name)
