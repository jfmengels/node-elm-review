port module Node.Program exposing (Config, Program, program)

import Base64
import Bytes exposing (Bytes)
import ConcurrentTask exposing (ConcurrentTask, Pool)
import ConcurrentTask.Http
import Dict exposing (Dict)
import Elm.Review.CliCommunication as CliCommunication
import Elm.Review.InitError as InitError
import Elm.Review.Testable.CliData as CliData exposing (Console)
import Elm.Review.Testable.Cmd as TestableCmd
import Elm.Review.Testable.FileWatchData as FileWatchData
import Elm.Review.Testable.FsData as FsData exposing (Entry, FileStat, FsError, MatchKind)
import Elm.Review.Testable.Internal as Internal exposing (TCmd, TSub, TaskResult)
import Elm.Review.Testable.ProcessData as ProcessData exposing (Completed, ProcessError, ProcessId, SpawnError, SpawnOptions)
import Elm.Review.Testable.StdinData as StdinData exposing (Key, StdinError)
import Elm.Review.Testable.TSub as TSub exposing (SubEffects, TSub)
import Elm.Review.Testable.TTask exposing (TTask)
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Node.FileWatcher as FileWatcher
import Process
import Task exposing (Task)


type ModelWrapper model msg
    = Done
    | Running (Model model msg)


type alias Model model msg =
    { mainModel : model
    , exitCode : Maybe Int
    , ongoingTasksCount : Int
    , pool : Pool msg
    }


type alias Pool msg =
    ConcurrentTask.Pool (Msg msg)


type Error
    = Error


type TransactionError
    = FsError FsData.FsError


type Msg msg
    = MainMsg msg
    | TaskOnProgress ( ConcurrentTask.Pool (Msg msg), Cmd (Msg msg) ) -- updates task progress
    | TaskOnComplete (ConcurrentTask.Response msg msg)


type alias Config model msg =
    { init : Flags -> InitError.InitError ( model, TCmd msg )
    , update : msg -> model -> ( model, TCmd msg )
    , subscriptions : model -> TSub msg
    }


type alias Flags =
    { args : List String
    , env : Dict String String
    , communicationKey : CliCommunication.Key
    , userHome : Path
    , binaryRoot : Path
    }


type alias Program model msg =
    Platform.Program Decode.Value (ModelWrapper model msg) (Msg msg)


program : Config model msg -> Program model msg
program config =
    Platform.worker
        { init = init config.init
        , update = update config.update
        , subscriptions = subscriptions config.subscriptions
        }


init : (Flags -> InitError.InitError ( model, TCmd msg )) -> Decode.Value -> ( ModelWrapper model msg, Cmd (Msg msg) )
init initFn rawFlags =
    case Decode.decodeValue flagsDecoder rawFlags of
        Ok flags ->
            case initFn flags of
                InitError.Success ( mainModel, initCmd ) ->
                    let
                        { pool, exitCode, ongoingTasksCount, cmd } =
                            taskToCmd ConcurrentTask.pool Nothing 0 initCmd
                    in
                    ( Running
                        { mainModel = mainModel
                        , ongoingTasksCount = ongoingTasksCount
                        , exitCode = exitCode
                        , pool = pool
                        }
                    , cmd
                    )

                InitError.Problem formatOptions problem ->
                    ( Done
                    , stop formatOptions problem
                    )

                InitError.StringProblem message ->
                    ( Done
                    , printlnStderrThenExit
                        { message = message
                        , exitCode = 1
                        }
                    )

        Err decodingError ->
            ( Done
            , printlnStderrThenExit
                { message = "Problem decoding flags: " ++ Decode.errorToString decodingError
                , exitCode = 1
                }
            )


flagsDecoder : Decode.Decoder Flags
flagsDecoder =
    Decode.map5 Flags
        (Decode.field "args" (Decode.list Decode.string))
        (Decode.field "env" (Decode.dict Decode.string))
        CliCommunication.decoder
        (Decode.field "userHome" Decode.string)
        (Decode.field "binaryRoot" Decode.string)


startTask : Pool msg -> ConcurrentTask msg msg -> ( Pool msg, Cmd (Msg msg) )
startTask pool task_ =
    ConcurrentTask.attempt
        { send = send
        , pool = pool
        , onComplete = TaskOnComplete
        }
        task_


