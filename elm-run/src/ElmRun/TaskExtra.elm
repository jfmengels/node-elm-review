module ElmRun.TaskExtra exposing (mapAll)

{-| Like Task.map f >> Task.sequence but the return value is ()
-}

import Task exposing (Task)


mapAll : (a -> Task x ()) -> List a -> Task x ()
mapAll f list =
    List.foldl (\task acc -> Task.map2 always (f task) acc) (Task.succeed ()) list
