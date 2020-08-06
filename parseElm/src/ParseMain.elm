port module ParseMain exposing (main)

import AstCodec
import Dependencies
import Elm.Parser as Parser
import Elm.Processing
import Elm.Syntax.File exposing (File)
import Json.Encode as Encode


port requestParsing : (String -> msg) -> Sub msg


port parseResult : Encode.Value -> Cmd msg


main : Program () () Msg
main =
    Platform.worker
        { init = always ( (), Cmd.none )
        , update = update
        , subscriptions = always subscriptions
        }


subscriptions : Sub Msg
subscriptions =
    requestParsing GotFile


type Msg
    = GotFile String


update : Msg -> () -> ( (), Cmd Msg )
update (GotFile source) () =
    parseSource source
        |> Result.map AstCodec.encode
        |> Result.withDefault Encode.null
        |> parseResult
        |> Tuple.pair ()


{-| Parse source code into a AST
-}
parseSource : String -> Result () File
parseSource source =
    source
        |> Parser.parse
        |> Result.mapError (always ())
        |> Result.map (Elm.Processing.process elmProcessContext)


elmProcessContext : Elm.Processing.ProcessContext
elmProcessContext =
    Elm.Processing.init
        |> Elm.Processing.addDependency Dependencies.elmCore
        |> Elm.Processing.addDependency Dependencies.elmUrl
        |> Elm.Processing.addDependency Dependencies.elmParser
