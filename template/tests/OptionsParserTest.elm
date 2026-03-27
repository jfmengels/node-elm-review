module OptionsParserTest exposing (all)

import Dict
import Expect exposing (Expectation)
import Test exposing (Test, describe, test)
import Wrapper.Color as Color
import Wrapper.Options exposing (Options)
import Wrapper.Options.Parser as OptionsParser exposing (OptionsParseResult(..))
import Wrapper.Problem as Problem
import Wrapper.Subcommand as Subcommand exposing (Subcommand)


all : Test
all =
    describe "Wrapper.Flags.parse"
        [ test "Parse --app" <|
            \() ->
                { env = Dict.empty
                , args = [ "--app", "binaryLocation" ]
                }
                    |> OptionsParser.parse
                    |> expectEqual
                        { subcommand = Nothing
                        , help = False
                        , directoriesToAnalyze = []
                        , appBinary = "binaryLocation"
                        }
        , test "Parse subcommand init" <|
            \() ->
                { env = Dict.empty
                , args = [ "init", "--app", "binaryLocation" ]
                }
                    |> OptionsParser.parse
                    |> expectEqual
                        { subcommand = Just Subcommand.Init
                        , help = False
                        , directoriesToAnalyze = []
                        , appBinary = "binaryLocation"
                        }
        , test "Consider unknown args as directories to analyze" <|
            \() ->
                { env = Dict.empty
                , args = [ "unknown", "--app", "binaryLocation", "other" ]
                }
                    |> OptionsParser.parse
                    |> expectEqual
                        { subcommand = Nothing
                        , help = False
                        , directoriesToAnalyze = [ "other", "unknown" ]
                        , appBinary = "binaryLocation"
                        }
        , test "Enter help mode if --help is used" <|
            \() ->
                { env = Dict.empty
                , args = [ "--help" ]
                }
                    |> OptionsParser.parse
                    |> expectHelp Nothing
        , test "Enter help mode for init if `init --help` is used" <|
            \() ->
                { env = Dict.empty
                , args = [ "init", "--help" ]
                }
                    |> OptionsParser.parse
                    |> expectHelp (Just Subcommand.Init)
        , test "--help can be used before the subcommand" <|
            \() ->
                { env = Dict.empty
                , args = [ "--help", "init" ]
                }
                    |> OptionsParser.parse
                    |> expectHelp (Just Subcommand.Init)
        , test "Enter help mode by using the -h shorthand" <|
            \() ->
                { env = Dict.empty
                , args = [ "-h" ]
                }
                    |> OptionsParser.parse
                    |> expectHelp Nothing
        ]


expectEqual : Options -> OptionsParseResult -> Expectation
expectEqual expected received =
    case received of
        ParseSuccess result ->
            Expect.equal expected result

        ShowHelp _ subcommand ->
            Expect.fail ("Unexpected showing of help with subcommand " ++ Debug.toString subcommand)

        ParseError _ problem ->
            let
                { title, message } =
                    Problem.unwrapFOR_TESTS problem
            in
            Expect.fail ("Unexpected parsing failure:\n\n" ++ title ++ "\n\n" ++ message (Color.toAnsi Color.noColors))


expectHelp : Maybe Subcommand -> OptionsParseResult -> Expectation
expectHelp expectedSubcommand received =
    case received of
        ShowHelp _ subcommand ->
            Expect.equal expectedSubcommand subcommand

        ParseSuccess _ ->
            Expect.fail "Unexpected parse success without help"

        ParseError _ problem ->
            let
                { title, message } =
                    Problem.unwrapFOR_TESTS problem
            in
            Expect.fail ("Unexpected parsing failure:\n\n" ++ title ++ "\n\n" ++ message (Color.toAnsi Color.noColors))
