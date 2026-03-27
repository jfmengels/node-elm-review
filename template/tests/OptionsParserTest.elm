module OptionsParserTest exposing (all)

import Dict
import Expect exposing (Expectation)
import Test exposing (Test, describe, test)
import Wrapper.Options.Parser as OptionsParser exposing (OptionsParseResult(..))


all : Test
all =
    describe "Wrapper.Flags.parse"
        [ test "Parse --app" <|
            \() ->
                { env = Dict.empty
                , args = [ "--app", "binaryLocation" ]
                }
                    |> OptionsParser.parse
                    |> Expect.equal
                        (ParseSuccess
                            { subCommand = Nothing
                            , help = False
                            , directoriesToAnalyze = []
                            , appBinary = "binaryLocation"
                            }
                        )
        ]
