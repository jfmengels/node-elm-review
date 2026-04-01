module Wrapper.Options.Flags exposing
    ( flags
    , buildFlag, buildFlagArgs, buildFlags
    , flagsByName
    , templateFlag
    )

{-|

@docs flags
@docs buildFlag, buildFlagArgs, buildFlags
@docs flagsByName

@docs templateFlag

-}

import Dict exposing (Dict)
import Elm.Review.ReportMode as ReportMode
import Wrapper.Color exposing (Color(..), Colorize)
import Wrapper.Flag as Flag exposing (Argument(..), Display, Flag)
import Wrapper.Options.InternalOptions exposing (InternalOptions)
import Wrapper.Problem exposing (ProblemSimple)
import Wrapper.RemoteTemplate as RemoteTemplate
import Wrapper.Section as Section exposing (Section)
import Wrapper.Subcommand as Subcommand exposing (Subcommand)


flagsByName : Dict String Flag
flagsByName =
    List.foldl (\flag dict -> Dict.insert flag.name flag dict) Dict.empty flags


flags : List Flag
flags =
    [ { name = "unsuppress"
      , argument = ArgumentAbsent addToReviewAppFlags
      , display =
            Just
                { color = Cyan
                , sections = [ Section.Regular, Section.Suppress ]
                , description =
                    \c ->
                        [ "Include " ++ c Orange "suppressed" ++ " errors in the error report for all rules."
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "unsuppress-rules"
      , argument =
            ArgumentPresent
                { argName = "<rule1,rule2,...>"
                , mayBeUsedSeveralTimes = True
                , usesEquals = False
                , apply = \_ arg options -> Ok { options | unsuppressRules = options.unsuppressRules ++ String.split "," arg }
                }
      , display =
            Just
                { color = Cyan
                , sections = [ Section.Suppress ]
                , description =
                    \c ->
                        [ "Include " ++ c Orange "suppressed" ++ " errors in the error report for the listed rules."
                        , "Specify the rules by their name, and separate them by commas."
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "rules"
      , argument =
            ArgumentPresent
                { argName = "<rule1,rule2,...>"
                , mayBeUsedSeveralTimes = True
                , usesEquals = False
                , apply = \_ arg options -> Ok { options | rules = options.rules ++ String.split "," arg }
                }
      , display =
            Just
                { color = Cyan
                , sections = [ Section.Regular ]
                , description =
                    \_ ->
                        [ "Run with a subsection of the rules in the configuration."
                        , "Specify them by their name, and separate them by commas."
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "watch"
      , argument = ArgumentAbsent (\flagName options -> addToReviewAppFlags flagName { options | watchConfig = True })
      , display =
            Just
                { color = Cyan
                , sections = [ Section.Regular ]
                , description =
                    \c ->
                        [ "Re-run " ++ c GreenBright "elm-review" ++ " automatically when your project or configuration"
                        , "changes. Use " ++ c Cyan "--watch-code" ++ " to re-run only on project changes."
                        , "You can use " ++ c Cyan "--watch" ++ " and " ++ c BlueBright "--fix" ++ " together."
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "watch-code"
      , argument = ArgumentAbsent (\_ options -> addToReviewAppFlags "watch" options)
      , display = Nothing
      }
    , { name = "extract"
      , argument = ArgumentAbsent addToReviewAppFlags
      , display =
            Just
                { color = Cyan
                , sections = [ Section.Regular ]
                , description =
                    \c ->
                        [ "Enable extracting data from the project for the rules that have a"
                        , "data extractor. Requires running with " ++ c Cyan "--report=json" ++ "."
                        , "Learn more by reading the section about \"Extracting information\""
                        , "at https://bit.ly/3UmNr0V"
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "elmjson"
      , argument =
            ArgumentPresent
                { argName = "<path-to-elm.json>"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                , apply = \_ arg options -> Ok { options | elmJsonPath = Just arg }
                }
      , display =
            Just
                { color = Cyan
                , sections = [ Section.Regular, Section.PrepareOffline ]
                , description =
                    \_ ->
                        [ "Specify the path to the elm.json file of the project. By default,"
                        , "the one in the current directory or its parent directories will be used."
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , configFlag
    , templateFlag
    , { name = "compiler"
      , argument =
            ArgumentPresent
                { argName = "<path-to-elm>"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                , apply = \_ arg options -> Ok { options | compilerPath = Just arg }
                }
      , display =
            Just
                { color = Cyan
                , sections = [ Section.Regular, Section.Init, Section.NewPackage, Section.PrepareOffline ]
                , description =
                    \c ->
                        [ "Specify the path to the " ++ c MagentaBright "elm" ++ " compiler."
                        ]
                , initDescription =
                    Just
                        (\c ->
                            [ "Specify the path to the " ++ c MagentaBright "elm" ++ " compiler."
                            , "The " ++ c MagentaBright "elm" ++ " compiler is used to know the version of the compiler to write"
                            , "down in the " ++ c Yellow "review/elm.json" ++ " file's `elm-version` field. Use this if you"
                            , "have multiple versions of the " ++ c MagentaBright "elm" ++ " compiler on your device."
                            ]
                        )
                , newPackageDescription =
                    Just
                        (\c ->
                            [ "Specify the path to the " ++ c MagentaBright "elm" ++ " compiler."
                            , "The " ++ c MagentaBright "elm" ++ " compiler is used to know the version of the compiler to write"
                            , "down in the " ++ c Yellow "review/elm.json" ++ " file's `elm-version` field. Use this if you"
                            , "have multiple versions of the " ++ c MagentaBright "elm" ++ " compiler on your device."
                            ]
                        )
                }
      }
    , { name = "rule-type"
      , argument =
            ArgumentPresent
                { argName = "<module|project>"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                , apply =
                    \_ arg options ->
                        if arg == "module" || arg == "project" then
                            Ok { options | compilerPath = Just arg }

                        else
                            Err Nothing
                }
      , display =
            Just
                { color = Cyan
                , sections = [ Section.NewRule, Section.NewPackage ]
                , description =
                    \_ ->
                        [ "Whether the starting rule should be a module rule or a project rule."
                        , "Module rules are simpler but look at Elm modules in isolation, whereas"
                        , "project rules are more complex but have access to information from the"
                        , "entire project. You can always switch from a module rule to a project"
                        , "rule manually later on."
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "version"
      , argument = ArgumentAbsent (\_ options -> { options | version = True })
      , display =
            Just
                { color = Cyan
                , sections = [ Section.Regular ]
                , description =
                    \c ->
                        [ "Print the version of the " ++ c GreenBright "elm-review" ++ " CLI."
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "help"
      , argument = ArgumentAbsent (\_ options -> { options | help = True })
      , display = Nothing
      }
    , { name = "debug"
      , argument = ArgumentAbsent (\flagName options -> addToReviewAppFlags flagName { options | debug = True })
      , display =
            Just
                { color = Cyan
                , sections = [ Section.Regular ]
                , description =
                    \c ->
                        [ "Add helpful pieces of information for debugging purposes."
                        , "This will also run the compiler with " ++ c Cyan "--debug" ++ ", allowing you to use"
                        , c Yellow "Debug" ++ " functions in your custom rules."
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "benchmark-info"
      , argument = ArgumentAbsent (\_ options -> { options | showBenchmark = True })
      , display =
            Just
                { color = Cyan
                , sections = [ Section.Regular ]
                , description =
                    \_ ->
                        [ "Print out how much time it took for rules and phases of the process to"
                        , "run. This is meant for benchmarking purposes."
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "color"
      , argument = ArgumentAbsent (\_ options -> { options | color = Just True })
      , display = Nothing
      }
    , { name = "no-color"
      , argument = ArgumentAbsent (\_ options -> { options | color = Just False })
      , display =
            Just
                { color = Cyan
                , sections = [ Section.Regular ]
                , description = \_ -> [ "Disable colors in the output." ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , reportFlag
    , { name = "no-details"
      , argument = ArgumentAbsent addToReviewAppFlags
      , display =
            Just
                { color = Cyan
                , sections = [ Section.Regular ]
                , description =
                    \_ ->
                        [ "Hide the details from error reports for a more compact view."
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "fix"
      , argument = ArgumentAbsent addToReviewAppFlags
      , display =
            Just
                { color = BlueBright
                , sections = [ Section.Fix ]
                , description =
                    \c ->
                        [ c GreenBright "elm-review" ++ " will present fixes for the errors that offer an automatic"
                        , "fix, which you can then accept or refuse one by one. When there are no"
                        , "more fixable errors left, " ++ c GreenBright "elm-review" ++ " will report the remaining errors as"
                        , "if it was called without " ++ c BlueBright "--fix" ++ "."
                        , "Fixed files will be reformatted using " ++ c MagentaBright "elm-format" ++ "."
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "fix-all"
      , argument = ArgumentAbsent addToReviewAppFlags
      , display =
            Just
                { color = BlueBright
                , sections = [ Section.Fix ]
                , description =
                    \c ->
                        [ c GreenBright "elm-review" ++ " will present a single fix containing the application of all"
                        , "available automatic fixes, which you can then accept or refuse."
                        , "Afterwards, " ++ c GreenBright "elm-review" ++ " will report the remaining errors as if it was"
                        , "called without " ++ c BlueBright "--fix-all" ++ "."
                        , "Fixed files will be reformatted using " ++ c MagentaBright "elm-format" ++ "."
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "fix-all-without-prompt"
      , argument = ArgumentAbsent addToReviewAppFlags
      , display =
            Just
                { color = BlueBright
                , sections = [ Section.Fix ]
                , description =
                    \c ->
                        [ "Same as " ++ c BlueBright "--fix-all" ++ " but fixes are applied without a prompt."
                        , "I recommend committing all changes prior to running with this option and"
                        , "reviewing the applied changes afterwards."
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "fix-limit"
      , argument =
            ArgumentPresent
                { argName = "N"
                , mayBeUsedSeveralTimes = False
                , usesEquals = True
                , apply =
                    \flag arg options ->
                        case String.toInt arg of
                            Just n ->
                                if n < 1 then
                                    -- TODO Make custom error
                                    Err Nothing

                                else
                                    addToReviewAppFlagsWithArg flag arg options

                            Nothing ->
                                Err Nothing
                }
      , display =
            Just
                { color = BlueBright
                , sections = [ Section.Fix ]
                , description = \_ -> [ "Limit the number of fixes applied in a single batch to N." ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "allow-remove-files"
      , argument = ArgumentAbsent addToReviewAppFlags
      , display =
            Just
                { color = BlueBright
                , sections = [ Section.Fix ]
                , description = \_ -> [ "Allow files to be removed by automatic fixes." ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "explain-fix-failure"
      , argument = ArgumentAbsent addToReviewAppFlags
      , display =
            Just
                { color = BlueBright
                , sections = [ Section.Fix ]
                , description = \_ -> [ "Get more information about fixes that failed to apply." ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "elm-format-path"
      , argument =
            ArgumentPresent
                { argName = "<path-to-elm-format>"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                , apply = \_ arg options -> Ok { options | elmFormatPath = Just arg }
                }
      , display =
            Just
                { color = Cyan
                , sections = [ Section.Fix ]
                , description = \c -> [ "Specify the path to " ++ c MagentaBright "elm-format" ++ "." ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "ignore-problematic-dependencies"
      , argument = ArgumentAbsent addToReviewAppFlags
      , display = Nothing
      }
    , { name = "FOR-TESTS"
      , argument = ArgumentAbsent (\_ options -> { options | forTests = True })
      , display = Nothing
      }
    , { name = "force-build"
      , argument = ArgumentAbsent (\_ options -> { options | forceBuild = True })
      , display = Nothing
      }
    , { name = "offline"
      , argument = ArgumentAbsent (\_ options -> { options | offline = True })
      , display =
            Just
                { color = Cyan
                , sections = [ Section.Regular ]
                , description =
                    \c ->
                        [ "Prevent making network calls. You might need to run"
                        , c Yellow "elm-review prepare-offline" ++ " beforehand to avoid problems."
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , gitHubAuthFlag
    , { name = "namespace"
      , argument =
            ArgumentPresent
                { argName = "<namespace>"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                , apply = \flagName arg options -> addToReviewAppFlagsWithArg flagName arg { options | namespace = Just arg }
                }
      , display = Nothing
      }
    , { name = "prefill"
      , argument =
            ArgumentPresent
                { argName = "[author name[, package name[, license]]]"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                , apply = \_ arg options -> Ok { options | prefill = Just arg }
                }
      , display = Nothing
      }
    , { name = "ignore-dirs"
      , argument =
            ArgumentPresent
                { argName = "<dir1,dir2,...>"
                , mayBeUsedSeveralTimes = True
                , usesEquals = False
                , apply = \_ arg options -> Ok { options | ignoredDirs = options.ignoredDirs ++ String.split "," arg }
                }
      , display =
            Just
                { color = Cyan
                , sections = [ Section.Regular ]
                , description =
                    \_ ->
                        [ "Ignore the reports of all rules for the specified directories."
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "ignore-files"
      , argument =
            ArgumentPresent
                { argName = "<file1,file2,...>"
                , mayBeUsedSeveralTimes = True
                , usesEquals = False
                , apply = \_ arg options -> Ok { options | ignoredFiles = options.ignoredFiles ++ String.split "," arg }
                }
      , display =
            Just
                { color = Cyan
                , sections = [ Section.Regular ]
                , description = \_ -> [ "Ignore the reports of all rules for the specified files." ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "check-after-tests"
      , argument = ArgumentAbsent (\_ options -> { options | suppressCheckAfterTests = True })
      , display =
            Just
                { color = Cyan
                , sections = [ Section.SuppressSubcommand ]
                , description =
                    \c ->
                        [ "Checks whether there are uncommitted suppression files. They may get"
                        , "updated when running " ++ c GreenBright "elm-review" ++ ", which people can forget to commit"
                        , "before making a pull request. Running " ++ c Orange "elm-review suppress" ++ " with this flag"
                        , "at the end of your test suite makes sure these files stay up to date."
                        , "This command does not cause your project to be reviewed though."
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    ]


addToReviewAppFlags : String -> InternalOptions -> InternalOptions
addToReviewAppFlags flagName options =
    { options | reviewAppFlags = ("--" ++ flagName) :: options.reviewAppFlags }


addToReviewAppFlagsWithArg : String -> String -> InternalOptions -> Result x InternalOptions
addToReviewAppFlagsWithArg flagName arg options =
    Ok { options | reviewAppFlags = ("--" ++ flagName ++ "=" ++ arg) :: options.reviewAppFlags }


gitHubAuthFlag : Flag
gitHubAuthFlag =
    { name = "github-auth"
    , argument =
        ArgumentPresent
            { argName = "<github-api-token>"
            , mayBeUsedSeveralTimes = False
            , usesEquals = True
            , apply = \_ arg options -> Ok { options | githubAuth = Just arg }
            }
    , display =
        Just
            { color = Cyan
            , sections = []
            , description =
                \c ->
                    [ "To be used along with " ++ c Cyan "--template" ++ " to avoid GitHub rate limiting."
                    , "Follow https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token to create an API token. The API token needs access to public repositories."
                    , ""
                    , "Then use the flag like this:"
                    , c GreenBright "  --github-auth=github_pat_abcdef01234567890"
                    ]
            , initDescription = Nothing
            , newPackageDescription = Nothing
            }
    }


reportFlag : Flag
reportFlag =
    { name = "report"
    , argument =
        ArgumentPresent
            { argName = "<human|json|ndjson>"
            , mayBeUsedSeveralTimes = False
            , usesEquals = True
            , apply = applyReport
            }
    , display =
        Just
            { color = Cyan
            , sections = [ Section.Regular ]
            , description =
                \c ->
                    [ "Error reports will be in JSON format. " ++ c Magenta "json" ++ " prints a single JSON object"
                    , "while " ++ c Magenta "ndjson" ++ " will print one JSON object per error each on a new line."
                    , "The formats are described in this document: https://bit.ly/31F6jzz"
                    ]
            , initDescription = Nothing
            , newPackageDescription = Nothing
            }
    }


applyReport : String -> String -> InternalOptions -> Result (Maybe a) InternalOptions
applyReport flagName arg options =
    if arg == "human" then
        addToReviewAppFlagsWithArg flagName arg { options | report = ReportMode.HumanReadable }

    else if arg == "json" then
        addToReviewAppFlagsWithArg flagName arg { options | report = ReportMode.Json }

    else if arg == "ndjson" then
        addToReviewAppFlagsWithArg flagName arg { options | report = ReportMode.NDJson }

    else
        Err Nothing


configFlag : Flag
configFlag =
    { name = "config"
    , argument =
        ArgumentPresent
            { argName = "<path-to-review-directory>"
            , mayBeUsedSeveralTimes = False
            , usesEquals = False
            , apply =
                \_ arg options ->
                    case options.remoteTemplate of
                        Nothing ->
                            Ok { options | configPath = Just arg }

                        Just _ ->
                            Err (Just (incompatibleFlags templateFlag configFlag))
            }
    , display =
        Just
            { color = Cyan
            , sections = [ Section.Regular, Section.Init, Section.PrepareOffline ]
            , description =
                \_ ->
                    [ "Use the review configuration in the specified directory instead of the"
                    , "one found in the current directory or one of its parents."
                    ]
            , initDescription =
                Just
                    (\_ ->
                        [ "Create the configuration files in the specified directory instead of in"
                        , "the review/ directory."
                        ]
                    )
            , newPackageDescription = Nothing
            }
    }


templateFlag : Flag
templateFlag =
    { name = "template"
    , argument =
        ArgumentPresent
            { argName = "<author>/<repo>[/path-to-the-config-folder][#branch-or-commit]"
            , mayBeUsedSeveralTimes = False
            , usesEquals = False
            , apply =
                \_ arg options ->
                    case options.configPath of
                        Nothing ->
                            case RemoteTemplate.fromString arg of
                                Ok remoteTemplate ->
                                    Ok { options | remoteTemplate = Just remoteTemplate }

                                Err () ->
                                    Err (Just (remoteTemplateError arg))

                        Just _ ->
                            Err (Just (incompatibleFlags configFlag templateFlag))
            }
    , display =
        Just
            { color = Cyan
            , sections = [ Section.Regular, Section.Init ]
            , description =
                \c ->
                    [ "Use the review configuration from a GitHub repository. You can use this"
                    , "to try out " ++ c GreenBright "elm-review" ++ ", a configuration or a single rule."
                    , "This flag requires Internet access, even after the first run."
                    , "Examples:"
                    , "  - elm-review --template author/elm-review-configuration"
                    , "  - elm-review --template jfmengels/elm-review-unused/example#master"
                    , ""
                    , "I recommend to only use this temporarily, and run " ++ c Yellow "elm-review init" ++ " with"
                    , "this same flag to copy the configuration to your project."
                    ]
            , initDescription =
                Just
                    (\_ ->
                        [ "Copy the review configuration from a GitHub repository, at the root or"
                        , "in a folder. Examples:"
                        , "- elm-review init --template author/elm-review-configuration"
                        , "- elm-review init --template jfmengels/elm-review-config/package"
                        , "- elm-review init --template jfmengels/elm-review-config/application"
                        , "- elm-review init --template jfmengels/elm-review-unused/example#master"
                        ]
                    )
            , newPackageDescription = Nothing
            }
    }


remoteTemplateError : String -> ProblemSimple
remoteTemplateError string =
    { title = "INVALID FLAG ARGUMENT"
    , message =
        \c ->
            "The value " ++ c RedBright string ++ " passed to " ++ c (Flag.color templateFlag) "--template" ++ """ is not a valid one.

Here is the documentation for this flag:

""" ++ buildFlag c Nothing templateFlag
    }


incompatibleFlags : Flag -> Flag -> ProblemSimple
incompatibleFlags flag1 flag2 =
    { title = "INCOMPATIBLE FLAGS"
    , message =
        \c ->
            "You used both " ++ c (Flag.color flag1) flag1.name ++ " and " ++ c (Flag.color flag2) flag2.name ++ """, but these flags can't be used together.

Please remove one of them and try re-running."""
    }


buildFlags : Colorize -> Section -> Maybe Subcommand -> String
buildFlags c section maybeSubcommand =
    List.filterMap
        (\flag ->
            case flag.display of
                Just display ->
                    if List.member section display.sections then
                        Just (buildFlag c maybeSubcommand flag)

                    else
                        Nothing

                Nothing ->
                    Nothing
        )
        flags
        |> String.join "\n\n"


buildFlag : Colorize -> Maybe Subcommand -> Flag -> String
buildFlag c maybeSubCommand flag =
    let
        description : String
        description =
            case flag.display of
                Just display ->
                    "\n        " ++ String.join "\n        " (preferredDescriptionFieldFor maybeSubCommand display c)

                Nothing ->
                    ""

        alias : String
        alias =
            if flag.name == "version" then
                ", -v"

            else if flag.name == "help" then
                ", -h"

            else
                ""

        flagPresentation : String
        flagPresentation =
            "--" ++ flag.name ++ alias ++ buildFlagArgs flag
    in
    "    " ++ c (Flag.color flag) flagPresentation ++ description


preferredDescriptionFieldFor : Maybe Subcommand -> Display -> (Colorize -> List String)
preferredDescriptionFieldFor subcommand display =
    case subcommand of
        Just Subcommand.Init ->
            Maybe.withDefault display.description display.initDescription

        Just Subcommand.NewPackage ->
            Maybe.withDefault display.description display.newPackageDescription

        Just Subcommand.NewRule ->
            display.description

        Just Subcommand.Suppress ->
            display.description

        Just Subcommand.PrepareOffline ->
            display.description

        Nothing ->
            display.description


buildFlagArgs : Flag -> String
buildFlagArgs flag =
    case flag.argument of
        ArgumentAbsent _ ->
            ""

        ArgumentPresent { argName, usesEquals } ->
            let
                delimiter : String
                delimiter =
                    if usesEquals then
                        "="

                    else
                        " "
            in
            delimiter ++ argName ++ ""
