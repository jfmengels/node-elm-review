module ElmRun.Effects exposing (effects, subEffects)

import Bytes exposing (Bytes)
import Capabilities exposing (Console, FileWatcher, Stdin)
import Cli as ElmRunCli exposing (Env)
import Elm.Review.Testable exposing (Effects)
import Elm.Review.Testable.CliData as CliData
import Elm.Review.Testable.FileWatchData exposing (FileEvent, WatchOptions)
import Elm.Review.Testable.FsData as FsData
import Elm.Review.Testable.ProcessData as ProcessData exposing (ProcessError, SpawnError)
import Elm.Review.Testable.StdinData as StdinData
import Elm.Review.Testable.TSub as TSub
import ElmReview.Path exposing (Path)
import Fs as ElmRunFs exposing (FileSystem, FsError(..))
import Fs.Error
import Fs.FileWatcher as FileWatcher
import Fs.Location
import Fs.Path
import Fs.Walk as Walk
import Http
import Os exposing (ProcessCapability)
import Os.Process as ElmRunProcess
import Stdin as ElmRunStdin
import Task exposing (Task)


effects : FileSystem -> ProcessCapability -> Maybe Stdin -> Console -> Console -> Effects
effects fs os stdin stdout stderr =
    { -- File system
      readTextFile = \path -> ElmRunFs.readTextFile fs (Fs.Location.file path) |> Task.mapError mapFsError
    , writeTextFile = \path string -> ElmRunFs.writeTextFile fs (Fs.Location.file path) string |> Task.mapError mapFsError
    , writeBytes = \path bytes -> ElmRunFs.writeBytes fs (Fs.Location.file path) bytes |> Task.mapError mapFsError
    , stat = \path -> ElmRunFs.stat fs (Fs.Location.fromFile (Fs.Location.file path)) |> Task.map toTestableStat |> Task.mapError mapFsError
    , list = \path -> ElmRunFs.list fs (Fs.Location.dir path) |> Task.map (List.map toTestableEntry) |> Task.mapError mapFsError
    , deleteFile = \path -> ElmRunFs.deleteFile fs (Fs.Location.file path) |> Task.mapError mapFsError
    , createSymlink = createSymlink fs
    , createDirectory = \path -> ElmRunFs.createDirectory fs (Fs.Location.dir path) |> Task.mapError mapFsError
    , removeDirectory = \path -> ElmRunFs.removeDirectory fs (Fs.Location.dir path) |> Task.mapError mapFsError
    , copyDirectory = copyDirectory fs
    , walkTree = walkTree fs

    -- Http
    , httpGetString = httpGetString
    , httpGetBytes = httpGetBytes

    -- Stdin / Stdout
    , readKey = readKey stdin
    , readLine = readLine stdin
    , println = mapConsole stdout stderr >> ElmRunCli.println
    , printlnStderrThenExit = \message exitCode -> Cmd.batch [ ElmRunCli.println stderr message, ElmRunCli.exit exitCode ]
    , printlnTask = mapConsole stdout stderr >> ElmRunCli.printlnTask
    , exit = ElmRunCli.exit

    -- Process
    , runProcess = runProcess os
    , spawnProcess = spawnProcess os
    , waitProcess = ElmRunProcess.wait os >> Task.mapError mapProcessError
    , killProcess = \pid signal -> ElmRunProcess.kill os pid signal |> Task.mapError mapProcessError
    }


httpGetString : String -> Task () String
httpGetString url =
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


httpGetBytes : String -> Task () Bytes
httpGetBytes url =
    Http.task
        { method = "GET"
        , url = url
        , headers = []
        , body = Http.emptyBody
        , resolver =
            Http.bytesResolver
                (\response ->
                    case response of
                        Http.GoodStatus_ _ body ->
                            Ok body

                        _ ->
                            Err ()
                )
        , timeout = Just 60000
        }


readKey : Maybe Stdin -> Task StdinData.StdinError StdinData.Key
readKey stdin =
    case stdin of
        Just stdin_ ->
            ElmRunStdin.readKey stdin_
                |> Task.map mapStdinKey
                |> Task.mapError mapStdinError

        Nothing ->
            Task.fail StdinData.PermissionDenied


