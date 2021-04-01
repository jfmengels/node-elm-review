module Elm.Review.Progress exposing (Console, decoder, dummy, fixWasApplied, reset)

import Json.Decode
import Json.Encode
import Review.Rule as Rule


type Console
    = Console Int Json.Decode.Value


dummy : Console
dummy =
    Console 0 (Json.Encode.bool True)


reset : Console -> Console
reset (Console _ console) =
    always (Console 0 console) <|
        Json.Decode.decodeValue
            (Json.Decode.field "reset" (Json.Decode.null ()))
            console


decoder : Json.Decode.Decoder Console
decoder =
    Json.Decode.map (Console 0) Json.Decode.value


fixWasApplied : List Rule.ReviewError -> Console -> Console
fixWasApplied remainingErrors (Console previousCount console) =
    let
        count : Int
        count =
            previousCount + 1

        remainingFixableErrors : String
        remainingFixableErrors =
            remainingErrors
                |> List.filterMap Rule.errorFixes
                |> List.length
                |> String.fromInt
    in
    if count >= 3 then
        always (Console count console) <|
            Json.Decode.decodeValue
                (Json.Decode.field ("log::" ++ String.fromInt count ++ "::" ++ remainingFixableErrors) (Json.Decode.null ()))
                console

    else
        Console count console
