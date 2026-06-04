module ParseMain exposing (main)

import Cli exposing (Env)
import Elm.Parser as Parser
import Elm.Syntax.File exposing (File)
import Fs
import Fs.Location as Location
import Fs.Path as Path
import Fs.Walk as Walk
import Json.Encode as Encode
import Parser exposing (Problem)
import Parser.Error
import Task exposing (Task)
import Worker.Capabilities exposing (Console)


main : Cli.Program Console Msg
main =
    Cli.program
        { init = \env -> ( env.stdout, init env )
        , update = update
        , subscriptions = \_ -> Sub.none
        }


type Msg
    = Done (Result Fs.FsError ())


init : Env -> Cmd Msg
init env =
    case Fs.require env of
        Err error ->
            Cli.println env.stderr error

        Ok fs ->
            let
                directory : Location.Dir
                directory =
                    List.head env.args
                        |> Maybe.withDefault "."
                        |> Location.dir
            in
            findAllElmFiles fs directory
                |> Task.attempt Done


update : Msg -> Console -> ( Console, Cmd msg )
update (Done result) stdout =
    ( stdout
    , case result of
        Ok () ->
            Cli.println stdout "Success"

        Err error ->
            Cli.println stdout ("ERROR: " ++ Fs.errorToString error)
    )


outputFolder : Location.Dir
outputFolder =
    Location.dir "ast"


findAllElmFiles :
    Fs.FileSystem
    -> Location.Dir
    -> Task Fs.FsError ()
findAllElmFiles fs dir =
    Walk.foldM fs
        dir
        { maxDepth = -1
        , batchSize = 256
        , kind = Fs.File
        , pattern = Just "*.elm"
        }
        (\entry () ->
            case Location.toFile entry.location of
                Just file_ ->
                    case Location.relativePathFrom dir file_ of
                        Just relativePath ->
                            Fs.readTextFile fs file_
                                |> Task.andThen
                                    (\source ->
                                        let
                                            outputPath : Location.File
                                            outputPath =
                                                Location.childFile
                                                    (Path.toString relativePath |> String.replace ".elm" ".txt")
                                                    outputFolder
                                        in
                                        Fs.createDirectory fs (Location.parent (Location.fromFile outputPath) |> Maybe.withDefault outputFolder)
                                            |> Task.andThen
                                                (\() ->
                                                    parseSource source
                                                        |> Fs.writeTextFile fs outputPath
                                                )
                                    )
                                |> Task.map Walk.Continue

                        Nothing ->
                            Task.succeed (Walk.Continue ())

                Nothing ->
                    Task.succeed (Walk.Continue ())
        )
        ()
        |> Task.map (\_ -> ())


parseSource : String -> String
parseSource source =
    case Parser.parseToFile source of
        Ok ast ->
            ast
                |> Elm.Syntax.File.encode
                |> Encode.encode 2

        Err error ->
            "ERROR: " ++ errorToString source error


errorToString : String -> List Parser.DeadEnd -> String
errorToString src deadEnds =
    Parser.Error.renderError
        { text = identity
        , formatContext = identity
        , formatCaret = identity
        , newline = "\n"
        , linesOfExtraContext = 3
        }
        Parser.Error.forParser
        src
        deadEnds
        |> String.concat
