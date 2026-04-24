module ElmRun.TaskExtra exposing
    ( mapAllAndFold, mapAllAndIgnore
    , resultToTask, toResultTask
    , otherwise
    )

{-|

@docs mapAllAndFold, mapAllAndIgnore
@docs resultToTask, toResultTask
@docs otherwise

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


toResultTask : Task x value -> Task never (Result () value)
toResultTask task =
    task
        |> Task.map Ok
        |> Task.onError (\_ -> Task.succeed (Err ()))


otherwise : (() -> Task x a) -> Maybe a -> Task x a
otherwise alternative maybe =
    case maybe of
        Just reference ->
            Task.succeed reference

        Nothing ->
            alternative ()


mapAllAndFold : (a -> Task x b) -> (b -> c -> c) -> c -> List a -> Task x c
mapAllAndFold f fold initial list =
    List.foldl (\task acc -> Task.map2 (\c b -> fold b c) acc (f task)) (Task.succeed initial) list


mapAllAndIgnore : (a -> Task x ()) -> List a -> Task x ()
mapAllAndIgnore f list =
    List.foldl (\task acc -> Task.map2 always acc (f task)) (Task.succeed ()) list
