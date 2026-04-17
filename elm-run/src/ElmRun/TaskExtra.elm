module ElmRun.TaskExtra exposing (mapAll, resultToTask)

{-| Like Task.map f >> Task.sequence but the return value is ()
-}

import Task exposing (Task)


resultToTask : Result x a -> Task x a
resultToTask result =
    case result of
        Ok value ->
            Task.succeed value

        Err err ->
            Task.fail err


mapAll : (a -> Task x ()) -> List a -> Task x ()
mapAll f list =
    List.foldl (\task acc -> Task.map2 always (f task) acc) (Task.succeed ()) list
