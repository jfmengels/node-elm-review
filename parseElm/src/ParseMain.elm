port module ParseMain exposing (main)

import Dependencies
import Elm.Parser as Parser
import Elm.Processing
import Elm.Syntax.File exposing (File)
import Json.Encode as Encode


port requestParsing : ({ path : String, source : String } -> msg) -> Sub msg


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
    = GotFile { path : String, source : String }


update : Msg -> () -> ( (), Cmd Msg )
update (GotFile { path, source }) () =
    Encode.object
        [ ( "path", Encode.string path )
        , ( "ast"
          , parseSource source
                |> Result.map Elm.Syntax.File.encode
                |> Result.withDefault Encode.null
          )
        ]
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
