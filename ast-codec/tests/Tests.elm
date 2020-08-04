module Tests exposing (someCode, suite)

import AstCodec
import Elm.Parser
import Elm.Processing
import Elm.Syntax.File exposing (File)
import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer, int, list, string)
import Test exposing (..)


someCode =
    """module AstCodec exposing (decode, encode)

import Serialize as S exposing (Codec)


encode : File -> String
encode file_ =
   S.encodeToString file file_"""


suite : Test
suite =
    describe "codec tests"
        [ test "test" <|
            \_ ->
                case Elm.Parser.parse someCode of
                    Ok rawFile ->
                        let
                            file : File
                            file =
                                Elm.Processing.process Elm.Processing.init rawFile
                        in
                        AstCodec.encode file |> AstCodec.decode |> Expect.equal (Ok file)

                    Err _ ->
                        Expect.fail "Failed to parse"
        ]
