port module ParseMain exposing (main)

import Dependencies
import Elm.Parser as Parser
import Elm.Processing
import Elm.Review.AstCodec as AstCodec
import Elm.Syntax.File exposing (File)
import Json.Encode as Encode


port requestParsing : (String -> msg) -> Sub msg


port parseResult : Encode.Value -> Cmd msg


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
    = GotFile String


update : Msg -> Cmd Msg
update (GotFile source) =
    let
        json : Encode.Value
        json =
            case parseSource source of
                Ok ast ->
                    AstCodec.encode ast

                Err _ ->
                    Encode.null
    in
    parseResult json


{-| Parse source code into a AST
-}
parseSource : String -> Result () File
parseSource source =
    case Parser.parse source of
        Ok ast ->
            Ok (Elm.Processing.process elmProcessContext ast)

        Err _ ->
            Err ()


elmProcessContext : Elm.Processing.ProcessContext
elmProcessContext =
    Elm.Processing.init
        |> Elm.Processing.addDependency Dependencies.elmCore
        |> Elm.Processing.addDependency Dependencies.elmUrl
        |> Elm.Processing.addDependency Dependencies.elmParser
