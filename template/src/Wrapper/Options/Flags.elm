module Wrapper.Options.Flags exposing (buildFlag, buildFlagArgs, buildFlags, flags, flagsByName, flagsNotToDuplicate)

import Dict exposing (Dict)
import Set exposing (Set)
import Wrapper.Color exposing (Color(..), Colorize)
import Wrapper.Options exposing (Argument(..), Display, Flag)
import Wrapper.Options.InternalOptions exposing (InternalOptions)
import Wrapper.Section as Section
import Wrapper.Subcommand as Subcommand exposing (Subcommand)


flagsByName : Dict String Flag
flagsByName =
    List.foldl (\flag dict -> Dict.insert flag.name flag dict) Dict.empty flags


flagsNotToDuplicate : Set String
flagsNotToDuplicate =
    List.foldl
        (\flag set ->
            case flag.argument of
                ArgumentPresent { mayBeUsedSeveralTimes } ->
                    if mayBeUsedSeveralTimes then
                        set

                    else
                        Set.insert flag.name set

                ArgumentAbsent _ ->
                    set
        )
        Set.empty
        flags


flags : List Flag
flags =
    [ { name = "unsuppress"
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | unsuppress = True })
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
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<rule1,rule2,...>"
                , mayBeUsedSeveralTimes = True
                , usesEquals = False
                , apply = \arg options -> Ok { options | unsuppressRules = options.unsuppressRules ++ String.split "," arg }
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
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<rule1,rule2,...>"
                , mayBeUsedSeveralTimes = True
                , usesEquals = False
                , apply = \arg options -> Ok { options | rules = options.rules ++ String.split "," arg }
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
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | watch = True, watchConfig = True })
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
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | watch = True })
      , display = Nothing
      }
    , { name = "extract"
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | extract = True })
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
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<path-to-elm.json>"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                , apply = \arg options -> Ok { options | elmJsonPath = arg }
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
    , { name = "config"
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<path-to-review-directory>"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                , apply = \arg options -> Ok { options | configPath = arg }
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
    , templateFlag
    , { name = "compiler"
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<path-to-elm>"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                , apply = \arg options -> Ok { options | compilerPath = Just arg }
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
                            , "down in the " ++ c Yellow "review/elm.json" ++ " file’s \"elm-version\" field. Use this if you"
                            , "have multiple versions of the " ++ c MagentaBright "elm" ++ " compiler on your device."
                            ]
                        )
                , newPackageDescription =
                    Just
                        (\c ->
                            [ "Specify the path to the " ++ c MagentaBright "elm" ++ " compiler."
                            , "The " ++ c MagentaBright "elm" ++ " compiler is used to know the version of the compiler to write"
                            , "down in the " ++ c Yellow "review/elm.json" ++ " file’s \"elm-version\" field. Use this if you"
                            , "have multiple versions of the " ++ c MagentaBright "elm" ++ " compiler on your device."
                            ]
                        )
                }
      }
    , { name = "rule-type"
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<module|project>"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                , apply =
                    \arg options ->
                        if arg == "module" || arg == "project" then
                            Ok { options | compilerPath = Just arg }

                        else
                            Err ()
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
      , alias = Just "v"
      , argument = ArgumentAbsent (\options -> { options | version = True })
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
      , alias = Just "h"
      , argument = ArgumentAbsent (\options -> { options | help = True })
      , display = Nothing
      }
    , { name = "debug"
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | debug = True })
      , display =
            Just
                { color = Cyan
                , sections = [ Section.Regular ]
                , description =
                    \c ->
                        [ "Add helpful pieces of information for debugging purposes."
                        , "This will also run the compiler with " ++ c Cyan " --debug" ++ ", allowing you to use"
                        , c Yellow "Debug" ++ " functions in your custom rules."
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "benchmark-info"
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | showBenchmark = True })
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
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | color = Just True })
      , display = Nothing
      }
    , { name = "no-color"
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | color = Just False })
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
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | details = False })
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
    , { name = "details"
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | details = True })
      , display = Nothing
      }
    , { name = "fix"
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | fix = True })
      , display =
            Just
                { color = BlueBright
                , sections = [ Section.Fix ]
                , description =
                    \c ->
                        [ c GreenBright "elm-review" ++ " will present fixes for the errors that offer an automatic"
                        , "fix, which you can then accept or refuse one by one. When there are no"
                        , "more fixable errors left, " ++ c GreenBright "elm-review" ++ " will report the remaining errors as"
                        , "if it was called without " ++ c BlueBright " --fix" ++ "."
                        , "Fixed files will be reformatted using " ++ c MagentaBright "elm-format" ++ "."
                        ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
      }
    , { name = "fix-all"
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | fixAll = True })
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
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | fixAllWithoutPrompt = True })
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
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "N"
                , mayBeUsedSeveralTimes = False
                , usesEquals = True
                , apply =
                    \arg options ->
                        case String.toInt arg of
                            Just n ->
                                Ok { options | fixLimit = Just n }

                            Nothing ->
                                Err ()
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
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | fileRemovalFixesEnabled = True })
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
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | explainFixFailure = True })
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
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<path-to-elm-format>"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                , apply = \arg options -> Ok { options | elmFormatPath = Just arg }
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
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | ignoreProblematicDependencies = True })
      , display = Nothing
      }
    , { name = "FOR-TESTS"
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | forTests = True })
      , display = Nothing
      }
    , { name = "force-build"
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | forceBuild = True })
      , display = Nothing
      }
    , { name = "offline"
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | offline = True })
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
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<namespace>"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                , apply = \arg options -> Ok { options | namespace = Just arg }
                }
      , display = Nothing
      }
    , { name = "prefill"
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "[author name[, package name[, license]]]"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                , apply = \_ _ -> Debug.todo "prefill"
                }
      , display = Nothing
      }
    , { name = "ignore-dirs"
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<dir1,dir2,...>"
                , mayBeUsedSeveralTimes = True
                , usesEquals = False
                , apply = \arg options -> Ok { options | ignoredDirs = options.ignoredDirs ++ String.split "," arg }
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
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<file1,file2,...>"
                , mayBeUsedSeveralTimes = True
                , usesEquals = False
                , apply = \arg options -> Ok { options | ignoredFiles = options.ignoredFiles ++ String.split "," arg }
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
      , alias = Nothing
      , argument = ArgumentAbsent (\options -> { options | suppressCheckAfterTests = True })
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
    , { name = "app"
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<path-to-app>"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                , apply = \arg options -> Ok { options | appBinary = Just arg }
                }
      , display = Nothing
      }
    ]


