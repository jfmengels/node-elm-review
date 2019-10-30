module Elm.Review.File exposing (encode, decode)

{-| TODO file


# Decoding

@docs encode, decode

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Review.File exposing (RawFile)



-- ENCODING / DECODING


decode : Decode.Decoder RawFile
decode =
    Decode.map2 (\path source -> { path = path, source = source })
        (Decode.field "path" Decode.string)
        (Decode.field "source" Decode.string)


encode : { file | path : String, source : String } -> Encode.Value
encode file =
    Encode.object
        [ ( "path", Encode.string file.path )
        , ( "source", Encode.string file.source )
        ]
