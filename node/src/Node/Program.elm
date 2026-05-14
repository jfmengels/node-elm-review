port module Node.Program exposing (Config, Program, program)

import ConcurrentTask exposing (ConcurrentTask, Pool)
import Dict exposing (Dict)
import Elm.Review.InitError as InitError
import Elm.Review.Testable.CliData exposing (Console)
import Elm.Review.Testable.Cmd as TestableCmd
import Elm.Review.Testable.FsData as FsData exposing (FileStat, FsError, MatchKind)
import Elm.Review.Testable.Internal as Internal exposing (TCmd, TSub, TaskResult)
import Elm.Review.Testable.ProcessData exposing (Completed, ProcessError, ProcessId, SpawnError, SpawnOptions)
import Elm.Review.Testable.StdinData exposing (Key, StdinError)
import Elm.Review.Testable.TSub as TSub exposing (TSub)
import Elm.Review.Testable.TTask exposing (TTask)
import ElmReview.Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Node.Effects as NodeEffects


type ModelWrapper model msg
    = Done
    | Running (Model model msg)


type alias Model model msg =
    { mainModel : model
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
                        ( pool, cmd ) =
                            taskToCmd ConcurrentTask.pool initCmd
                    in
                    ( Running
                        { mainModel = mainModel
                        , pool = pool
                        }
                    , cmd
                    )

                InitError.Problem formatOptions problem ->
                    ( Done
                    , stop formatOptions problem
                    )

                InitError.StringProblem string ->
                    ( Done
                    , Debug.todo "stop on stringProblem"
                    )

        Err decodingError ->
            ( Done
            , Debug.todo ("Problem decoding flags: " ++ Decode.errorToString decodingError)
            )


flagsDecoder : Decode.Decoder Flags
flagsDecoder =
    Decode.map2 Flags
        (Decode.field "args" (Decode.list Decode.string))
        (Decode.field "env" (Decode.dict Decode.string))


startTask : Pool msg -> ConcurrentTask msg msg -> ( Pool msg, Cmd (Msg msg) )
startTask pool task_ =
    ConcurrentTask.attempt
        { send = send
        , pool = pool
        , onComplete = TaskOnComplete
        }
        task_


update : (msg -> model -> ( model, TCmd msg )) -> Msg msg -> ModelWrapper model msg -> ( ModelWrapper model msg, Cmd (Msg msg) )
update updateFn msg modelWrapper =
    case modelWrapper of
        Done ->
            ( Done, Cmd.none )

        Running { mainModel, pool } ->
            case msg of
                MainMsg mainMsg ->
                    let
                        ( newMainModel, mainCmd ) =
                            updateFn mainMsg mainModel

                        ( newPool, cmd ) =
                            taskToCmd pool mainCmd
                    in
                    ( Running
                        { mainModel = newMainModel
                        , pool = newPool
                        }
                    , cmd
                    )

                TaskOnProgress ( newPool, cmd ) ->
                    ( Running { mainModel = mainModel, pool = newPool }, cmd )

                TaskOnComplete _ ->
                    ( modelWrapper, Cmd.none )


{-| Converts a `Testable.Cmd` into a `Cmd`

    TestableCmd.none
        |> Testable.cmd
        == Cmd.none

-}
taskToCmd : Pool msg -> TestableCmd.Cmd msg -> ( Pool msg, Cmd (Msg msg) )
taskToCmd pool testableEffects =
    case testableEffects of
        Internal.None ->
            ( pool, Cmd.none )

        Internal.TaskCmd testableTask ->
            task testableTask
                |> startTask pool

        Internal.Batch list ->
            List.foldl
                (\t ( p, cmds ) ->
                    taskToCmd p t
                        |> Tuple.mapSecond (\cmd -> cmd :: cmds)
                )
                ( pool, [] )
                list
                |> Tuple.mapSecond Cmd.batch

        Internal.PrintLn console string ->
            ( pool
            , effects.println console string
                |> Cmd.map never
            )

        Internal.Exit code ->
            ( pool
            , effects.exit code
                |> Cmd.map never
            )


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

        -- File system
        Internal.Stat path onResult ->
            effects.stat path
                |> handle onResult

        Internal.ReadTextFile path onResult ->
            effects.readTextFile path
                |> handle onResult

        Internal.WriteTextFile path string onResult ->
            effects.writeTextFile path string
                |> handle onResult

        Internal.DeleteFile path onResult ->
            effects.deleteFile path
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
        Internal.HttpGet url onResult ->
            effects.httpGet url
                |> handle onResult

        -- Stdin
        Internal.ReadKey onResult ->
            effects.readKey ()
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


readTextFile : String -> ConcurrentTask FsData.FsError String
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


stat : String -> ConcurrentTask FsData.FsError FileStat
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


statDecoder : Decoder FileStat
statDecoder =
    Decode.map5 FileStat
        (Decode.field "isFile" Decode.bool)
        (Decode.field "isDirectory" Decode.bool)
        (Decode.field "isSymlink" Decode.bool)
        (Decode.field "size" Decode.int)
        (Decode.field "modifiedTime" Decode.int)


decodeFsError : Decoder FsData.FsError
decodeFsError =
    Decode.field "kind" Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "PermissionDenied" ->
                        Decode.succeed FsData.PermissionDenied

                    "NotFound" ->
                        Decode.map FsData.NotFound (Decode.field "data" Decode.string)

                    "IoError" ->
                        Decode.map FsData.NotFound (Decode.field "data" Decode.string)

                    _ ->
                        Decode.fail ("Unknown kind: " ++ kind)
            )


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
                , TSub.subscriptions NodeEffects.subEffects (subsFn mainModel)
                    |> Sub.map MainMsg
                ]


