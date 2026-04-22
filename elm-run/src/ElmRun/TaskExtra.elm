module ElmRun.TaskExtra exposing
    ( mapAllAndIgnore
    , resultToTask
    , toResultTask
    )

{-|

@docs mapAllAndIgnore
@docs resultToTask
@docs toResultTask

-}

import Task exposing (Task)


{-| Like Task.map f >> Task.sequence but the return value is ()
-}
resultToTask : Result x a -> Task x a
resultToTask result =
    case result of
        Ok value ->
            Task.succeed value

        Err err ->
            Task.fail err


mapAllAndIgnore : (a -> Task x ()) -> List a -> Task x ()
mapAllAndIgnore f list =
    List.foldl (\task acc -> Task.map2 always (f task) acc) (Task.succeed ()) list


toResultTask : Task x value -> Task never (Result () value)
toResultTask task =
    task
        |> Task.map Ok
        |> Task.onError (\_ -> Task.succeed (Err ()))
