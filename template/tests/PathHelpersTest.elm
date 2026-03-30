module PathHelpersTest exposing (all)

import Expect
import Test exposing (Test, describe, test)
import Wrapper.PathHelpers as PathHelpers


all : Test
all =
    describe "Wrapper.PathHelpers"
        [ test "should leave the path untouched if it does not contain odd characters" <|
            \() ->
                let
                    input : String
                    input =
                        "some-folder123"
                in
                input
                    |> PathHelpers.format
                    |> Expect.equal input
        , test "should escape single quotes" <|
            \() ->
                "Don't-do-that"
                    |> PathHelpers.format
                    |> Expect.equal "Don\\'t-do-that"
        , test "should escape double quotes" <|
            \() ->
                """Don"t-do-that"""
                    |> PathHelpers.format
                    |> Expect.equal """Don\\"t-do-that"""
        , test "should escape spaces" <|
            \() ->
                "some path"
                    |> PathHelpers.format
                    |> Expect.equal "some\\ path"
        , test "should escape *" <|
            \() ->
                "some*path"
                    |> PathHelpers.format
                    |> Expect.equal "some\\*path"
        ]
