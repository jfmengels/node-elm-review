module Wrapper.Hash exposing (Hash, fromString, toString)


type Hash
    = Hash String


fromString : String -> Hash
fromString =
    Hash


toString : Hash -> String
toString (Hash hash) =
    hash
