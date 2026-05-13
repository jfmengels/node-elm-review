module Elm.Review.Testable.Task exposing
    ( Task, succeed, fail
    , map
    , andThen
    , mapError, onError, toMaybe, toResult
    , perform
    )

{-| `Testable.Task` is a replacement for the core `Task` module. You can use it
to create components that can be tested with `Testable.TestContext`. You can
convert `Testable.Task` into a core `Task` with the `Testable` module.


# Basics

@docs Task, succeed, fail


# Mapping

@docs map


# Chaining

@docs andThen


# Errors

@docs mapError, onError, toMaybe, toResult


# Commands

@docs perform

-}

import Elm.Review.Testable.Internal as Internal exposing (TaskResult(..))


{-| Represents asynchronous effects that may fail. It is useful for stuff like
HTTP.
For example, maybe we have a task with the type (`Task String User`). This means
that when we perform the task, it will either fail with a `String` message or
succeed with a `User`. So this could represent a task that is asking a server
for a certain user.
-}
type alias Task error value =
    Internal.Task error value


{-| A task that succeeds immediately when run.

    succeed 42 -- results in 42

-}
succeed : a -> Task x a
succeed value =
    Internal.ImmediateTask (Success value)


{-| A task that fails immediately when run.

    fail "file not found" : Task String a

-}
fail : x -> Task x a
fail error =
    Internal.ImmediateTask (Failure error)


{-| Transform a task.

    map sqrt (succeed 9) == succeed 3

-}
map : (a -> b) -> Task x a -> Task x b
map f source =
    transform (resultMap f) source



-- Chaining


{-| Chain together a task and a callback. The first task will run, and if it is
successful, you give the result to the callback resulting in another task. This
task then gets run.

    succeed 2 |> andThen (\n -> succeed (n + 2)) == succeed 4

This is useful for chaining tasks together. Maybe you need to get a user from
your servers _and then_ lookup their picture once you know their name.

-}
andThen : (a -> Task x b) -> Task x a -> Task x b
andThen next source =
    transform (resultAndThen next) source



-- Errors


{-| Transform the error value. This can be useful if you need a bunch of error
types to match up.

    type Error
        = Http Http.Error
        | WebGL WebGL.Error

    getResources : Task Error Resource
    getResources =
        sequence [ mapError Http serverTask, mapError WebGL textureTask ]

-}
mapError : (x -> y) -> Task x a -> Task y a
mapError f task =
    transform
        (\res ->
            case res of
                Success value ->
                    Success value

                Failure error ->
                    Failure (f error)

                Continue next ->
                    Continue (mapError f next)
        )
        task


{-| TODO Describe onError
-}
onError : (x -> Task y a) -> Task x a -> Task y a
onError next source =
    transform (resultOnError next) source


resultOnError : (x -> Task y a) -> TaskResult x a -> TaskResult y a
resultOnError f source =
    case source of
        Success value ->
            Success value

        Failure error ->
            Continue (f error)

        Continue next ->
            Continue (onError f next)


{-| Helps with handling failure. Instead of having a task fail with some value
of type `x` it promotes the failure to a `Nothing` and turns all successes into
`Just` something.

    toMaybe (fail "file not found") == succeed Nothing

    toMaybe (succeed 42) == succeed (Just 42)

This means you can handle the error with the `Maybe` module instead.

-}
toMaybe : Task x a -> Task never (Maybe a)
toMaybe source =
    transform (resultToResult >> resultMap Result.toMaybe) source


{-| Helps with handling failure. Instead of having a task fail with some value
of type `x` it promotes the failure to an `Err` and turns all successes into
`Ok` something.

    toResult (fail "file not found") == succeed (Err "file not found")

    toResult (succeed 42) == succeed (Ok 42)

This means you can handle the error with the `Result` module instead.

-}
toResult : Task x a -> Task never (Result x a)
toResult source =
    transform resultToResult source


transform : (TaskResult x a -> TaskResult y b) -> Task x a -> Task y b
transform tx source =
    case source of
        Internal.ImmediateTask result ->
            Internal.ImmediateTask (result |> tx)

        -- File system
        Internal.Stat path onResult ->
            Internal.Stat path (onResult >> tx)

        Internal.ReadTextFile path onResult ->
            Internal.ReadTextFile path (onResult >> tx)

        Internal.WriteTextFile path string onResult ->
            Internal.WriteTextFile path string (onResult >> tx)

        Internal.DeleteFile path onResult ->
            Internal.DeleteFile path (onResult >> tx)

        Internal.CreateDirectory path onResult ->
            Internal.CreateDirectory path (onResult >> tx)

        Internal.RemoveDirectory path onResult ->
            Internal.RemoveDirectory path (onResult >> tx)

        Internal.WalkTree path pattern matchKind onResult ->
            Internal.WalkTree path pattern matchKind (onResult >> tx)

        -- Stdin
        Internal.ReadKey onResult ->
            Internal.ReadKey (onResult >> tx)



-- Commands


{-| Command the runtime system to perform a task. The most important argument
is the `Task` which describes what you want to happen. But you also need to
provide functions to tag the two possible outcomes of the task. It can fail or
succeed, but either way, you need to have a message to feed back into your
application.
-}
perform : (Result x a -> msg) -> Task x a -> Internal.Cmd msg
perform toMessage task =
    task
        |> toResult
        |> map toMessage
        |> Internal.TaskCmd



-- TaskResult


resultMap : (a -> b) -> TaskResult x a -> TaskResult x b
resultMap f source =
    case source of
        Success value ->
            Success (f value)

        Failure error ->
            Failure error

        Continue next ->
            Continue (map f next)


resultAndThen : (a -> Task x b) -> TaskResult x a -> TaskResult x b
resultAndThen f source =
    case source of
        Success value ->
            Continue (f value)

        Failure error ->
            Failure error

        Continue next ->
            Continue (andThen f next)


resultToResult : TaskResult x a -> TaskResult never (Result x a)
resultToResult source =
    case source of
        Success value ->
            Success (Ok value)

        Failure error ->
            Success (Err error)

        Continue next ->
            Continue (toResult next)
