module Elm.Review.Testable.FileWatcher exposing (watch)

import Elm.Review.Testable.FileWatchData exposing (FileEvent, WatchOptions)
import Elm.Review.Testable.Internal as Internal exposing (TSub)


watch : WatchOptions -> (FileEvent -> msg) -> TSub msg
watch =
    Internal.WatchFiles