stop : Problem.FormatOptions options -> Problem -> Cmd msg
stop formatOptions problem =
    Debug.todo "stop"


type Output
    = A


port send : Decode.Value -> Cmd msg


port receive : (Decode.Value -> msg) -> Sub msg


type alias Effects =
    { -- File system
      readTextFile : Path -> ConcurrentTask FsError String
    , writeTextFile : Path -> String -> ConcurrentTask FsError ()
    , stat : Path -> ConcurrentTask FsError FileStat
    , deleteFile : Path -> ConcurrentTask FsError ()
    , createDirectory : Path -> ConcurrentTask FsError ()
    , removeDirectory : Path -> ConcurrentTask FsError ()
    , copyDirectory : { from : Path, to : Path } -> ConcurrentTask SpawnError ()
    , walkTree : Path -> Maybe String -> MatchKind -> ConcurrentTask FsError (List Path)
    , httpGet : String -> ConcurrentTask () String

    -- Stdin / Stdout
    , readKey : () -> ConcurrentTask StdinError Key
    , println : Console -> String -> Cmd Never
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
    , stat = stat
    , deleteFile = \path -> Debug.todo "deleteFile"
    , createDirectory = \path -> Debug.todo "createDirectory"
    , removeDirectory = \path -> Debug.todo "removeDirectory"
    , copyDirectory = \path -> Debug.todo "copyDirectory"
    , walkTree = \path pattern matchKind -> Debug.todo "walkTree"

    -- Http
    , httpGet = \url -> Debug.todo "httpGet"

    -- Stdin / Stdout
    , readKey = \() -> Debug.todo "readKey"
    , println = \console string -> Debug.todo "println, use a port"
    , exit = \code -> Debug.todo "exit, use a port"

    -- Process
    , runProcess = \command options -> Debug.todo "runProcess"
    , spawnProcess = \command options -> Debug.todo "spawnProcess"
    , waitProcess = \pid -> Debug.todo "waitProcess"
    , killProcess = \pid signal -> Debug.todo "killProcess"
    }
