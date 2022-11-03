module Elm.Review.Progress exposing (Console, appliedFix, clearFixProgress, decoder, dummy, log, timerEnd, timerStart)

import Json.Decode
import Json.Encode as Encode
import Review.Rule as Rule


type Console
    = Console Json.Decode.Value


dummy : Console
dummy =
    Console (Encode.bool True)


clearFixProgress : Console -> a -> a
clearFixProgress console a =
    logInPipe console [ ( "type", Encode.string "clear-fix-progress" ) ] a


decoder : Json.Decode.Decoder Console
decoder =
    Json.Decode.map Console Json.Decode.value


log : Console -> String -> String
log (Console console) message =
    always message <|
        sendLoggerMessage message console


timerStart : Console -> String -> a -> a
timerStart console metric a =
    logInPipe console [ ( "type", Encode.string "timer-start" ), ( "metric", Encode.string metric ) ] a


timerEnd : Console -> String -> a -> a
timerEnd console metric a =
    logInPipe console [ ( "type", Encode.string "timer-end" ), ( "metric", Encode.string metric ) ] a


appliedFix : Console -> Int -> Rule.ReviewError -> Rule.ReviewError
appliedFix console errorCount error =
    logInPipe
        console
        [ ( "type", Encode.string "apply-fix" )
        , ( "ruleName", Encode.string (Rule.errorRuleName error) )
        , ( "filePath", Encode.string (Rule.errorFilePath error) )
        , ( "count", Encode.int errorCount )
        ]
        error


logInPipe : Console -> List ( String, Json.Decode.Value ) -> a -> a
logInPipe (Console console) message data =
    always data <|
        sendLoggerMessage (Encode.encode 0 (Encode.object message)) console


sendLoggerMessage : String -> Json.Decode.Value -> Result Json.Decode.Error ()
sendLoggerMessage message console =
    Json.Decode.decodeValue
        (Json.Decode.field message (Json.Decode.null ()))
        console
