module FlagsTest exposing (all)

import Dict
import Expect exposing (Expectation)
import Test exposing (Test, describe, test)
import Wrapper.Flags


all : Test
all =
    describe "Wrapper.Flags.parse"
        [ test "Parse --app" <|
            \() ->
                { env = Dict.empty
                , args = [ "--app", "binaryLocation" ]
                }
                    |> Wrapper.Flags.parse
                    |> Expect.equal
                        (Ok
                            { subCommand = Nothing
                            , help = False
                            , directoriesToAnalyze = []
                            , appBinary = "binaryLocation"
                            }
                        )
        ]
