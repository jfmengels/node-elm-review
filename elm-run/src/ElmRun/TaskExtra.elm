module ElmRun.TaskExtra exposing
    ( sequence, mapAllAndFold, mapAllAndIgnore
    , resultToTask, toResultTask
    , otherwise
    )

{-|

@docs sequence, mapAllAndFold, mapAllAndIgnore
@docs resultToTask, toResultTask
@docs otherwise

-}

import Task exposing (Task)


resultToTask : Result x a -> Task x a
resultToTask result =
    case result of
        Ok value ->
            Task.succeed value

        Err err ->
            Task.fail err


toResultTask : Task x value -> Task never (Result x value)
toResultTask task =
    task
        |> Task.map Ok
        |> Task.onError (\x -> Task.succeed (Err x))


otherwise : (() -> Task x a) -> Maybe a -> Task x a
otherwise alternative maybe =
    case maybe of
        Just reference ->
            Task.succeed reference

        Nothing ->
            alternative ()


{-| Like Task.sequence but ignores the tasks' results.
-}
sequence : List (Task x ()) -> Task x ()
sequence list =
    List.foldl (\task acc -> Task.map2 always acc task) (Task.succeed ()) list


mapAllAndFold : (a -> Task x b) -> (b -> c -> c) -> c -> List a -> Task x c
mapAllAndFold f fold initial list =
    List.foldl (\task acc -> Task.map2 (\c b -> fold b c) acc (f task)) (Task.succeed initial) list


{-| Like Task.map f >> Task.sequence but ignores the tasks' results.
-}
mapAllAndIgnore : (a -> Task x ()) -> List a -> Task x ()
mapAllAndIgnore f list =
    List.foldl (\task acc -> Task.map2 always acc (f task)) (Task.succeed ()) list
