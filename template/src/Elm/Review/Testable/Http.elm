module Elm.Review.Testable.Http exposing (get)

import Elm.Review.Testable.Internal as Internal


get : String -> Internal.TTask () String
get url =
    Internal.HttpGet url Internal.resultFromResult
