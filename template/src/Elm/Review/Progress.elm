module Elm.Review.Progress exposing (Console, decoder, dummy, fixWasApplied, reset, log)

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
    let
        message : String
        message =
            Json.Encode.object
                [ ( "type", Json.Encode.string "reset" )
                ]
                |> Json.Encode.encode 0
    in
    always (Console 0 console) <|
        sendLoggerMessage message console


decoder : Json.Decode.Decoder Console
decoder =
    Json.Decode.map (Console 0) Json.Decode.value


fixWasApplied : List Rule.ReviewError -> Console -> Console
fixWasApplied remainingErrors (Console previousCount console) =
    let
        count : Int
        count =
            previousCount + 1

        remainingFixableErrors : Int
        remainingFixableErrors =
            remainingErrors
                |> List.filterMap Rule.errorFixes
                |> List.length

        message : String
        message =
            Json.Encode.object
                [ ( "type", Json.Encode.string "log" )
                , ( "done", Json.Encode.int count )
                , ( "remaining", Json.Encode.int remainingFixableErrors )
                ]
                |> Json.Encode.encode 0
    in
    if count >= 3 then
        always (Console count console) <|
            sendLoggerMessage message console

    else
        Console count console


log : Console -> String -> String
log (Console _ console) message =
    always message <|
        sendLoggerMessage message console


sendLoggerMessage : String -> Json.Decode.Value -> Result Json.Decode.Error ()
sendLoggerMessage message console =
    Json.Decode.decodeValue
        (Json.Decode.field message (Json.Decode.null ()))
        console
