module Wrapper.Options exposing
    ( Options
    , Flag, Argument(..), Display
    )

{-|

@docs Options
@docs Flag, Argument, Display

-}

import Wrapper.Color exposing (Color, Colorize)
import Wrapper.Options.InternalOptions exposing (InternalOptions)
import Wrapper.Section exposing (Section)
import Wrapper.Subcommand exposing (Subcommand)


type alias Options =
    { subcommand : Maybe Subcommand
    , help : Bool
    , directoriesToAnalyze : List String
    , -- TODO Remove field
      appBinary : String
    }


type alias Flag =
    { name : String
    , alias : Maybe String
    , argument : Argument
    , display : Maybe Display
    }


type Argument
    = ArgumentAbsent (InternalOptions -> InternalOptions)
    | ArgumentPresent
        { argName : String
        , mayBeUsedSeveralTimes : Bool
        , usesEquals : Bool
        , apply : String -> InternalOptions -> Result () InternalOptions
        }


type alias Display =
    { sections : List Section
    , color : Color
    , description : Colorize -> List String
    , initDescription : Maybe (Colorize -> List String)
    , newPackageDescription : Maybe (Colorize -> List String)
    }