update :
    (msg -> model -> ( model, TCmd msg ))
    -> Msg msg
    -> ModelWrapper model msg
    -> ( ModelWrapper model msg, Cmd (Msg msg) )
update updateFn msg modelWrapper =
    case modelWrapper of
        Done ->
            ( Done, Cmd.none )

        Running model ->
            case msg of
                MainMsg mainMsg ->
                    handleMainMsg updateFn mainMsg model

                TaskOnComplete (ConcurrentTask.Success mainMsg) ->
                    handleMainMsg updateFn mainMsg { model | ongoingTasksCount = model.ongoingTasksCount - 1 }
                        |> exitIfRequestedAndDone

                TaskOnComplete (ConcurrentTask.Error error) ->
                    -- TODO Handle Task ConcurrentTask.Error
                    ( modelWrapper, Cmd.none )
                        |> exitIfRequestedAndDone

                TaskOnComplete (ConcurrentTask.UnexpectedError error) ->
                    -- TODO Handle Task ConcurrentTask.UnexpectedError
                    ( modelWrapper, Cmd.none )
                        |> exitIfRequestedAndDone

                TaskOnProgress ( newPool, cmd ) ->
                    ( Running
                        { mainModel = model.mainModel
                        , exitCode = model.exitCode
                        , ongoingTasksCount = model.ongoingTasksCount
                        , pool = newPool
                        }
                    , cmd
                    )


handleMainMsg :
    (msg -> model -> ( model, TCmd msg ))
    -> msg
    -> Model model msg
    -> ( ModelWrapper model msg, Cmd (Msg msg) )
handleMainMsg updateFn mainMsg model =
    let
        ( newMainModel, mainCmd ) =
            updateFn mainMsg model.mainModel

        { pool, exitCode, ongoingTasksCount, cmd } =
            taskToCmd model.pool model.exitCode model.ongoingTasksCount mainCmd
    in
    ( Running
        { mainModel = newMainModel
        , exitCode = maybeOr model.exitCode exitCode
        , ongoingTasksCount = ongoingTasksCount
        , pool = pool
        }
    , cmd
    )
        |> exitIfRequestedAndDone


exitIfRequestedAndDone : ( ModelWrapper model msg, Cmd (Msg msg) ) -> ( ModelWrapper model msg, Cmd (Msg msg) )
exitIfRequestedAndDone (( modelWrapper, _ ) as untouched) =
    case modelWrapper of
        Done ->
            untouched

        Running model ->
            case model.exitCode of
                Nothing ->
                    untouched

                Just exitCode ->
                    if model.ongoingTasksCount == 0 then
                        ( modelWrapper
                        , exit exitCode
                        )

                    else
                        untouched


maybeOr : Maybe a -> Maybe a -> Maybe a
maybeOr initialMaybe newMaybe =
    case initialMaybe of
        Nothing ->
            newMaybe

        Just _ ->
            initialMaybe


{-| Converts a `Testable.Cmd` into a `Cmd`

    TestableCmd.none
        |> Testable.cmd
        == Cmd.none

-}
taskToCmd :
    Pool msg
    -> Maybe Int
    -> Int
    -> TestableCmd.Cmd msg
    ->
        { pool : Pool msg
        , exitCode : Maybe Int
        , ongoingTasksCount : Int
        , cmd : Cmd (Msg msg)
        }
