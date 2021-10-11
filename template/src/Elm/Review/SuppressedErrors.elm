module Elm.Review.SuppressedErrors exposing (SuppressedErrorsDict, decoder)

import Dict exposing (Dict)
import Json.Decode as Decode


type alias SuppressedErrorsDict =
    Dict ( String, String ) Int


decoder : Decode.Decoder SuppressedErrorsDict
decoder =
    Decode.list suppressedErrorEntryDecoder
        |> Decode.map (List.concat >> Dict.fromList)


suppressedErrorEntryDecoder : Decode.Decoder (List ( ( String, String ), Int ))
suppressedErrorEntryDecoder =
    Decode.map2
        (\rule suppressions ->
            List.map
                (\( filePath, count ) ->
                    ( ( rule, filePath ), count )
                )
                suppressions
        )
        (Decode.field "rule" Decode.string)
        (Decode.field "suppressions" (Decode.list fileEntryDecoder))


fileEntryDecoder : Decode.Decoder ( String, Int )
fileEntryDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "filePath" Decode.string)
        (Decode.field "count" Decode.int)
