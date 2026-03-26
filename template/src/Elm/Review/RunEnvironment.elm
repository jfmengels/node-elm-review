module Elm.Review.RunEnvironment exposing
    ( RunEnvironment
    , suppressionFolder
    )

{-| Information about the environment in which the review application runs.

@docs RunEnvironment
@docs suppressionFolder

-}


type alias RunEnvironment =
    { elmVersion : String
    , elmHomePath : String
    , reviewFolder : String
    , namespace : String
    }


suppressionFolder : RunEnvironment -> String
suppressionFolder runEnvironment =
    -- TODO Use path functions
    runEnvironment.reviewFolder ++ "/suppressed"