taskToCmd pool initialExitCode ongoingTasksCount testableEffects =
    case testableEffects of
        Internal.None ->
            { pool = pool
            , exitCode = Nothing
            , ongoingTasksCount = ongoingTasksCount
            , cmd = Cmd.none
            }

        Internal.TaskCmd (Internal.ExitTask exitCode _) ->
            { pool = pool
            , exitCode = Just exitCode
            , ongoingTasksCount = ongoingTasksCount
            , cmd = Cmd.none
            }

        Internal.TaskCmd testableTask ->
            let
                ( newPool, cmd ) =
                    task testableTask
                        |> startTask pool
            in
            { pool = newPool
            , exitCode = Nothing
            , ongoingTasksCount = ongoingTasksCount + 1
            , cmd =
                case initialExitCode of
                    Just _ ->
                        Cmd.none

                    Nothing ->
                        cmd
            }

        Internal.Batch elements ->
            let
                result : { pool : Pool msg, exitCode : Maybe Int, ongoingTasksCount : Int, cmds : List (Cmd (Msg msg)) }
                result =
                    List.foldl
                        (\t acc ->
                            let
                                res : { pool : Pool msg, exitCode : Maybe Int, ongoingTasksCount : Int, cmd : Cmd (Msg msg) }
                                res =
                                    taskToCmd acc.pool initialExitCode acc.ongoingTasksCount t
                            in
                            { pool = res.pool
                            , exitCode = maybeOr acc.exitCode res.exitCode
                            , ongoingTasksCount = res.ongoingTasksCount
                            , cmds = res.cmd :: acc.cmds
                            }
                        )
                        { pool = pool
                        , exitCode = initialExitCode
                        , ongoingTasksCount = ongoingTasksCount
                        , cmds = []
                        }
                        elements
            in
            { pool = result.pool
            , exitCode = result.exitCode
            , ongoingTasksCount = result.ongoingTasksCount
            , cmd = Cmd.batch result.cmds
            }

        Internal.Println console string ->
            { pool = pool
            , exitCode = Nothing
            , ongoingTasksCount = ongoingTasksCount
            , cmd =
                effects.println console string
                    |> Cmd.map never
            }

        Internal.PrintErrorThenExit message exitCode ->
            { pool = pool
            , exitCode = Nothing
            , ongoingTasksCount = ongoingTasksCount
            , cmd = printlnStderrThenExit { message = message, exitCode = exitCode }
            }

        Internal.Exit code ->
            { pool = pool
            , exitCode = Just code
            , ongoingTasksCount = ongoingTasksCount
            , cmd =
                effects.exit code
                    |> Cmd.map never
            }


{-| Converts a `Testable.Task` into a `Task`

    Testable.Task.succeed "A"
        |> Testable.task
        == Task.succeed "A"

-}
task : TTask error value -> ConcurrentTask error value
task testableTask =
    case testableTask of
        Internal.ImmediateTask result ->
            taskResult result

        Internal.ExitTask _ result ->
            -- Is handled in the parent caller
            -- TODO Extract ExitTask out of TTask (add a layer?) to avoid this case
            taskResult result

        -- File system
        Internal.Stat path onResult ->
            effects.stat path
                |> handle onResult

        Internal.List path onResult ->
            effects.list path
                |> handle onResult

        Internal.ReadTextFile path onResult ->
            effects.readTextFile path
                |> handle onResult

        Internal.WriteTextFile path string onResult ->
            effects.writeTextFile path string
                |> handle onResult

        Internal.WriteBytes path bytes onResult ->
            effects.writeBytes path bytes
                |> handle onResult

        Internal.DeleteFile path onResult ->
            effects.deleteFile path
                |> handle onResult

        Internal.CreateSymlink targets onResult ->
            effects.createSymlink targets
                |> handle onResult

        Internal.CreateDirectory path onResult ->
            effects.createDirectory path
                |> handle onResult

        Internal.RemoveDirectory path onResult ->
            effects.removeDirectory path
                |> handle onResult

        Internal.CopyDirectory targets onResult ->
            effects.copyDirectory targets
                |> handle onResult

        Internal.WalkTree path pattern matchKind onResult ->
            effects.walkTree path pattern matchKind
                |> handle onResult

        -- Http
        Internal.HttpGetString url onResult ->
            effects.httpGetString url
                |> handle onResult

        Internal.HttpGetBytes url onResult ->
            effects.httpGetBytes url
                |> handle onResult

        -- Stdin/stdout/stderr
        Internal.ReadKey onResult ->
            effects.readKey
                |> handle onResult

        Internal.ReadLine onResult ->
            effects.readLine
                |> handle onResult

        Internal.PrintlnTask console message onResult ->
            effects.printlnTask console message
                |> handle onResult

        -- Process
        Internal.RunProcess command spawnOptions onResult ->
            effects.runProcess command spawnOptions
                |> handle onResult

        Internal.SpawnProcess command spawnOptions onResult ->
            effects.spawnProcess command spawnOptions
                |> handle onResult

        Internal.WaitProcess processId onResult ->
            effects.waitProcess processId
                |> handle onResult

        Internal.KillProcess processId signal onResult ->
            effects.killProcess processId signal
                |> handle onResult


