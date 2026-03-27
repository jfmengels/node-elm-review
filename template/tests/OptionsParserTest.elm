module OptionsParserTest exposing (all)

import Dict
import Expect exposing (Expectation)
import Test exposing (Test, describe, test)
import Wrapper.Color as Color
import Wrapper.Options exposing (Options)
import Wrapper.Options.Parser as OptionsParser exposing (OptionsParseResult(..))
import Wrapper.Subcommand as Subcommand


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
        ]


expectEqual : Options -> OptionsParseResult -> Expectation
expectEqual expected received =
    case received of
        ParseSuccess result ->
            Expect.equal expected result

        ParseError { title, message } ->
            Expect.fail ("Unexpected parsing failure:\n\n" ++ title ++ "\n\n" ++ message)
