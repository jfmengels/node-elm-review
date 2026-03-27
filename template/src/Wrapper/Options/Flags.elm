module Wrapper.Options.Flags exposing (flags)

import Dict exposing (Dict)
import Wrapper.Options as Flags exposing (Argument(..), Color(..), Flag)


flags : List Flag
flags =
    [ { name = "unsuppress"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display =
            Just
                (\c ->
                    { color = Cyan
                    , sections = [ "regular", "suppress" ]
                    , description =
                        [ "Include " ++ c Orange "suppressed" ++ " errors in the error report for all rules."
                        ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "unsuppress-rules"
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<rule1,rule2,...>"
                , mayBeUsedSeveralTimes = True
                , usesEquals = False
                }
      , display =
            Just
                (\c ->
                    { color = Cyan
                    , sections = [ "suppress" ]
                    , description =
                        [ "Include " ++ c Orange "suppressed" ++ " errors in the error report for the listed rules."
                        , "Specify the rules by their name, and separate them by commas."
                        ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "rules"
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<rule1,rule2,...>"
                , mayBeUsedSeveralTimes = True
                , usesEquals = False
                }
      , display =
            Just
                (\_ ->
                    { color = Cyan
                    , sections = [ "regular" ]
                    , description =
                        [ "Run with a subsection of the rules in the configuration."
                        , "Specify them by their name, and separate them by commas."
                        ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "watch"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display =
            Just
                (\c ->
                    { color = Cyan
                    , sections = [ "regular" ]
                    , description =
                        [ "Re-run " ++ c GreenBright "elm-review" ++ " automatically when your project or configuration"
                        , "changes. Use " ++ c Cyan "--watch-code" ++ " to re-run only on project changes."
                        , "You can use " ++ c Cyan "--watch" ++ " and " ++ c BlueBright "--fix" ++ " together."
                        ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "watch-code"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display = Nothing
      }
    , { name = "extract"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display =
            Just
                (\c ->
                    { color = Cyan
                    , sections = [ "regular" ]
                    , description =
                        [ "Enable extracting data from the project for the rules that have a"
                        , "data extractor. Requires running with " ++ c Cyan "--report=json" ++ "."
                        , "Learn more by reading the section about \"Extracting information\""
                        , "at https://bit.ly/3UmNr0V"
                        ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "elmjson"
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<path-to-elm.json>"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                }
      , display =
            Just
                (\_ ->
                    { color = Cyan
                    , sections = [ "regular", "prepare-offline" ]
                    , description =
                        [ "Specify the path to the elm.json file of the project. By default,"
                        , "the one in the current directory or its parent directories will be used."
                        ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "config"
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<path-to-review-directory>"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                }
      , display =
            Just
                (\_ ->
                    { color = Cyan
                    , sections = [ "regular", "init", "prepare-offline" ]
                    , description =
                        [ "Use the review configuration in the specified directory instead of the"
                        , "one found in the current directory or one of its parents."
                        ]
                    , initDescription =
                        Just
                            [ "Create the configuration files in the specified directory instead of in"
                            , "the review/ directory."
                            ]
                    , newPackageDescription = Nothing
                    }
                )
      }
    , templateFlag
    , { name = "compiler"
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<path-to-elm>"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                }
      , display =
            Just
                (\c ->
                    { color = Cyan
                    , sections = [ "regular", "init", "new-package", "prepare-offline" ]
                    , description =
                        [ "Specify the path to the " ++ c MagentaBright "elm" ++ " compiler."
                        ]
                    , initDescription =
                        Just
                            [ "Specify the path to the " ++ c MagentaBright "elm" ++ " compiler."
                            , "The " ++ c MagentaBright "elm" ++ " compiler is used to know the version of the compiler to write"
                            , "down in the " ++ c Yellow "review/elm.json" ++ " file’s \"elm-version\" field. Use this if you"
                            , "have multiple versions of the " ++ c MagentaBright "elm" ++ " compiler on your device."
                            ]
                    , newPackageDescription =
                        Just
                            [ "Specify the path to the " ++ c MagentaBright "elm" ++ " compiler."
                            , "The " ++ c MagentaBright "elm" ++ " compiler is used to know the version of the compiler to write"
                            , "down in the " ++ c Yellow "review/elm.json" ++ " file’s \"elm-version\" field. Use this if you"
                            , "have multiple versions of the " ++ c MagentaBright "elm" ++ " compiler on your device."
                            ]
                    }
                )
      }
    , { name = "rule-type"
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<module|project>"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                }
      , display =
            Just
                (\_ ->
                    { color = Cyan
                    , sections = [ "new-rule", "new-package" ]
                    , description =
                        [ "Whether the starting rule should be a module rule or a project rule."
                        , "Module rules are simpler but look at Elm modules in isolation, whereas"
                        , "project rules are more complex but have access to information from the"
                        , "entire project. You can always switch from a module rule to a project"
                        , "rule manually later on."
                        ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "version"
      , alias = Just "v"
      , argument = ArgumentAbsent
      , display =
            Just
                (\c ->
                    { color = Cyan
                    , sections = [ "regular" ]
                    , description =
                        [ "Print the version of the " ++ c GreenBright "elm-review" ++ " CLI."
                        ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "help"
      , alias = Just "h"
      , argument = ArgumentAbsent
      , display = Nothing
      }
    , { name = "debug"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display =
            Just
                (\c ->
                    { color = Cyan
                    , sections = [ "regular" ]
                    , description =
                        [ "Add helpful pieces of information for debugging purposes."
                        , "This will also run the compiler with " ++ c Cyan " --debug" ++ ", allowing you to use"
                        , c Yellow "Debug" ++ " functions in your custom rules."
                        ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "benchmark-info"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display =
            Just
                (\_ ->
                    { color = Cyan
                    , sections = [ "regular" ]
                    , description =
                        [ "Print out how much time it took for rules and phases of the process to"
                        , "run. This is meant for benchmarking purposes."
                        ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "color"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display = Nothing
      }
    , { name = "no-color"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display =
            Just
                (\_ ->
                    { color = Cyan
                    , sections = [ "regular" ]
                    , description = [ "Disable colors in the output." ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , reportFlag
    , { name = "no-details"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display =
            Just
                (\_ ->
                    { color = Cyan
                    , sections = [ "regular" ]
                    , description =
                        [ "Hide the details from error reports for a more compact view."
                        ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "details"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display = Nothing
      }
    , { name = "fix"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display =
            Just
                (\c ->
                    { color = BlueBright
                    , sections = [ "fix" ]
                    , description =
                        [ c GreenBright "elm-review" ++ " will present fixes for the errors that offer an automatic"
                        , "fix, which you can then accept or refuse one by one. When there are no"
                        , "more fixable errors left, " ++ c GreenBright "elm-review" ++ " will report the remaining errors as"
                        , "if it was called without " ++ c BlueBright " --fix" ++ "."
                        , "Fixed files will be reformatted using " ++ c MagentaBright "elm-format" ++ "."
                        ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "fix-all"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display =
            Just
                (\c ->
                    { color = BlueBright
                    , sections = [ "fix" ]
                    , description =
                        [ c GreenBright "elm-review" ++ " will present a single fix containing the application of all"
                        , "available automatic fixes, which you can then accept or refuse."
                        , "Afterwards, " ++ c GreenBright "elm-review" ++ " will report the remaining errors as if it was"
                        , "called without " ++ c BlueBright "--fix-all" ++ "."
                        , "Fixed files will be reformatted using " ++ c MagentaBright "elm-format" ++ "."
                        ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "fix-all-without-prompt"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display =
            Just
                (\c ->
                    { color = BlueBright
                    , sections = [ "fix" ]
                    , description =
                        [ "Same as " ++ c BlueBright "--fix-all" ++ " but fixes are applied without a prompt."
                        , "I recommend committing all changes prior to running with this option and"
                        , "reviewing the applied changes afterwards."
                        ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "fix-limit"
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "N"
                , mayBeUsedSeveralTimes = False
                , usesEquals = True
                }
      , display =
            Just
                (\_ ->
                    { color = BlueBright
                    , sections = [ "fix" ]
                    , description = [ "Limit the number of fixes applied in a single batch to N." ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "allow-remove-files"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display =
            Just
                (\_ ->
                    { color = BlueBright
                    , sections = [ "fix" ]
                    , description = [ "Allow files to be removed by automatic fixes." ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "explain-fix-failure"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display =
            Just
                (\_ ->
                    { color = BlueBright
                    , sections = [ "fix" ]
                    , description = [ "Get more information about fixes that failed to apply." ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "elm-format-path"
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<path-to-elm-format>"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
                }
      , display =
            Just
                (\c ->
                    { color = Cyan
                    , sections = [ "fix" ]
                    , description = [ "Specify the path to " ++ c MagentaBright "elm-format" ++ "." ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "ignore-problematic-dependencies"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display = Nothing
      }
    , { name = "FOR-TESTS"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display = Nothing
      }
    , { name = "force-build"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display = Nothing
      }
    , { name = "offline"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display =
            Just
                (\c ->
                    { color = Cyan
                    , sections = [ "regular" ]
                    , description =
                        [ "Prevent making network calls. You might need to run"
                        , c Yellow "elm-review prepare-offline" ++ " beforehand to avoid problems."
                        ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , gitHubAuthFlag
    , { name = "namespace"
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<namespace>"
                , mayBeUsedSeveralTimes = False
                , usesEquals = False
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
                }
      , display =
            Just
                (\_ ->
                    { color = Cyan
                    , sections = [ "regular" ]
                    , description =
                        [ "Ignore the reports of all rules for the specified directories."
                        ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "ignore-files"
      , alias = Nothing
      , argument =
            ArgumentPresent
                { argName = "<file1,file2,...>"
                , mayBeUsedSeveralTimes = True
                , usesEquals = False
                }
      , display =
            Just
                (\_ ->
                    { color = Cyan
                    , sections = [ "regular" ]
                    , description = [ "Ignore the reports of all rules for the specified files." ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
      }
    , { name = "check-after-tests"
      , alias = Nothing
      , argument = ArgumentAbsent
      , display =
            Just
                (\c ->
                    { color = Cyan
                    , sections = [ "suppress-subcommand" ]
                    , description =
                        [ "Checks whether there are uncommitted suppression files. They may get"
                        , "updated when running " ++ c GreenBright "elm-review" ++ ", which people can forget to commit"
                        , "before making a pull request. Running " ++ c Orange "elm-review suppress" ++ " with this flag"
                        , "at the end of your test suite makes sure these files stay up to date."
                        , "This command does not cause your project to be reviewed though."
                        ]
                    , initDescription = Nothing
                    , newPackageDescription = Nothing
                    }
                )
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
            }
    , display =
        Just
            (\c ->
                { color = Cyan
                , sections = []
                , description =
                    [ "To be used along with " ++ c Cyan "--template" ++ " to avoid GitHub rate limiting."
                    , "Follow https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token to create an API token. The API token needs access to public repositories."
                    , ""
                    , "Then use the flag like this:"
                    , c GreenBright "  --github-auth=github_pat_abcdef01234567890"
                    ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
            )
    }


reportFlag : Flag
reportFlag =
    { name = "report"
    , alias = Nothing
    , argument =
        ArgumentPresent
            { argName = "<json or ndjson>"
            , mayBeUsedSeveralTimes = False
            , usesEquals = True
            }
    , display =
        Just
            (\c ->
                { color = Cyan
                , sections = [ "regular" ]
                , description =
                    [ "Error reports will be in JSON format. " ++ c Magenta "json" ++ " prints a single JSON object"
                    , "while " ++ c Magenta "ndjson" ++ " will print one JSON object per error each on a new line."
                    , "The formats are described in this document: https://bit.ly/31F6jzz"
                    ]
                , initDescription = Nothing
                , newPackageDescription = Nothing
                }
            )
    }


templateFlag : Flag
templateFlag =
    { name = "template"
    , alias = Nothing
    , argument =
        ArgumentPresent
            { argName = "<author>/<repo>[/path-to-the-config-folder][#branch-or-commit]"
            , mayBeUsedSeveralTimes = False
            , usesEquals = False
            }
    , display =
        Just
            (\c ->
                { color = Cyan
                , sections = [ "regular", "init" ]
                , description =
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
                        [ "Copy the review configuration from a GitHub repository, at the root or"
                        , "in a folder. Examples:"
                        , "- elm-review init --template author/elm-review-configuration"
                        , "- elm-review init --template jfmengels/elm-review-config/package"
                        , "- elm-review init --template jfmengels/elm-review-config/application"
                        , "- elm-review init --template jfmengels/elm-review-unused/example#master"
                        ]
                , newPackageDescription = Nothing
                }
            )
    }


colorize : Bool -> Flags.Color -> String -> String
colorize colorsAreSupported =
    if colorsAreSupported then
        \color str -> "\u{001B}[" ++ toRGB color ++ "m" ++ str ++ "\u{001B}[39m"

    else
        \_ str -> str


supportsColor : { env | args : List String, env : Dict String String } -> Bool
supportsColor { env, args } =
    case Dict.get "FORCE_COLOR" env of
        Just "1" ->
            True

        Just _ ->
            False

        Nothing ->
            if Dict.member "NO_COLOR" env then
                False

            else
                True


toRGB : Flags.Color -> String
toRGB color =
    case color of
        Cyan ->
            "38;2;51;187;200"

        Orange ->
            "38;2;255;165;0"

        Yellow ->
            "38;2;232;195;56"

        Magenta ->
            "35"

        GreenBright ->
            "92"

        BlueBright ->
            "94"

        MagentaBright ->
            "95"
