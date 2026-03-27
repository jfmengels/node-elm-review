module Wrapper.Options exposing
    ( Options
    , Flag, Argument(..), Display
    , Color(..)
    )

{-|

@docs Options
@docs Flag, Argument, Display
@docs Color

-}

import Wrapper.Options.InternalOptions exposing (InternalOptions)
import Wrapper.SubCommand exposing (SubCommand)


type alias Options =
    { subCommand : Maybe SubCommand
    , help : Bool
    , directoriesToAnalyze : List String
    , -- TODO Remove field
      appBinary : String
    }


type alias Flag =
    { name : String
    , alias : Maybe String
    , argument : Argument
    , display : Maybe ((Color -> String -> String) -> Display)
    }


type Argument
    = ArgumentAbsent
    | ArgumentPresent
        { argName : String
        , mayBeUsedSeveralTimes : Bool
        , usesEquals : Bool
        }


type alias Display =
    { sections : List String
    , color : Color
    , description : List String
    , initDescription : Maybe (List String)
    , newPackageDescription : Maybe (List String)
    }


type Color
    = Cyan
    | Orange
    | Yellow
    | Magenta
    | GreenBright
    | BlueBright
    | MagentaBright