readTextFile : Path -> ConcurrentTask FsData.FsError String
readTextFile path =
    ConcurrentTask.define
        { function = "fs:readTextFile"
        , expect = ConcurrentTask.expectString
        , errors = ConcurrentTask.expectErrors decodeFsError
        , args =
            Encode.object
                [ ( "path", Encode.string path )
                ]
        }


writeTextFile : String -> String -> ConcurrentTask FsData.FsError ()
writeTextFile path content =
    ConcurrentTask.define
        { function = "fs:writeTextFile"
        , expect = ConcurrentTask.expectWhatever
        , errors = ConcurrentTask.expectErrors decodeFsError
        , args =
            Encode.object
                [ ( "path", Encode.string path )
                , ( "content", Encode.string content )
                ]
        }


writeBytes : String -> Bytes -> ConcurrentTask FsData.FsError ()
writeBytes path content =
    ConcurrentTask.define
        { function = "fs:writeBytes"
        , expect = ConcurrentTask.expectWhatever
        , errors = ConcurrentTask.expectErrors decodeFsError
        , args =
            Encode.object
                [ ( "path", Encode.string path )
                , ( "content", Encode.string (Base64.fromBytes content |> Maybe.withDefault "Invalid bytes") )
                ]
        }


stat : Path -> ConcurrentTask FsData.FsError FileStat
stat path =
    ConcurrentTask.define
        { function = "fs:stat"
        , expect = ConcurrentTask.expectJson statDecoder
        , errors = ConcurrentTask.expectErrors decodeFsError
        , args =
            Encode.object
                [ ( "path", Encode.string path )
                ]
        }


list : Path -> ConcurrentTask FsData.FsError (List Entry)
list path =
    ConcurrentTask.define
        { function = "fs:list"
        , expect = ConcurrentTask.expectJson (Decode.list (entryDecoder path))
        , errors = ConcurrentTask.expectErrors decodeFsError
        , args =
            Encode.object
                [ ( "path", Encode.string path )
                ]
        }


statDecoder : Decoder FileStat
statDecoder =
    Decode.map5 FileStat
        (Decode.field "isFile" Decode.bool)
        (Decode.field "isDirectory" Decode.bool)
        (Decode.field "isSymlink" Decode.bool)
        (Decode.field "size" Decode.int)
        (Decode.field "modifiedTime" Decode.int)


entryDecoder : Path -> Decoder Entry
entryDecoder root =
    Decode.map8 Entry
        (Decode.field "path" Decode.string)
        (Decode.field "name" Decode.string)
        (Decode.field "path" Decode.string |> Decode.map (Path.join2 root))
        (Decode.field "isDirectory" Decode.bool)
        (Decode.field "isFile" Decode.bool)
        (Decode.field "isSymlink" Decode.bool)
        (Decode.field "size" Decode.int)
        (Decode.field "modifiedTime" Decode.int)
        |> Decode.map (\f -> f 0)


deleteFile : Path -> ConcurrentTask FsData.FsError ()
deleteFile path =
    ConcurrentTask.define
        { function = "fs:deleteFile"
        , expect = ConcurrentTask.expectWhatever
        , errors = ConcurrentTask.expectErrors decodeFsError
        , args =
            Encode.object
                [ ( "path", Encode.string path )
                ]
        }


createSymlink : { target : Path, linkPath : Path } -> ConcurrentTask FsData.FsError ()
createSymlink { target, linkPath } =
    ConcurrentTask.define
        { function = "fs:createSymlink"
        , expect = ConcurrentTask.expectWhatever
        , errors = ConcurrentTask.expectErrors decodeFsError
        , args =
            Encode.object
                [ ( "target", Encode.string target )
                , ( "linkPath", Encode.string linkPath )
                ]
        }


createDirectory : Path -> ConcurrentTask FsData.FsError ()
createDirectory path =
    ConcurrentTask.define
        { function = "fs:createDirectory"
        , expect = ConcurrentTask.expectWhatever
        , errors = ConcurrentTask.expectErrors decodeFsError
        , args =
            Encode.object
                [ ( "path", Encode.string path )
                ]
        }


