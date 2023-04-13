module Elm.Review.CliCommunication exposing
    ( Key, decoder, dummy
    , send
    , timerStart, timerEnd
    )

{-| Communicate with the CLI through a proxied JSON (that we get through flags).

This is mostly done to provide feedback to the user like the number of applied fixes.

@docs Key, decoder, dummy

@docs send
@docs timerStart, timerEnd

-}

import Json.Decode
import Json.Encode as Encode


type Key
    = Key Json.Decode.Value


dummy : Key
dummy =
    Key (Encode.bool True)


decoder : Json.Decode.Decoder Key
decoder =
    Json.Decode.map Key Json.Decode.value


send : Key -> List ( String, Json.Decode.Value ) -> List ( String, Json.Decode.Value )
send key =
    \message ->
        message
            |> Encode.object
            |> Encode.encode 0
            |> sendLoggerMessage key
            |> always message


timerStart : Key -> String -> a -> a
timerStart key metric a =
    logInPipe key [ ( "type", Encode.string "timer-start" ), ( "metric", Encode.string metric ) ] a


timerEnd : Key -> String -> a -> a
timerEnd key metric a =
    logInPipe key [ ( "type", Encode.string "timer-end" ), ( "metric", Encode.string metric ) ] a


logInPipe : Key -> List ( String, Json.Decode.Value ) -> a -> a
logInPipe key fields a =
    fields
        |> Encode.object
        |> Encode.encode 0
        |> sendLoggerMessage key
        |> always a


sendLoggerMessage : Key -> String -> Result Json.Decode.Error ()
sendLoggerMessage (Key hackyJson) message =
    Json.Decode.decodeValue
        (Json.Decode.field message (Json.Decode.null ()))
        hackyJson
