module Elm.Review.RunEnvironment exposing (RunEnvironment)

{-| Information about the environment in which the review application runs.

@docs RunEnvironment

-}


type alias RunEnvironment =
    { elmVersion : String
    , elmHomePath : String
    , reviewFolder : String
    }
