module Elm.Review.Testable.Cmd exposing (Cmd, map, batch, none)

{-| `Testable.Cmd` is a replacement for the core `Cmd` module. You can use it
to create components that can be tested with `Testable.TestContext`. You can
convert `Testable.Cmd` into a core `Cmd` with the `Testable` module.

@docs Cmd, map, batch, none

-}

import Elm.Review.Testable.Internal as Internal
import Elm.Review.Testable.TTask as Task


{-| -}
type alias Cmd msg =
    Internal.Cmd msg


{-| -}
none : Cmd never
none =
    Internal.None


{-| -}
batch : List (Cmd msg) -> Cmd msg
batch effectsList =
    Internal.Batch effectsList


{-| -}
map : (a -> b) -> Cmd a -> Cmd b
map f source =
    case source of
        Internal.None ->
            Internal.None

        Internal.TaskCmd wrapped ->
            wrapped
                |> Task.map f
                |> Task.mapError f
                |> Internal.TaskCmd

        Internal.Batch list ->
            Internal.Batch (List.map (map f) list)
