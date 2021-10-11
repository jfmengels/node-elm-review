module Elm.Review.SuppressedErrors exposing (SuppressedErrors, apply, decoder, fromReviewErrors)

import Dict exposing (Dict)
import Elm.Review.Vendor.List.Extra as ListExtra
import Json.Decode as Decode
import Review.Rule as Rule


type alias SuppressedErrors =
    Dict ( String, String ) Int


fromReviewErrors : List Rule.ReviewError -> SuppressedErrors
fromReviewErrors reviewErrors =
    List.foldl
        (\error acc ->
            Dict.update
                ( Rule.errorRuleName error, Rule.errorFilePath error )
                (Maybe.withDefault 0 >> (+) 1 >> Just)
                acc
        )
        Dict.empty
        reviewErrors


apply : SuppressedErrors -> List Rule.ReviewError -> List Rule.ReviewError
apply suppressedErrors errors =
    errors
        |> ListExtra.gatherWith (\a b -> (Rule.errorFilePath a == Rule.errorFilePath b) && (Rule.errorRuleName a == Rule.errorRuleName b))
        |> List.concatMap
            (\( head, tail ) ->
                case Dict.get ( Rule.errorRuleName head, Rule.errorFilePath head ) suppressedErrors of
                    Just count ->
                        if List.length tail <= count - 1 then
                            []

                        else
                            head :: tail

                    Nothing ->
                        head :: tail
            )



-- DECODER


decoder : Decode.Decoder SuppressedErrors
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
