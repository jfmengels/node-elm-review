module Elm.Review.Testable.FileWatcher exposing (watch)

import Elm.Review.Testable.FileWatchData exposing (FileEvent, WatchOptions)
import Elm.Review.Testable.Internal as Internal exposing (TSub)


watch : String -> WatchOptions -> (FileEvent -> msg) -> TSub msg
watch path options toMsg =
    Internal.WatchFiles path options toMsg
