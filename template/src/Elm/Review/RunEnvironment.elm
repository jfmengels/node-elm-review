module Elm.Review.RunEnvironment exposing (RunEnvironment)

{-| Information about the environment in which the review application runs.

@docs RunEnvironment

-}

import ElmReview.Path exposing (Path)


type alias RunEnvironment =
    { packagesLocation : Path
    , reviewFolder : Path
    }
