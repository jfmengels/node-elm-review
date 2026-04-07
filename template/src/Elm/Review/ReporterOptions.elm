module Elm.Review.ReporterOptions exposing (DetailsMode(..), ReportFixMode(..))

{-| -}


{-| Mode in which `elm-review` is running.
-}
type ReportFixMode
    = Reviewing
    | Fixing


type DetailsMode
    = WithDetails
    | WithoutDetails
