module Wrapper.Auth exposing
    ( Auth
    , fromString, toString
    )

{-|

@docs Auth
@docs fromString, toString

-}


type Auth
    = Auth String


fromString : String -> Auth
fromString =
    Auth


toString : Auth -> String
toString (Auth auth) =
    auth
