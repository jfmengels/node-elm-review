module Elm.Review.ElmRunMain exposing (main)

import Capabilities exposing (Console, Stdin)
import Cli as ElmRunCli exposing (Env)
import Elm.Review.Main as Main
import Elm.Review.Options as Options
import Elm.Review.Testable as Testable exposing (Effects)
import Elm.Review.Testable.CliData as CliData
import Elm.Review.Testable.FsData as FsData
import Elm.Review.Testable.ProcessData as ProcessData exposing (ProcessError, SpawnError)
import ElmReview.Color as Color
import ElmReview.Problem as Problem exposing (Problem)
import ElmReview.ReportMode as ReportMode
import Fs as ElmRunFs exposing (FileSystem, FsError(..))
import Http
import Os exposing (ProcessCapability)
import Os.Process as ElmRunProcess
import Task exposing (Task)


type ModelWrapper
    = Done
    | Running Model


type alias Model =
    { fs : FileSystem
    , os : ProcessCapability
    , stdout : Console
    , stderr : Console
    , mainModel : Main.Model
    }


main : ElmRunCli.Program ModelWrapper Main.Msg
main =
    ElmRunCli.program
        { init = init
        , update = update
        , subscriptions = subscriptions
        }


init : Env -> ( ModelWrapper, Cmd Main.Msg )
init env =
    case Result.map2 Tuple.pair (requireCapabilities env) (Options.parse env.args) of
        Ok ( { fs, os }, options ) ->
            case Main.init env.stdin options of
                Ok ( mainModel, cmd ) ->
                    ( Running
                        { fs = fs
                        , os = os
                        , stdout = env.stdout
                        , stderr = env.stderr
                        , mainModel = mainModel
                        }
                    , Testable.cmd (effects fs os env.stdout env.stderr) cmd
                    )

                Err cmd ->
                    ( Done
                    , Testable.cmd (effects fs os env.stdout env.stderr) cmd
                    )

        Err err ->
            ( Done
            , stop env.stderr (roughFormatOptions env.args) err
            )


update : Main.Msg -> ModelWrapper -> ( ModelWrapper, Cmd Main.Msg )
update msg modelWrapper =
    case modelWrapper of
        Done ->
            ( Done, Cmd.none )

        Running { fs, os, stdout, stderr, mainModel } ->
            let
                ( newMainModel, cmd ) =
                    Main.update msg mainModel
            in
            ( Running
                { fs = fs
                , os = os
                , stdout = stdout
                , stderr = stderr
                , mainModel = newMainModel
                }
            , Testable.cmd (effects fs os stdout stderr) cmd
            )


subscriptions : ModelWrapper -> Sub Main.Msg
subscriptions model =
    case model of
        Done ->
            Sub.none

        Running { mainModel } ->
            Main.subscriptions mainModel


stop : Console -> Problem.FormatOptions options -> Problem -> Cmd msg
stop stderr formatOptions problem =
    Cmd.batch
        [ ElmRunCli.println stderr (Problem.format formatOptions problem)
        , ElmRunCli.exit 1
        ]


roughFormatOptions : List String -> Problem.FormatOptions { attemptFutureRecovery : Bool }
roughFormatOptions args =
    { color = Color.noColors
    , reportMode =
        if List.member "--report=json" args || List.member "--report=ndjson" args then
            ReportMode.Json

        else
            ReportMode.HumanReadable
    , debug = List.member "--debug" args
    , attemptFutureRecovery = False
    }


requireCapabilities : Env -> Result Problem { fs : FileSystem, os : ProcessCapability }
requireCapabilities env =
    Result.map2 (\fs os -> { fs = fs, os = os })
        (ElmRunFs.require env)
        (Os.requireProcess env)
        |> Result.mapError
            (\err ->
                Problem.from Problem.Unrecoverable
                    { title = "MISSING CAPABILITIES"
                    , message = \_ -> "elm-review was run with missing capabilities:\n\n    " ++ err
                    }
            )


effects : FileSystem -> ProcessCapability -> Console -> Console -> Effects
effects fs os stdout stderr =
    { -- File system
      readTextFile = \path -> ElmRunFs.readTextFile fs path |> Task.mapError mapFsError
    , writeTextFile = \path string -> ElmRunFs.writeTextFile fs path string |> Task.mapError mapFsError
    , stat = \path -> ElmRunFs.stat fs path |> Task.mapError mapFsError
    , deleteFile = \path -> ElmRunFs.deleteFile fs path |> Task.mapError mapFsError
    , createDirectory = \path -> ElmRunFs.createDirectory fs path |> Task.mapError mapFsError
    , removeDirectory = \path -> ElmRunFs.removeDirectory fs path |> Task.mapError mapFsError
    , copyDirectory = copyDirectory os
    , walkTree = \path pattern matchKind -> ElmRunFs.walkTree fs path pattern (mapMatchKind matchKind) |> Task.map Tuple.first |> Task.mapError mapFsError

    -- Http
    , httpGet = httpGet

    -- Stdin / Stdout
    , readKey = Debug.todo "effects: readKey"
    , println = mapConsole stdout stderr >> ElmRunCli.println
    , exit = ElmRunCli.exit

    -- Process
    , runProcess = runProcess os
    , spawnProcess = spawnProcess os
    , waitProcess = ElmRunProcess.wait os >> Task.mapError mapProcessError
    , killProcess = \pid signal -> ElmRunProcess.kill os pid signal |> Task.mapError mapProcessError
    }


