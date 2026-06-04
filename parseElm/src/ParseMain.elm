port module ParseMain exposing (main)

import Elm.Parser as Parser
import Elm.Processing
import Elm.Syntax.File exposing (File)
import Json.Encode as Encode
import Parser


port requestParsing : ({ path : String, source : String } -> msg) -> Sub msg


port parseResult : { path : String, output : String } -> Cmd msg


main : Program () () Msg
main =
    Platform.worker
        { init = always ( (), Cmd.none )
        , update = \msg _ -> ( (), update msg )
        , subscriptions = always subscriptions
        }


subscriptions : Sub Msg
subscriptions =
    requestParsing GotFile


type Msg
    = GotFile { path : String, source : String }


update : Msg -> Cmd Msg
update (GotFile { path, source }) =
    parseResult
        { path = path
        , output =
            case parseSource source of
                Ok ast ->
                    Elm.Syntax.File.encode ast
                        |> Encode.encode 2

                Err error ->
                    error
        }


{-| Parse source code into a AST
-}
parseSource : String -> Result String File
parseSource source =
    case Parser.parse source of
        Ok ast ->
            Ok (Elm.Processing.process Elm.Processing.init ast)

        Err error ->
            ("ERROR: " ++ Parser.deadEndsToString error)
                |> Err
