module Wrapper.Options exposing
    ( Options, SubCommand(..)
    , Flag, Argument, Display
    , Color(..)
    )

{-|

@docs Options, SubCommand
@docs Flag, Argument, Display

-}


type alias Options =
    { subCommand : Maybe SubCommand
    , help : Bool
    , directoriesToAnalyze : List String
    , -- TODO Remove field
      appBinary : String
    }


type SubCommand
    = Init
    | NewPackage
    | NewRule
    | Suppress
    | PrepareOffline


type alias Flag =
    { name : String
    , alias : Maybe String
    , argument : Maybe Argument
    , display : Maybe ((Color -> String -> String) -> Display)
    }


type alias Argument =
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