readLine : Maybe Stdin -> Task StdinData.StdinError String
readLine stdin =
    case stdin of
        Just stdin_ ->
            ElmRunStdin.readLine stdin_
                |> Task.mapError mapStdinError

        Nothing ->
            Task.fail StdinData.PermissionDenied


mapFsError : ElmRunFs.FsError -> FsData.FsError
mapFsError (ElmRunFs.FsError errno path) =
    FsData.FsError (mapFsErrno errno) (Fs.Path.toString path)


toTestableStat : ElmRunFs.FileStat -> FsData.FileStat
toTestableStat s =
    { isFile = s.isFile
    , isDirectory = s.isDirectory
    , isSymlink = s.isSymlink
    , size = s.size
    , modifiedTime = s.modifiedTime
    }


toTestableEntry : ElmRunFs.Entry -> FsData.Entry
toTestableEntry s =
    { relativePath = Fs.Path.toString s.relativePath
    , name = s.name
    , path = Fs.Location.display s.location
    , isDirectory = s.isDirectory
    , isFile = s.isFile
    , isSymlink = s.isSymlink
    , size = s.size
    , modifiedTime = s.modifiedTime
    , depth = s.depth
    }


walkTree : FileSystem -> Path -> Maybe String -> FsData.MatchKind -> Task FsData.FsError (List Path)
walkTree fs path pattern matchKind =
    let
        opts =
            Walk.defaultOptions

        walkOpts =
            { opts | pattern = pattern, kind = mapMatchKind matchKind }
    in
    Walk.fold fs
        (Fs.Location.dir path)
        walkOpts
        (\entry acc -> Walk.Continue (Fs.Path.toString entry.relativePath :: acc))
        []
        |> Task.map (\r -> List.reverse r.result)
        |> Task.mapError mapFsError


mapConsole : Capabilities.Console -> Capabilities.Console -> CliData.Console -> Capabilities.Console
mapConsole stdout stderr console =
    case console of
        CliData.Stdout ->
            stdout

        CliData.Stderr ->
            stderr


createSymlink : FileSystem -> { target : Path, linkPath : Path } -> Task FsData.FsError ()
createSymlink fs { target, linkPath } =
    ElmRunFs.createSymlink fs target (Fs.Location.file linkPath)
        |> Task.mapError mapFsError


copyDirectory : FileSystem -> { from : String, to : String } -> Task FsData.FsError ()
copyDirectory fs { from, to } =
    Walk.copyDirectory fs (Fs.Location.dir from) (Fs.Location.dir to)
        |> Task.mapError mapFsError


{-| Spawn and wait, mapping non-zero exits to typed failures.
-}
runProcess :
    ProcessCapability
    -> String
    -> ProcessData.SpawnOptions
    -> Task ProcessData.SpawnError ProcessData.Completed
runProcess os command spawnOptions =
    ElmRunProcess.spawn os command (mapSpawnOptions spawnOptions)
        |> Task.andThen (\spawned -> ElmRunProcess.wait os spawned.pid)
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


subEffects : Maybe FileWatcher -> TSub.SubEffects msg
subEffects maybeFileWatcher =
    { watchFiles = watchFiles maybeFileWatcher
    }


watchFiles : Maybe FileWatcher -> Path -> WatchOptions -> (FileEvent -> msg) -> Sub msg
watchFiles maybeFileWatcher =
    case maybeFileWatcher of
        Just fileWatcher ->
            \path watchOptions toMsg ->
                FileWatcher.watch fileWatcher path watchOptions toMsg

        Nothing ->
            \_ _ _ -> Sub.none


