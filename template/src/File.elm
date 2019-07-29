module File exposing
    ( File
    , decode
    )

{-| Represents a file


# Definition

@docs File


# Decoding

@decode

-}

import Json.Decode as Decode



-- DEFINITION


type alias File =
    { name : String
    , source : String
    }



-- DECODING


decode : Decode.Decoder File
decode =
    Decode.map2 (\name_ source_ -> { name = name_, source = source_ })
        (Decode.field "name" Decode.string)
        (Decode.field "source" Decode.string)