httpGet : String -> Task () String
httpGet url =
    Http.task
        { method = "GET"
        , url = url
        , headers = []
        , body = Http.emptyBody
        , resolver =
            Http.stringResolver
                (\response ->
                    case response of
                        Http.GoodStatus_ _ body ->
                            Ok body

                        _ ->
                            Err ()
                )
        , timeout = Nothing
        }


mapFsError : ElmRunFs.FsError -> FsData.FsError
mapFsError fsError =
    case fsError of
        ElmRunFs.PermissionDenied ->
            FsData.PermissionDenied

        ElmRunFs.NotFound string ->
            FsData.NotFound string

        ElmRunFs.IoError string ->
            FsData.IoError string


mapConsole : Capabilities.Console -> Capabilities.Console -> CliData.Console -> Capabilities.Console
mapConsole stdout stderr console =
    case console of
        CliData.Stdout ->
            stdout

        CliData.Stderr ->
            stderr


copyDirectory : ProcessCapability -> { from : String, to : String } -> Task SpawnError ()
copyDirectory os { from, to } =
    runProcess os
        "cp"
        { cwd = Nothing
        , env = Nothing
        , args = [ "-R", from, to ]
        , stdin = ProcessData.NullStdin
        , stdout = ProcessData.NullStdout
        , stderr = ProcessData.NullStderr
        }
        |> Task.map (\_ -> ())


{-| Like `Os.Process.run`, but fails if the exit code is different from 0.
-}
runProcess :
    ProcessCapability
    -> String
    -> ProcessData.SpawnOptions
    -> Task ProcessData.SpawnError ProcessData.Completed
runProcess os command spawnOptions =
    ElmRunProcess.run os command (mapSpawnOptions spawnOptions)
        |> Task.mapError (mapProcessError >> ProcessData.ProcessRunError)
        |> Task.andThen
            (\completed ->
                if completed.exitCode == 0 then
                    Task.succeed completed

                else if completed.exitCode == commandNotFound then
                    Task.fail ProcessData.CommandNotFound

                else
                    Task.fail (ProcessData.CommandFailed completed)
            )


{-| Like `Os.Process.spawn`, but fails if the exit code is different from 0.
-}
spawnProcess :
    ProcessCapability
    -> String
    -> ProcessData.SpawnOptions
    -> Task ProcessError ElmRunProcess.ProcessId
spawnProcess os command spawnOptions =
    ElmRunProcess.spawn os command (mapSpawnOptions spawnOptions)
        |> Task.mapError mapProcessError
        |> Task.map .pid


mapProcessError : ElmRunProcess.ProcessError -> ProcessData.ProcessError
mapProcessError processError =
    case processError of
        ElmRunProcess.PermissionDenied ->
            ProcessData.PermissionDenied

        ElmRunProcess.CaptureLimitExceeded string ->
            ProcessData.CaptureLimitExceeded string

        ElmRunProcess.ProcessError string ->
            ProcessData.ProcessError string


mapMatchKind : FsData.MatchKind -> ElmRunFs.MatchKind
mapMatchKind matchKind =
    case matchKind of
        FsData.Any ->
            ElmRunFs.Any

        FsData.File ->
            ElmRunFs.File

        FsData.Directory ->
            ElmRunFs.Directory


mapSpawnOptions : ProcessData.SpawnOptions -> ElmRunProcess.SpawnOptions
mapSpawnOptions spawnOptions =
    { args = spawnOptions.args
    , cwd = spawnOptions.cwd
    , env = spawnOptions.env
    , stdin = mapStdinSpec spawnOptions.stdin
    , stdout = mapStdoutSpec spawnOptions.stdout
    , stderr = mapStderrSpec spawnOptions.stderr
    }


mapStdinSpec : ProcessData.StdinSpec -> ElmRunProcess.StdinSpec
mapStdinSpec spec =
    case spec of
        ProcessData.InheritStdin ->
            ElmRunProcess.InheritStdin

        ProcessData.NullStdin ->
            ElmRunProcess.NullStdin

        ProcessData.TextStdin string ->
            ElmRunProcess.TextStdin string

        ProcessData.FileStdin string ->
            ElmRunProcess.FileStdin string


mapStdoutSpec : ProcessData.StdoutSpec -> ElmRunProcess.StdoutSpec
mapStdoutSpec spec =
    case spec of
        ProcessData.InheritStdout ->
            ElmRunProcess.InheritStdout

        ProcessData.NullStdout ->
            ElmRunProcess.NullStdout

        ProcessData.CaptureStdout limit ->
            ElmRunProcess.CaptureStdout (mapCaptureLimit limit)


mapStderrSpec : ProcessData.StderrSpec -> ElmRunProcess.StderrSpec
mapStderrSpec spec =
    case spec of
        ProcessData.InheritStderr ->
            ElmRunProcess.InheritStderr

        ProcessData.NullStderr ->
            ElmRunProcess.NullStderr

        ProcessData.CaptureStderr limit ->
            ElmRunProcess.CaptureStderr (mapCaptureLimit limit)

        ProcessData.MergeWithStdout ->
            ElmRunProcess.MergeWithStdout


mapCaptureLimit : ProcessData.CaptureLimit -> ElmRunProcess.CaptureLimit
mapCaptureLimit spec =
    { maxBytes = spec.maxBytes
    , onOverflow = mapOverflowPolicy spec.onOverflow
    }


mapOverflowPolicy : ProcessData.OverflowPolicy -> ElmRunProcess.OverflowPolicy
mapOverflowPolicy policy =
    case policy of
        ProcessData.FailProcess ->
            ElmRunProcess.FailProcess

        ProcessData.TruncateOutput ->
            ElmRunProcess.TruncateOutput


{-| Error code when command was not found.
-}
commandNotFound : Int
commandNotFound =
    127