removeDirectory : Path -> ConcurrentTask FsData.FsError ()
removeDirectory path =
    ConcurrentTask.define
        { function = "fs:removeDirectory"
        , expect = ConcurrentTask.expectWhatever
        , errors = ConcurrentTask.expectErrors decodeFsError
        , args =
            Encode.object
                [ ( "path", Encode.string path )
                ]
        }


copyDirectory : { from : Path, to : Path } -> ConcurrentTask FsError ()
copyDirectory { from, to } =
    ConcurrentTask.define
        { function = "fs:copyDirectory"
        , expect = ConcurrentTask.expectWhatever
        , errors = ConcurrentTask.expectErrors decodeFsError
        , args =
            Encode.object
                [ ( "from", Encode.string from )
                , ( "to", Encode.string to )
                ]
        }


walkTree : Path -> Maybe String -> MatchKind -> ConcurrentTask FsError (List Path)
walkTree path pattern kind =
    ConcurrentTask.define
        { function = "fs:walkTree"
        , expect = ConcurrentTask.expectJson (Decode.list Decode.string)
        , errors = ConcurrentTask.expectErrors decodeFsError
        , args =
            Encode.object
                [ ( "path", Encode.string path )
                , ( "pattern", encodeMaybe Encode.string pattern )
                , ( "onlyFiles", Encode.bool (kind == FsData.File) )
                , ( "onlyDirectory", Encode.bool (kind == FsData.Directory) )
                ]
        }


decodeFsError : Decoder FsData.FsError
decodeFsError =
    Decode.map2 FsData.errorFromCodeAndPath
        (Decode.field "errno" (Decode.map negate Decode.int))
        (Decode.field "path" Decode.string)


decodeSpawnError : Decoder ProcessData.SpawnError
decodeSpawnError =
    Decode.field "code" Decode.string
        |> Decode.andThen
            (\code ->
                case code of
                    "CommandNotFound" ->
                        Decode.succeed ProcessData.CommandNotFound

                    "ProcessRunError" ->
                        Decode.map ProcessData.ProcessRunError (Decode.field "processError" decodeProcessError)

                    "CommandFailed" ->
                        Decode.map ProcessData.CommandFailed (Decode.field "data" decodeCompleted)

                    _ ->
                        Decode.field "message" Decode.string
                            |> Decode.andThen
                                (\message ->
                                    Decode.fail ("Unknown code: " ++ code ++ " - " ++ message)
                                )
            )


decodeProcessError : Decoder ProcessData.ProcessError
decodeProcessError =
    Decode.field "code" Decode.string
        |> Decode.andThen
            (\code ->
                case code of
                    "PermissionDenied" ->
                        Decode.succeed ProcessData.PermissionDenied

                    "CaptureLimitExceeded" ->
                        Decode.map ProcessData.CaptureLimitExceeded (Decode.field "data" Decode.string)

                    "ProcessError" ->
                        Decode.map ProcessData.ProcessError (Decode.field "data" Decode.string)

                    _ ->
                        Decode.field "message" Decode.string
                            |> Decode.andThen
                                (\message ->
                                    Decode.fail ("Unknown code: " ++ code ++ " - " ++ message)
                                )
            )


decodeCompleted : Decoder ProcessData.Completed
decodeCompleted =
    Decode.map7 ProcessData.Completed
        (Decode.field "pid" Decode.int)
        (Decode.field "exitCode" Decode.int)
        (Decode.succeed Nothing)
        (Decode.field "stdout" (Decode.nullable Decode.string))
        (Decode.field "stderr" (Decode.nullable Decode.string))
        (Decode.succeed False)
        (Decode.succeed False)


httpGetString : String -> ConcurrentTask () String
httpGetString url =
    ConcurrentTask.Http.get
        { url = url
        , headers = []
        , expect = ConcurrentTask.Http.expectString
        , timeout = Nothing
        }
        |> ConcurrentTask.mapError (\_ -> ())


httpGetBytes : String -> ConcurrentTask () Bytes
httpGetBytes url =
    ConcurrentTask.Http.get
        { url = url
        , headers = []
        , expect = ConcurrentTask.Http.expectRawBytes
        , timeout = Just 60000
        }
        |> ConcurrentTask.mapError (\_ -> ())


