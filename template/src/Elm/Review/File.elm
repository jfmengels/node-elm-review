module Elm.Review.File exposing (decode)

{-| Represents an Elm file.


# Decoding

@docs decode

-}

import Elm.Review.AstCodec as AstCodec
import Elm.Syntax.File
import Json.Decode as Decode



-- ENCODING / DECODING


decode : Decode.Decoder { path : String, source : String, ast : Maybe Elm.Syntax.File.File }
decode =
    Decode.map3 (\path source ast -> { path = path, source = source, ast = ast })
        (Decode.field "path" Decode.string)
        (Decode.field "source" Decode.string)
        (Decode.oneOf
            [ Decode.field "ast" (AstCodec.decode |> Decode.map Just)
            , Decode.succeed Nothing
            ]
        )
