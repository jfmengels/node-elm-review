module Elm.Review.SuppressedErrors exposing (SuppressedErrors, apply, count, decoder, empty, encode, fromReviewErrors, member)

import Dict exposing (Dict)
import Elm.Review.Vendor.List.Extra as ListExtra
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Review.Rule as Rule


type SuppressedErrors
    = SuppressedErrors (Dict ( String, String ) Int)


empty : SuppressedErrors
empty =
    SuppressedErrors Dict.empty


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
        |> SuppressedErrors


apply : SuppressedErrors -> List Rule.ReviewError -> List Rule.ReviewError
apply (SuppressedErrors suppressedErrors) errors =
    if Dict.isEmpty suppressedErrors then
        errors

    else
        applyHelp suppressedErrors errors


applyHelp : Dict ( String, String ) Int -> List Rule.ReviewError -> List Rule.ReviewError
applyHelp suppressedErrors errors =
    errors
        |> ListExtra.gatherWith (\a b -> (Rule.errorFilePath a == Rule.errorFilePath b) && (Rule.errorRuleName a == Rule.errorRuleName b))
        |> List.concatMap
            (\( head, tail ) ->
                case Dict.get ( Rule.errorRuleName head, Rule.errorFilePath head ) suppressedErrors of
                    Just nbSuppressedErrors ->
                        if List.length tail <= nbSuppressedErrors - 1 then
                            []

                        else
                            head :: tail

                    Nothing ->
                        head :: tail
            )


count : SuppressedErrors -> Int
count (SuppressedErrors suppressedErrors) =
    suppressedErrors
        |> Dict.values
        |> List.sum


member : Rule.ReviewError -> SuppressedErrors -> Bool
member error (SuppressedErrors suppressedErrors) =
    Dict.member ( Rule.errorRuleName error, Rule.errorFilePath error ) suppressedErrors



-- DECODER


decoder : Decoder SuppressedErrors
decoder =
    Decode.list suppressedErrorEntryDecoder
        |> Decode.map (List.concat >> Dict.fromList >> SuppressedErrors)


suppressedErrorEntryDecoder : Decoder (List ( ( String, String ), Int ))
suppressedErrorEntryDecoder =
    Decode.map2
        (\rule suppressions ->
            List.map
                (\( filePath, nbSuppressedErrors ) ->
                    ( ( rule, filePath ), nbSuppressedErrors )
                )
                suppressions
        )
        (Decode.field "rule" Decode.string)
        (Decode.field "suppressions" (Decode.list fileEntryDecoder))


fileEntryDecoder : Decoder ( String, Int )
fileEntryDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "filePath" Decode.string)
        (Decode.field "count" Decode.int)



-- ENCODE


encode : List String -> SuppressedErrors -> Encode.Value
encode ruleNames (SuppressedErrors suppressedErrors) =
    suppressedErrors
        |> Dict.toList
        |> List.foldl
            (\( ( ruleName, path ), nbSuppressedErrors ) acc ->
                Dict.update
                    ruleName
                    (Maybe.withDefault [] >> (::) ( nbSuppressedErrors, path ) >> Just)
                    acc
            )
            Dict.empty
        |> Dict.toList
        |> Encode.list
            (\( ruleName, countPerFile ) ->
                encodeRuleSuppression ruleName (encodeFileSuppressions countPerFile)
            )


encodeRuleSuppression : String -> Encode.Value -> Encode.Value
encodeRuleSuppression ruleName fileSuppressions =
    Encode.object
        [ ( "rule", Encode.string ruleName )
        , ( "suppressions", fileSuppressions )
        ]


encodeFileSuppressions : List ( Int, String ) -> Encode.Value
encodeFileSuppressions countPerFile =
    Encode.list encodeFileSuppression countPerFile


encodeFileSuppression : ( Int, String ) -> Encode.Value
encodeFileSuppression ( nbSuppressedErrors, path ) =
    Encode.object
        [ ( "count", Encode.int nbSuppressedErrors )
        , ( "filePath", Encode.string path )
        ]
