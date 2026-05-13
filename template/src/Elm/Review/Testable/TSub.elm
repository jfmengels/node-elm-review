module Elm.Review.Testable.TSub exposing
    ( TSub
    , none, map
    , batch, mapBatch
    , subscriptions, SubEffects
    )

{-|

@docs TSub
@docs none, map
@docs batch, mapBatch
@docs subscriptions, SubEffects

-}

import Elm.Review.Testable.FileWatchData exposing (FileEvent, WatchOptions)
import Elm.Review.Testable.Internal as Internal exposing (TaskResult(..))
import ElmReview.Path exposing (Path)


{-| "TSub" stands for "Testable Subscription".
-}
type alias TSub msg =
    Internal.TSub msg


type alias SubEffects msg =
    { watchFiles : Path -> WatchOptions -> (FileEvent -> msg) -> Sub.Sub msg
    }


subscriptions : SubEffects msg -> TSub msg -> Sub.Sub msg
subscriptions subEffects sub =
    case sub of
        Internal.WatchFiles path watchOptions toMsg ->
            subEffects.watchFiles path watchOptions toMsg

        Internal.SubBatch list ->
            Sub.batch (List.map (subscriptions subEffects) list)


map : (a -> b) -> TSub a -> TSub b
map f sub =
    case sub of
        Internal.SubBatch list ->
            Internal.SubBatch (List.map (map f) list)

        Internal.WatchFiles path watchOptions toMsg ->
            Internal.WatchFiles path watchOptions (toMsg >> f)


batch : List (TSub msg) -> TSub msg
batch =
    Internal.SubBatch


mapBatch : (a -> TSub msg) -> List a -> TSub msg
mapBatch fn list =
    batch (List.map fn list)


none : TSub msg
none =
    Internal.SubBatch []
