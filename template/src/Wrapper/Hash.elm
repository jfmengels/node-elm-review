module Wrapper.Hash exposing
    ( Hash
    , initial, fromList
    , toString
    )

{-|

@docs Hash
@docs initial, fromList
@docs toString

-}

import FNV1a


type Hash
    = Hash Int


initial : Hash
initial =
    Hash FNV1a.initialSeed


fromList : (a -> String) -> Hash -> List a -> Hash
fromList fn (Hash previous) list =
    list
        |> List.foldl (\a hash -> FNV1a.hashWithSeed (fn a) hash) previous
        |> Hash


toString : Hash -> String
toString (Hash hash) =
    String.fromInt hash
