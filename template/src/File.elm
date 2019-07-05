module File exposing
    ( File
    , name, source
    , decode
    )

{-| Represents a file


# Definition

@docs File


# Access

@docs name, source


# Decoding

@decode

-}

import Json.Decode as Decode



-- DEFINITION


type File
    = File
        { name : String
        , source : String
        }



-- ACCESS


name : File -> String
name (File file) =
    file.name


source : File -> String
source (File file) =
    file.source



-- DECODING


decode : Decode.Decoder File
decode =
    Decode.map2 (\name_ source_ -> File { name = name_, source = source_ })
        (Decode.field "name" Decode.string)
        (Decode.field "source" Decode.string)
