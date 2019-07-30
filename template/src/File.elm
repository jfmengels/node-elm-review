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
    { path : String
    , source : String
    }



-- DECODING


decode : Decode.Decoder File
decode =
    Decode.map2 (\path_ source_ -> { path = path_, source = source_ })
        (Decode.field "path" Decode.string)
        (Decode.field "source" Decode.string)