mapFsErrno : Fs.Error.Errno -> FsData.Errno
mapFsErrno errno =
    case errno of
        Fs.Error.EPERM ->
            FsData.EPERM

        Fs.Error.ENOENT ->
            FsData.ENOENT

        Fs.Error.ESRCH ->
            FsData.ESRCH

        Fs.Error.EINTR ->
            FsData.EINTR

        Fs.Error.EIO ->
            FsData.EIO

        Fs.Error.ENXIO ->
            FsData.ENXIO

        Fs.Error.E2BIG ->
            FsData.E2BIG

        Fs.Error.ENOEXEC ->
            FsData.ENOEXEC

        Fs.Error.EBADF ->
            FsData.EBADF

        Fs.Error.ECHILD ->
            FsData.ECHILD

        Fs.Error.EDEADLK ->
            FsData.EDEADLK

        Fs.Error.ENOMEM ->
            FsData.ENOMEM

        Fs.Error.EACCES ->
            FsData.EACCES

        Fs.Error.EFAULT ->
            FsData.EFAULT

        Fs.Error.ENOTBLK ->
            FsData.ENOTBLK

        Fs.Error.EBUSY ->
            FsData.EBUSY

        Fs.Error.EEXIST ->
            FsData.EEXIST

        Fs.Error.EXDEV ->
            FsData.EXDEV

        Fs.Error.ENODEV ->
            FsData.ENODEV

        Fs.Error.ENOTDIR ->
            FsData.ENOTDIR

        Fs.Error.EISDIR ->
            FsData.EISDIR

        Fs.Error.EINVAL ->
            FsData.EINVAL

        Fs.Error.ENFILE ->
            FsData.ENFILE

        Fs.Error.EMFILE ->
            FsData.EMFILE

        Fs.Error.ENOTTY ->
            FsData.ENOTTY

        Fs.Error.ETXTBSY ->
            FsData.ETXTBSY

        Fs.Error.EFBIG ->
            FsData.EFBIG

        Fs.Error.ENOSPC ->
            FsData.ENOSPC

        Fs.Error.ESPIPE ->
            FsData.ESPIPE

        Fs.Error.EROFS ->
            FsData.EROFS

        Fs.Error.EMLINK ->
            FsData.EMLINK

        Fs.Error.EPIPE ->
            FsData.EPIPE

        Fs.Error.EDOM ->
            FsData.EDOM

        Fs.Error.ERANGE ->
            FsData.ERANGE

        Fs.Error.EAGAIN ->
            FsData.EAGAIN

        Fs.Error.EINPROGRESS ->
            FsData.EINPROGRESS

        Fs.Error.EALREADY ->
            FsData.EALREADY

        Fs.Error.ENOTSOCK ->
            FsData.ENOTSOCK

        Fs.Error.EDESTADDRREQ ->
            FsData.EDESTADDRREQ

        Fs.Error.EMSGSIZE ->
            FsData.EMSGSIZE

        Fs.Error.EPROTOTYPE ->
            FsData.EPROTOTYPE

        Fs.Error.ENOPROTOOPT ->
            FsData.ENOPROTOOPT

        Fs.Error.EPROTONOSUPPORT ->
            FsData.EPROTONOSUPPORT

        Fs.Error.ESOCKTNOSUPPORT ->
            FsData.ESOCKTNOSUPPORT

        Fs.Error.ENOTSUP ->
            FsData.ENOTSUP

        Fs.Error.EPFNOSUPPORT ->
            FsData.EPFNOSUPPORT

        Fs.Error.EAFNOSUPPORT ->
            FsData.EAFNOSUPPORT

        Fs.Error.EADDRINUSE ->
            FsData.EADDRINUSE

        Fs.Error.EADDRNOTAVAIL ->
            FsData.EADDRNOTAVAIL

        Fs.Error.ENETDOWN ->
            FsData.ENETDOWN

        Fs.Error.ENETUNREACH ->
            FsData.ENETUNREACH

        Fs.Error.ENETRESET ->
            FsData.ENETRESET

        Fs.Error.ECONNABORTED ->
            FsData.ECONNABORTED

        Fs.Error.ECONNRESET ->
            FsData.ECONNRESET

        Fs.Error.ENOBUFS ->
            FsData.ENOBUFS

        Fs.Error.EISCONN ->
            FsData.EISCONN

        Fs.Error.ENOTCONN ->
            FsData.ENOTCONN

        Fs.Error.ESHUTDOWN ->
            FsData.ESHUTDOWN

        Fs.Error.ETOOMANYREFS ->
            FsData.ETOOMANYREFS

        Fs.Error.ETIMEDOUT ->
            FsData.ETIMEDOUT

        Fs.Error.ECONNREFUSED ->
            FsData.ECONNREFUSED

        Fs.Error.ELOOP ->
            FsData.ELOOP

        Fs.Error.ENAMETOOLONG ->
            FsData.ENAMETOOLONG

        Fs.Error.EHOSTDOWN ->
            FsData.EHOSTDOWN

        Fs.Error.EHOSTUNREACH ->
            FsData.EHOSTUNREACH

        Fs.Error.ENOTEMPTY ->
            FsData.ENOTEMPTY

        Fs.Error.EPROCLIM ->
            FsData.EPROCLIM

        Fs.Error.EUSERS ->
            FsData.EUSERS

        Fs.Error.EDQUOT ->
            FsData.EDQUOT

        Fs.Error.ESTALE ->
            FsData.ESTALE

        Fs.Error.EREMOTE ->
            FsData.EREMOTE

        Fs.Error.EBADRPC ->
            FsData.EBADRPC

        Fs.Error.ERPCMISMATCH ->
            FsData.ERPCMISMATCH

        Fs.Error.EPROGUNAVAIL ->
            FsData.EPROGUNAVAIL

        Fs.Error.EPROGMISMATCH ->
            FsData.EPROGMISMATCH

        Fs.Error.EPROCUNAVAIL ->
            FsData.EPROCUNAVAIL

        Fs.Error.ENOLCK ->
            FsData.ENOLCK

        Fs.Error.ENOSYS ->
            FsData.ENOSYS

        Fs.Error.EFTYPE ->
            FsData.EFTYPE

        Fs.Error.EAUTH ->
            FsData.EAUTH

        Fs.Error.ENEEDAUTH ->
            FsData.ENEEDAUTH

        Fs.Error.EPWROFF ->
            FsData.EPWROFF

        Fs.Error.EDEVERR ->
            FsData.EDEVERR

        Fs.Error.EOVERFLOW ->
            FsData.EOVERFLOW

        Fs.Error.EBADEXEC ->
            FsData.EBADEXEC

        Fs.Error.EBADARCH ->
            FsData.EBADARCH

        Fs.Error.ESHLIBVERS ->
            FsData.ESHLIBVERS

        Fs.Error.EBADMACHO ->
            FsData.EBADMACHO

        Fs.Error.ECANCELED ->
            FsData.ECANCELED

        Fs.Error.EIDRM ->
            FsData.EIDRM

        Fs.Error.ENOMSG ->
            FsData.ENOMSG

        Fs.Error.EILSEQ ->
            FsData.EILSEQ

        Fs.Error.ENOATTR ->
            FsData.ENOATTR

        Fs.Error.EBADMSG ->
            FsData.EBADMSG

        Fs.Error.EMULTIHOP ->
            FsData.EMULTIHOP

        Fs.Error.ENODATA ->
            FsData.ENODATA

        Fs.Error.ENOLINK ->
            FsData.ENOLINK

        Fs.Error.ENOSR ->
            FsData.ENOSR

        Fs.Error.ENOSTR ->
            FsData.ENOSTR

        Fs.Error.EPROTO ->
            FsData.EPROTO

        Fs.Error.ETIME ->
            FsData.ETIME

        Fs.Error.EOPNOTSUPP ->
            FsData.EOPNOTSUPP

        Fs.Error.ENOPOLICY ->
            FsData.ENOPOLICY

        Fs.Error.ENOTRECOVERABLE ->
            FsData.ENOTRECOVERABLE

        Fs.Error.EOWNERDEAD ->
            FsData.EOWNERDEAD

        Fs.Error.EQFULL ->
            FsData.EQFULL

        Fs.Error.Unknown code ->
            FsData.Unknown code