printlnTask : Console -> String -> ConcurrentTask x ()
printlnTask console message =
    ConcurrentTask.define
        { function = "std::println"
        , expect = ConcurrentTask.expectWhatever
        , errors = ConcurrentTask.expectNoErrors
        , args =
            Encode.object
                [ ( "logFunction"
                  , Encode.string
                        (case console of
                            CliData.Stdout ->
                                "log"

                            CliData.Stderr ->
                                "error"
                        )
                  )
                , ( "message", Encode.string message )
                ]
        }


printlnStderrThenExit_ : String -> Int -> Cmd msg
printlnStderrThenExit_ message exitCode =
    printlnStderrThenExit
        { message = message
        , exitCode = exitCode
        }


runProcess : String -> SpawnOptions -> ConcurrentTask SpawnError Completed
runProcess command spawnOptions =
    ConcurrentTask.define
        { function = "os:runProcess"
        , expect = ConcurrentTask.expectJson decodeCompleted
        , errors = ConcurrentTask.expectErrors decodeSpawnError
        , args = encodeSpawnOptions command spawnOptions
        }


spawnProcess : String -> SpawnOptions -> ConcurrentTask ProcessError ProcessId
spawnProcess command spawnOptions =
    -- TODO Add missing tasks in `lib/main-nodejs.js`
    ConcurrentTask.define
        { function = "os:spawnProcess"
        , expect = ConcurrentTask.expectJson Decode.int
        , errors = ConcurrentTask.expectErrors decodeProcessError
        , args = encodeSpawnOptions command spawnOptions
        }


waitProcess : ProcessId -> ConcurrentTask ProcessError Completed
waitProcess pid =
    ConcurrentTask.define
        { function = "os:waitProcess"
        , expect = ConcurrentTask.expectJson decodeCompleted
        , errors = ConcurrentTask.expectErrors decodeProcessError
        , args = Encode.int pid
        }


killProcess : ProcessId -> Int -> ConcurrentTask ProcessError ()
killProcess pid signal =
    ConcurrentTask.define
        { function = "os:killProcess"
        , expect = ConcurrentTask.expectWhatever
        , errors = ConcurrentTask.expectErrors decodeProcessError
        , args =
            Encode.object
                [ ( "pid", Encode.int pid )
                , ( "signal", Encode.int signal )
                ]
        }


encodeSpawnOptions : String -> SpawnOptions -> Encode.Value
encodeSpawnOptions command spawnOptions =
    Encode.object
        [ ( "command", Encode.string command )
        , ( "args", Encode.list Encode.string spawnOptions.args )
        , ( "env", encodeMaybe encodeEnv spawnOptions.env )
        , ( "cwd", encodeMaybe Encode.string spawnOptions.cwd )
        , ( "stdin", encodeStdinSpec spawnOptions.stdin )
        , ( "stdout", encodeStdoutSpec spawnOptions.stdout )
        , ( "stderr", encodeStderrSpec spawnOptions.stderr )
        ]


encodeEnv : List ( String, String ) -> Encode.Value
encodeEnv envList =
    List.map (\( key, value ) -> ( key, Encode.string value )) envList
        |> Encode.object


encodeStdinSpec : ProcessData.StdinSpec -> Encode.Value
encodeStdinSpec stdinSpec =
    case stdinSpec of
        ProcessData.InheritStdin ->
            Encode.object
                [ ( "kind", Encode.string "inherit" )
                ]

        ProcessData.NullStdin ->
            Encode.object
                [ ( "kind", Encode.string "ignore" )
                ]

        ProcessData.TextStdin data ->
            Encode.object
                [ ( "kind", Encode.string "pipe" )
                , ( "data", Encode.string data )
                ]

        ProcessData.FileStdin file ->
            Encode.object
                [ ( "kind", Encode.string "file" )
                , ( "file", Encode.string file )
                ]


encodeStdoutSpec : ProcessData.StdoutSpec -> Encode.Value
encodeStdoutSpec stdinSpec =
    case stdinSpec of
        ProcessData.InheritStdout ->
            Encode.object
                [ ( "kind", Encode.string "inherit" )
                ]

        ProcessData.NullStdout ->
            Encode.object
                [ ( "kind", Encode.string "ignore" )
                ]

        ProcessData.CaptureStdout captureLimits ->
            -- TODO Capture stdout
            -- https://nodejs.org/docs/latest-v14.x/api/child_process.html#child_process_options_stdio
            Encode.object
                [ ( "kind", Encode.string "pipe" )
                ]


