module InteropDefinitions exposing (Flags, FromElm(..), ToElm, interop)

import Json.Decode as JD
import Json.Encode as JE
import TsInterop.Decode as Decode exposing (Decoder)
import TsInterop.Encode as Encoder exposing (Encoder, optional, required)


interop : { toElm : Decoder ToElm, fromElm : Encoder FromElm, flags : Decode.Decoder Flags }
interop =
    { toElm = Decode.null ()
    , fromElm = fromElm
    , flags = Decode.null ()
    }


type FromElm
    = SendPresenceHeartbeat
    | Alert String
    | SomethingBlue


type alias ToElm =
    ()


type alias Flags =
    ()


fromElm : Encoder.Encoder FromElm
fromElm =
    Encoder.union
        (\vSendHeartbeat vAlert vSomethingBlue value ->
            case value of
                SendPresenceHeartbeat ->
                    vSendHeartbeat

                Alert string ->
                    vAlert string

                SomethingBlue ->
                    vSomethingBlue
        )
        |> Encoder.variant0 "SendPresenceHeartbeat"
        |> Encoder.variantObject "Alert" [ required "message" identity Encoder.string ]
        |> Encoder.variant0 "SomethingBlue"
        |> Encoder.buildUnion
