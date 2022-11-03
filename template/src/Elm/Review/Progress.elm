module Elm.Review.Progress exposing (Console, appliedFix, clearFixProgress, decoder, dummy, log, timerEnd, timerStart)

import Json.Decode
import Json.Encode as Encode
import Review.Rule as Rule


type Console
    = Console Json.Decode.Value


dummy : Console
dummy =
    Console (Encode.bool True)


decoder : Json.Decode.Decoder Console
decoder =
    Json.Decode.map Console Json.Decode.value


log : Console -> String -> String
log console message =
    message
        |> sendLoggerMessage console
        |> always message


clearFixProgress : Console -> a -> a
clearFixProgress console a =
    logInPipe console [ ( "type", Encode.string "clear-fix-progress" ) ] a


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
logInPipe console fields a =
    fields
        |> Encode.object
        |> Encode.encode 0
        |> sendLoggerMessage console
        |> always a


sendLoggerMessage : Console -> String -> Result Json.Decode.Error ()
sendLoggerMessage (Console hackyJson) message =
    Json.Decode.decodeValue
        (Json.Decode.field message (Json.Decode.null ()))
        hackyJson