encodeStderrSpec : ProcessData.StderrSpec -> Encode.Value
encodeStderrSpec stdinSpec =
    case stdinSpec of
        ProcessData.InheritStderr ->
            Encode.object
                [ ( "kind", Encode.string "inherit" )
                ]

        ProcessData.NullStderr ->
            Encode.object
                [ ( "kind", Encode.string "ignore" )
                ]

        ProcessData.CaptureStderr captureLimits ->
            -- TODO Capture stdout
            -- https://nodejs.org/docs/latest-v14.x/api/child_process.html#child_process_options_stdio
            Encode.object
                [ ( "kind", Encode.string "pipe" )
                ]

        ProcessData.MergeWithStdout ->
            -- TODO Merge stderr with stdout
            -- https://nodejs.org/docs/latest-v14.x/api/child_process.html#child_process_options_stdio
            Encode.object
                [ ( "kind", Encode.string "stdout" )
                ]


encodeMaybe : (a -> Encode.Value) -> Maybe a -> Encode.Value
encodeMaybe encoder maybe =
    case maybe of
        Just data ->
            encoder data

        Nothing ->
            Encode.null


handle : (Result x value -> TaskResult error a) -> ConcurrentTask x value -> ConcurrentTask error a
handle onResult source =
    source
        |> toResultTask
        |> ConcurrentTask.map onResult
        |> (\result -> ConcurrentTask.andThen taskResult result)


taskResult : Internal.TaskResult error value -> ConcurrentTask error value
taskResult result =
    case result of
        Internal.Success msg ->
            ConcurrentTask.succeed msg

        Internal.Failure error ->
            ConcurrentTask.fail error

        Internal.Continue next ->
            task next


toResultTask : ConcurrentTask x value -> ConcurrentTask never (Result x value)
toResultTask task_ =
    task_
        |> ConcurrentTask.map Ok
        |> ConcurrentTask.onError (\x -> ConcurrentTask.succeed (Err x))


subscriptions : (model -> TSub msg) -> ModelWrapper model msg -> Sub (Msg msg)
subscriptions subsFn model =
    case model of
        Done ->
            Sub.none

        Running { mainModel, pool } ->
            Sub.batch
                [ ConcurrentTask.onProgress
                    { send = send
                    , receive = receive
                    , onProgress = TaskOnProgress
                    }
                    pool
                , TSub.subscriptions subEffects (subsFn mainModel)
                    |> Sub.map MainMsg
                ]


subEffects : SubEffects msg
subEffects =
    { watchFiles = FileWatcher.watchFiles
    }


stop : Problem.FormatOptions options -> Problem -> Cmd msg
stop formatOptions problem =
    printlnStderrThenExit
        { message = Problem.format formatOptions problem
        , exitCode = 1
        }


port exit : Int -> Cmd msg


port printlnStdout : String -> Cmd msg


port printlnStderrThenExit : { message : String, exitCode : Int } -> Cmd msg


port printlnStderr : String -> Cmd msg


port send : Encode.Value -> Cmd msg


port receive : (Decode.Value -> msg) -> Sub msg


type alias Effects =
    { -- File system
      readTextFile : Path -> ConcurrentTask FsError String
    , writeTextFile : Path -> String -> ConcurrentTask FsError ()
    , writeBytes : Path -> Bytes -> ConcurrentTask FsError ()
    , stat : Path -> ConcurrentTask FsError FileStat
    , list : Path -> ConcurrentTask FsError (List Entry)
    , deleteFile : Path -> ConcurrentTask FsError ()
    , createSymlink : { target : Path, linkPath : Path } -> ConcurrentTask FsError ()
    , createDirectory : Path -> ConcurrentTask FsError ()
    , removeDirectory : Path -> ConcurrentTask FsError ()
    , copyDirectory : { from : Path, to : Path } -> ConcurrentTask FsError ()
    , walkTree : Path -> Maybe String -> MatchKind -> ConcurrentTask FsError (List Path)
    , httpGetString : String -> ConcurrentTask () String
    , httpGetBytes : String -> ConcurrentTask () Bytes

    -- Stdin / Stdout
    , readKey : ConcurrentTask StdinError Key
    , readLine : ConcurrentTask StdinError String
    , println : Console -> String -> Cmd Never
    , printlnStderrThenExit : String -> Int -> Cmd Never
    , printlnTask : Console -> String -> ConcurrentTask Never ()
    , exit : Int -> Cmd Never

    -- Process
    , runProcess : String -> SpawnOptions -> ConcurrentTask SpawnError Completed
    , spawnProcess : String -> SpawnOptions -> ConcurrentTask ProcessError ProcessId
    , waitProcess : ProcessId -> ConcurrentTask ProcessError Completed
    , killProcess : ProcessId -> Int -> ConcurrentTask ProcessError ()
    }


