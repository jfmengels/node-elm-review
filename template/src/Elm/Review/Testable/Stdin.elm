module Elm.Review.Testable.Stdin exposing (readKey)

import Elm.Review.Testable.Internal as Internal
import Elm.Review.Testable.StdinData exposing (Key, StdinError)


{-| Read a single keypress.
-}
readKey : Internal.TTask StdinError Key
readKey =
    Internal.ReadKey Internal.resultFromResult
