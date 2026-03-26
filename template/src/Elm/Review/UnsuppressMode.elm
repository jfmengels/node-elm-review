module Elm.Review.UnsuppressMode exposing (UnsuppressMode(..))

import Set exposing (Set)


type UnsuppressMode
    = UnsuppressAll
    | UnsuppressRules (Set String)
    | UnsuppressNone
