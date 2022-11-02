module Elm.Review.Progress exposing (Console, decoder, dummy, log, logInPipe, reset)

import Json.Decode
import Json.Encode
import Review.Rule as Rule


type Console
    = Console Json.Decode.Value


dummy : Console
dummy =
    Console (Json.Encode.bool True)


reset : Console -> Console
reset (Console console) =
    let
        message : String
        message =
            Json.Encode.object
                [ ( "type", Json.Encode.string "reset" )
                ]
                |> Json.Encode.encode 0
    in
    always (Console console) <|
        sendLoggerMessage message console


decoder : Json.Decode.Decoder Console
decoder =
    Json.Decode.map Console Json.Decode.value


log : Console -> String -> String
log (Console console) message =
    always message <|
        sendLoggerMessage message console


logInPipe : Console -> List ( String, Json.Decode.Value ) -> a -> a
logInPipe (Console console) message data =
    always data <|
        sendLoggerMessage (Json.Encode.encode 0 (Json.Encode.object message)) console


sendLoggerMessage : String -> Json.Decode.Value -> Result Json.Decode.Error ()
sendLoggerMessage message console =
    Json.Decode.decodeValue
        (Json.Decode.field message (Json.Decode.null ()))
        console
