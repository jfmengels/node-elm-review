module Wrapper.Flag exposing
    ( Flag, Argument(..), Display
    , color
    )

{-|

@docs Flag, Argument, Display
@docs color

-}

import ElmReview.Color as Color exposing (Color, Colorize)
import ElmReview.Problem exposing (ProblemSimple)
import Wrapper.Options.InternalOptions exposing (InternalOptions)
import Wrapper.Section exposing (Section)


type alias Flag =
    { name : String
    , argument : Argument
    , display : Maybe Display
    }


type Argument
    = ArgumentAbsent (String -> InternalOptions -> InternalOptions)
    | ArgumentPresent
        { argName : String
        , mayBeUsedSeveralTimes : Bool
        , usesEquals : Bool
        , apply : String -> String -> InternalOptions -> Result (Maybe ProblemSimple) InternalOptions
        }


type alias Display =
    { sections : List Section
    , color : Color
    , description : Colorize -> List String
    , initDescription : Maybe (Colorize -> List String)
    , newPackageDescription : Maybe (Colorize -> List String)
    }


color : Flag -> Color
color flag =
    case flag.display of
        Just display ->
            display.color

        Nothing ->
            Color.Cyan
