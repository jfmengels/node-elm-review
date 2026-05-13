module Elm.Review.Testable.Http exposing (get)

import Elm.Review.Testable.Internal as Internal


get url =
    Internal.HttpGet url Internal.resultFromResult
