module Wrapper.Hash exposing (Hash, fromString)


type Hash
    = Hash String


fromString : String -> Hash
fromString =
    Hash
