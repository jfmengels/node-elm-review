module Elm.Review.Testable.Http exposing
    ( getBytes
    , getString
    )

import Bytes exposing (Bytes)
import Elm.Review.Testable.Internal as Internal


getString : String -> Internal.TTask () String
getString url =
    Internal.HttpGetString url Internal.resultFromResult


getBytes : String -> Internal.TTask () Bytes
getBytes url =
    Internal.HttpGetBytes url Internal.resultFromResult
