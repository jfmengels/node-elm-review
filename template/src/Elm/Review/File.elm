module Elm.Review.File exposing (encode, decode)

{-| TODO file


# Decoding

@docs encode, decode

-}

import Elm.Syntax.File
import Json.Decode as Decode
import Json.Encode as Encode
import Review.File exposing (RawFile)



-- ENCODING / DECODING


decode : Decode.Decoder RawFile
decode =
    Decode.map3 (\path source ast -> { path = path, source = source, ast = ast })
        (Decode.field "path" Decode.string)
        (Decode.field "source" Decode.string)
        (Decode.oneOf
            [ Decode.field "ast" (Elm.Syntax.File.decoder |> Decode.map Just)
            , Decode.succeed Nothing
            ]
        )


encode : { file | path : String, source : String } -> Encode.Value
encode file =
    Encode.object
        [ ( "path", Encode.string file.path )
        , ( "source", Encode.string file.source )
        ]