effects : Effects
effects =
    { -- File system
      readTextFile = readTextFile
    , writeTextFile = writeTextFile
    , writeBytes = writeBytes
    , stat = stat
    , list = list
    , deleteFile = deleteFile
    , createSymlink = createSymlink
    , createDirectory = createDirectory
    , removeDirectory = removeDirectory
    , copyDirectory = copyDirectory
    , walkTree = walkTree

    -- Http
    , httpGetString = httpGetString
    , httpGetBytes = httpGetBytes

    -- Stdin / Stdout
    , readKey = readKey
    , readLine = readLine
    , println =
        \console string ->
            case console of
                CliData.Stdout ->
                    printlnStdout string

                CliData.Stderr ->
                    printlnStderr string
    , printlnStderrThenExit = printlnStderrThenExit_
    , printlnTask = printlnTask
    , exit = exit

    -- Process
    , runProcess = runProcess
    , spawnProcess = spawnProcess
    , waitProcess = waitProcess
    , killProcess = killProcess
    }


readKey : ConcurrentTask StdinError StdinData.Key
readKey =
    ConcurrentTask.define
        { function = "std::readKey"
        , expect = ConcurrentTask.expectJson decodeStdinKey
        , errors = ConcurrentTask.expectErrors decodeStdinError
        , args = Encode.null
        }


readLine : ConcurrentTask StdinError String
readLine =
    ConcurrentTask.define
        { function = "std::readLine"
        , expect = ConcurrentTask.expectString
        , errors = ConcurrentTask.expectErrors decodeStdinError
        , args = Encode.null
        }


decodeStdinKey : Decoder StdinData.Key
decodeStdinKey =
    Decode.oneOf
        [ Decode.field "name" Decode.string
            |> Decode.andThen stringToKey
        , Decode.field "sequence" Decode.string
            |> Decode.andThen
                (\sequence ->
                    case String.uncons sequence of
                        Just ( char, _ ) ->
                            Decode.succeed (StdinData.KeyChar char)

                        Nothing ->
                            Decode.fail "Invalid keyboard key"
                )
        ]


stringToKey : String -> Decoder StdinData.Key
stringToKey name =
    case name of
        "return" ->
            Decode.succeed StdinData.KeyEnter

        "backspace" ->
            Decode.succeed StdinData.KeyBackspace

        "delete" ->
            Decode.succeed StdinData.KeyDelete

        "escape" ->
            Decode.succeed StdinData.KeyEscape

        "up" ->
            Decode.succeed StdinData.KeyArrowUp

        "down" ->
            Decode.succeed StdinData.KeyArrowDown

        "left" ->
            Decode.succeed StdinData.KeyArrowLeft

        "right" ->
            Decode.succeed StdinData.KeyArrowRight

        "home" ->
            Decode.succeed StdinData.KeyHome

        "end" ->
            Decode.succeed StdinData.KeyEnd

        "pageup" ->
            Decode.succeed StdinData.KeyPageUp

        "pagedown" ->
            Decode.succeed StdinData.KeyPageDown

        _ ->
            case String.uncons name of
                Just ( char, _ ) ->
                    Decode.succeed (StdinData.KeyChar char)

                Nothing ->
                    Decode.fail "Invalid keyboard key"


decodeStdinError : Decoder StdinError
decodeStdinError =
    Decode.field "code" Decode.string
        |> Decode.andThen
            (\code ->
                case code of
                    "PermissionDenied" ->
                        Decode.succeed StdinData.PermissionDenied

                    "EndOfInput" ->
                        Decode.succeed StdinData.EndOfInput

                    "IoError" ->
                        Decode.map StdinData.IoError (Decode.field "data" Decode.string)

                    _ ->
                        Decode.fail ("Unknown code: " ++ code)
            )
