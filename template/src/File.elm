module File exposing
    ( File
    , encode, decode
    )

{-| Represents a file


# Definition

@docs File


# Decoding

@docs encode, decode

-}

import Json.Decode as Decode
import Json.Encode as Encode



-- DEFINITION


type alias File =
    { path : String
    , source : String
    }



-- ENCODING / DECODING


decode : Decode.Decoder File
decode =
    Decode.map2 (\path_ source_ -> { path = path_, source = source_ })
        (Decode.field "path" Decode.string)
        (Decode.field "source" Decode.string)


encode : File -> Encode.Value
encode file =
    Encode.object
        [ ( "path", Encode.string file.path )
        , ( "source", Encode.string file.source )
        ]
