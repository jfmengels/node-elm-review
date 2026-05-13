module Elm.Review.Testable exposing
    ( Effects
    , cmd, task
    , init, update
    )

{-| This module converts Testable things into real things.


# Basics

@docs Effects
@docs cmd, task


# StartApp helpers

@docs init, update

-}

import Elm.Review.Testable.Cmd as TestableCmd
import Elm.Review.Testable.FsData exposing (FileStat, FsError, MatchKind)
import Elm.Review.Testable.Internal as Internal exposing (TaskResult)
import Elm.Review.Testable.ProcessData exposing (ProcessError)
import Elm.Review.Testable.StdinData exposing (Key, StdinError)
import Elm.Review.Testable.Task as TestableTask
import ElmReview.Path exposing (Path)
import Task as PlatformTask


type alias Effects =
    { -- File system
      readTextFile : Path -> PlatformTask.Task FsError String
    , writeTextFile : Path -> String -> PlatformTask.Task FsError ()
    , stat : Path -> PlatformTask.Task FsError FileStat
    , deleteFile : Path -> PlatformTask.Task FsError ()
    , createDirectory : Path -> PlatformTask.Task FsError ()
    , removeDirectory : Path -> PlatformTask.Task FsError ()
    , copyDirectory : { from : Path, to : Path } -> PlatformTask.Task ProcessError ()
    , walkTree : Path -> Maybe String -> MatchKind -> PlatformTask.Task FsError (List Path)

    -- Stdin
    , readKey : () -> PlatformTask.Task StdinError Key
    }


{-| Converts a `Testable.Cmd` into a `Cmd`

    TestableCmd.none
        |> Testable.cmd
        == Cmd.none

-}
cmd : Effects -> TestableCmd.Cmd msg -> Cmd msg
cmd effects testableEffects =
    case testableEffects of
        Internal.None ->
            Cmd.none

        Internal.TaskCmd testableTask ->
            task effects testableTask
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
            Cmd.batch (List.map (\t -> cmd effects t) list)


{-| Converts a `Testable.Task` into a `Task`

    Testable.Task.succeed "A"
        |> Testable.task
        == Task.succeed "A"

-}
task : Effects -> TestableTask.Task error value -> PlatformTask.Task error value
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

        -- Stdin
        Internal.ReadKey onResult ->
            effects.readKey ()
                |> handle effects onResult


handle : Effects -> (Result x value -> TaskResult error a) -> PlatformTask.Task x value -> PlatformTask.Task error a
handle effects onResult source =
    source
        |> toResultTask
        |> PlatformTask.map onResult
        |> (\result -> PlatformTask.andThen (taskResult effects) result)


toResultTask : PlatformTask.Task x value -> PlatformTask.Task never (Result x value)
toResultTask task_ =
    task_
        |> PlatformTask.map Ok
        |> PlatformTask.onError (\x -> PlatformTask.succeed (Err x))


taskResult : Effects -> Internal.TaskResult error value -> PlatformTask.Task error value
taskResult effects result =
    case result of
        Internal.Success msg ->
            PlatformTask.succeed msg

        Internal.Failure error ->
            PlatformTask.fail error

        Internal.Continue next ->
            task effects next


{-| Converts a testable StartApp-style init value into a standard StartApp init value
-}
init : Effects -> ( model, TestableCmd.Cmd msg ) -> ( model, Cmd msg )
init effects ( model, testableEffects ) =
    ( model, cmd effects testableEffects )


{-| Converts a testable StartApp-style update function into a standard StartApp update function
-}
update : Effects -> (msg -> model -> ( model, TestableCmd.Cmd msg )) -> (msg -> model -> ( model, Cmd msg ))
update effects fn msg model =
    fn msg model
        |> init effects
