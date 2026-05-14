port module Node.Program exposing (Config, Program, program)

import ConcurrentTask exposing (ConcurrentTask, Pool)
import ConcurrentTask.Http
import Dict exposing (Dict)
import Elm.Review.InitError as InitError
import Elm.Review.Testable as Testable exposing (Effects)
import Elm.Review.Testable.Cmd as TestableCmd
import Elm.Review.Testable.FsData as FsData
import Elm.Review.Testable.Internal as Internal exposing (TCmd, TaskResult)
import Elm.Review.Testable.TSub as TSub exposing (TSub)
import Elm.Review.Testable.TTask exposing (TTask)
import ElmReview.Problem as Problem exposing (Problem)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Node.Effects as NodeEffects
import Task as PlatformTask


type ModelWrapper model msg
    = Done
    | Running (Model model msg)


type alias Model model msg =
    { mainModel : model
    , tasks : ConcurrentTask.Pool (Msg msg)
    }


type Msg msg
    = MainMsg msg
    | TaskOnProgress ( ConcurrentTask.Pool (Msg msg), Cmd (Msg msg) ) -- updates task progress
    | TaskOnComplete (ConcurrentTask.Response ConcurrentTask.Http.Error Output)


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
                InitError.Success ( mainModel, cmd ) ->
                    ( Running
                        { mainModel = mainModel
                        , tasks = ConcurrentTask.pool
                        }
                    , Testable.cmd NodeEffects.effects cmd
                        |> Cmd.map MainMsg
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


type TransactionError
    = ReadFileError String


type alias Pool msg =
    ConcurrentTask.Pool (Msg msg)


startTask : { pool : Pool msg, task : ConcurrentTask ConcurrentTask.Http.Error Output } -> ( Pool msg, Cmd (Msg msg) )
startTask options =
    ConcurrentTask.attempt
        { send = send
        , pool = options.pool
        , onComplete = TaskOnComplete
        }
        options.task


update : (msg -> model -> ( model, TCmd msg )) -> Msg msg -> ModelWrapper model msg -> ( ModelWrapper model msg, Cmd (Msg msg) )
update updateFn msg modelWrapper =
    case modelWrapper of
        Done ->
            ( Done, Cmd.none )

        Running { mainModel, tasks } ->
            case msg of
                MainMsg mainMsg ->
                    let
                        ( newMainModel, cmd ) =
                            updateFn mainMsg mainModel
                    in
                    ( Running
                        { mainModel = newMainModel
                        , tasks = tasks
                        }
                    , Testable.cmd NodeEffects.effects cmd
                        |> Cmd.map MainMsg
                    )

                TaskOnProgress ( pool, cmd ) ->
                    ( Running { mainModel = mainModel, tasks = pool }, cmd )

                TaskOnComplete _ ->
                    ( modelWrapper, Cmd.none )


{-| Converts a `Testable.Cmd` into a `Cmd`

    TestableCmd.none
        |> Testable.cmd
        == Cmd.none

-}
taskToCmd : TestableCmd.Cmd msg -> Cmd msg
taskToCmd testableEffects =
    case testableEffects of
        Internal.None ->
            Cmd.none

        Internal.TaskCmd testableTask ->
            Testable.task NodeEffects.effects testableTask
                |> toResultTask
                |> PlatformTask.perform
                    (\res ->
                        case res of
                            Ok msg ->
                                msg

                            Err msg ->
                                msg
                    )

        Internal.Batch list ->
            Cmd.batch (List.map (\t -> taskToCmd t) list)

        Internal.PrintLn console string ->
            NodeEffects.effects.println console string
                |> Cmd.map never

        Internal.Exit code ->
            NodeEffects.effects.exit code
                |> Cmd.map never


{-| Converts a `Testable.Task` into a `Task`

    Testable.Task.succeed "A"
        |> Testable.task
        == Task.succeed "A"

-}
task : Effects -> TTask error value -> PlatformTask.Task error value
task effects testableTask =
    case testableTask of
        Internal.ImmediateTask result ->
            taskResult effects result

        -- File system
        Internal.Stat path onResult ->
            effects.stat path
                |> handle effects onResult

        Internal.ReadTextFile path onResult ->
            effects.readTextFile path
                |> handle effects onResult

        Internal.WriteTextFile path string onResult ->
            effects.writeTextFile path string
                |> handle effects onResult

        Internal.DeleteFile path onResult ->
            effects.deleteFile path
                |> handle effects onResult

        Internal.CreateDirectory path onResult ->
            effects.createDirectory path
                |> handle effects onResult

        Internal.RemoveDirectory path onResult ->
            effects.removeDirectory path
                |> handle effects onResult

        Internal.CopyDirectory targets onResult ->
            effects.copyDirectory targets
                |> handle effects onResult

        Internal.WalkTree path pattern matchKind onResult ->
            effects.walkTree path pattern matchKind
                |> handle effects onResult

        -- Http
        Internal.HttpGet url onResult ->
            effects.httpGet url
                |> handle effects onResult

        -- Stdin
        Internal.ReadKey onResult ->
            effects.readKey ()
                |> handle effects onResult

        -- Process
        Internal.RunProcess command spawnOptions onResult ->
            effects.runProcess command spawnOptions
                |> handle effects onResult

        Internal.SpawnProcess command spawnOptions onResult ->
            effects.spawnProcess command spawnOptions
                |> handle effects onResult

        Internal.WaitProcess processId onResult ->
            effects.waitProcess processId
                |> handle effects onResult

        Internal.KillProcess processId signal onResult ->
            effects.killProcess processId signal
                |> handle effects onResult


readTextFile : String -> String -> ConcurrentTask FsData.FsError ()
readTextFile path content =
    ConcurrentTask.define
        { function = "fs:readTextFile"
        , expect = ConcurrentTask.expectWhatever
        , errors = ConcurrentTask.expectErrors decodeFsError
        , args =
            Encode.object
                [ ( "path", Encode.string path )
                , ( "content", Encode.string content )
                ]
        }


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


handle : Effects -> (Result x value -> TaskResult error a) -> PlatformTask.Task x value -> PlatformTask.Task error a
handle effects onResult source =
    source
        |> toResultTask
        |> PlatformTask.map onResult
        |> (\result -> PlatformTask.andThen (taskResult effects) result)


taskResult : Effects -> Internal.TaskResult error value -> PlatformTask.Task error value
taskResult effects result =
    case result of
        Internal.Success msg ->
            PlatformTask.succeed msg

        Internal.Failure error ->
            PlatformTask.fail error

        Internal.Continue next ->
            task effects next


toResultTask : PlatformTask.Task x value -> PlatformTask.Task never (Result x value)
toResultTask task_ =
    task_
        |> PlatformTask.map Ok
        |> PlatformTask.onError (\x -> PlatformTask.succeed (Err x))


subscriptions : (model -> TSub msg) -> ModelWrapper model msg -> Sub (Msg msg)
subscriptions subsFn model =
    case model of
        Done ->
            Sub.none

        Running { mainModel, tasks } ->
            Sub.batch
                [ ConcurrentTask.onProgress
                    { send = send
                    , receive = receive
                    , onProgress = TaskOnProgress
                    }
                    tasks
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
