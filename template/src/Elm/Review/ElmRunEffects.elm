module Elm.Review.ElmRunEffects exposing (effects, subEffects)

import Capabilities exposing (Console, FileWatcher, Stdin)
import Cli as ElmRunCli exposing (Env)
import Elm.Review.Testable exposing (Effects)
import Elm.Review.Testable.CliData as CliData
import Elm.Review.Testable.FileWatchData as FileWatcherData exposing (FileEvent, WatchOptions)
import Elm.Review.Testable.FsData as FsData
import Elm.Review.Testable.ProcessData as ProcessData exposing (ProcessError, SpawnError)
import Elm.Review.Testable.StdinData as StdinData
import Elm.Review.Testable.TSub as TSub
import ElmReview.Path exposing (Path)
import Fs as ElmRunFs exposing (FileSystem, FsError(..))
import Http
import Os exposing (ProcessCapability)
import Os.Process as ElmRunProcess
import Stdin as ElmRunStdin
import Task exposing (Task)
import Worker.FileWatcher as FileWatcher


effects : FileSystem -> ProcessCapability -> Maybe Stdin -> Console -> Console -> Effects
effects fs os stdin stdout stderr =
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
    , readKey = readKey stdin
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


readKey : Maybe Stdin -> () -> Task StdinData.StdinError StdinData.Key
readKey stdin =
    \() ->
        case stdin of
            Just stdin_ ->
                ElmRunStdin.readKey stdin_
                    |> Task.map mapStdinKey
                    |> Task.mapError mapStdinError

            Nothing ->
                Task.fail StdinData.PermissionDenied


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


mapStdinError : ElmRunStdin.StdinError -> StdinData.StdinError
mapStdinError stdinError =
    case stdinError of
        ElmRunStdin.PermissionDenied ->
            StdinData.PermissionDenied

        ElmRunStdin.EndOfInput ->
            StdinData.EndOfInput

        ElmRunStdin.IoError string ->
            StdinData.IoError string


mapStdinKey : ElmRunStdin.Key -> StdinData.Key
mapStdinKey key =
    case key of
        ElmRunStdin.KeyChar char ->
            StdinData.KeyChar char

        ElmRunStdin.KeyCtrl char ->
            StdinData.KeyCtrl char

        ElmRunStdin.KeyEnter ->
            StdinData.KeyEnter

        ElmRunStdin.KeyBackspace ->
            StdinData.KeyBackspace

        ElmRunStdin.KeyDelete ->
            StdinData.KeyDelete

        ElmRunStdin.KeyEscape ->
            StdinData.KeyEscape

        ElmRunStdin.KeyArrowUp ->
            StdinData.KeyArrowUp

        ElmRunStdin.KeyArrowDown ->
            StdinData.KeyArrowDown

        ElmRunStdin.KeyArrowLeft ->
            StdinData.KeyArrowLeft

        ElmRunStdin.KeyArrowRight ->
            StdinData.KeyArrowRight

        ElmRunStdin.KeyHome ->
            StdinData.KeyHome

        ElmRunStdin.KeyEnd ->
            StdinData.KeyEnd

        ElmRunStdin.KeyPageUp ->
            StdinData.KeyPageUp

        ElmRunStdin.KeyPageDown ->
            StdinData.KeyPageDown

        ElmRunStdin.KeyMouseWheelUp ->
            StdinData.KeyMouseWheelUp

        ElmRunStdin.KeyMouseWheelDown ->
            StdinData.KeyMouseWheelDown


subEffects : TSub.SubEffects msg
subEffects =
    { watchFiles = watchFiles (watchPermission ())
    }


watchFiles : Maybe FileWatcher -> Path -> WatchOptions -> (FileEvent -> msg) -> Sub msg
watchFiles maybeFileWatcher =
    case maybeFileWatcher of
        Just fileWatcher ->
            \path watchOptions toMsg ->
                FileWatcher.watch fileWatcher path watchOptions toMsg

        Nothing ->
            \_ _ _ -> Sub.none


watchPermission : () -> Maybe FileWatcher
watchPermission () =
    -- TODO Get FileWatcher permission from somewhere
    Nothing