gitHubAuthFlag : Flag
gitHubAuthFlag =
    { name = "github-auth"
    , alias = Nothing
    , argument =
        ArgumentPresent
            { argName = "<github-api-token>"
            , mayBeUsedSeveralTimes = False
            , usesEquals = True
            , apply = \arg options -> Ok { options | githubAuth = Just arg }
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
    , alias = Nothing
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


applyReport : String -> InternalOptions -> Result () InternalOptions
applyReport arg options =
    if arg == "human" then
        Ok { options | report = "human" }

    else if arg == "json" then
        Ok { options | report = "json" }

    else if arg == "ndjson" then
        Ok { options | report = "ndjson", reportOnOneLine = True }

    else
        Err ()


templateFlag : Flag
templateFlag =
    { name = "template"
    , alias = Nothing
    , argument =
        ArgumentPresent
            { argName = "<author>/<repo>[/path-to-the-config-folder][#branch-or-commit]"
            , mayBeUsedSeveralTimes = False
            , usesEquals = False
            , apply = \arg options -> Debug.todo "template"
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


buildFlags : Colorize -> Section.Section -> Maybe Subcommand -> String
buildFlags c section maybeSubcommand =
    List.filterMap
        (\flag ->
            case flag.display of
                Just display ->
                    if List.member section display.sections then
                        Just (buildFlag c maybeSubcommand flag display)

                    else
                        Nothing

                Nothing ->
                    Nothing
        )
        flags
        |> String.join "\n\n"


buildFlag : Colorize -> Maybe Subcommand -> Flag -> Display -> String
buildFlag c maybeSubCommand flag display =
    let
        description : (Color -> String -> String) -> List String
        description =
            preferredDescriptionFieldFor maybeSubCommand display

        alias : String
        alias =
            case flag.alias of
                Just alias_ ->
                    ", -" ++ alias_

                Nothing ->
                    ""

        flagPresentation : String
        flagPresentation =
            "--" ++ flag.name ++ alias ++ buildFlagArgs flag
    in
    "    " ++ c display.color flagPresentation ++ "\n        " ++ String.join "\n        " (description c)


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
