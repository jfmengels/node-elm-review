module Elm.Review.Flags exposing (FixMode(..), Flags, ReportMode(..), decoder, default)

import Elm.Review.CliCommunication as CliCommunication
import Elm.Review.FixExplanation as FixExplanation exposing (FixExplanation)
import Elm.Review.Reporter as Reporter
import Elm.Review.UnsuppressMode as UnsuppressMode exposing (UnsuppressMode)
import Json.Decode as Decode
import Set exposing (Set)


type alias Flags =
    { fixMode : FixMode
    , fixLimit : Maybe Int
    , fixExplanation : FixExplanation
    , enableExtract : Bool
    , unsuppressMode : UnsuppressMode
    , detailsMode : Reporter.DetailsMode
    , reportMode : ReportMode
    , ignoreProblematicDependencies : Bool
    , rulesFilter : Maybe (Set String)
    , ignoredDirs : List String
    , ignoredFiles : List String
    , writeSuppressionFiles : Bool
    , logger : CliCommunication.Key
    , suppress : Bool
    , watch : Bool
    , supportsColor : Bool
    , debug : Bool
    }


type FixMode
    = Mode_DontFix
    | Mode_Fix Bool
    | Mode_FixAll Bool


type ReportMode
    = HumanReadable
    | Json


decoder : Decode.Decoder Flags
decoder =
    Decode.succeed toDecodedFlags
        |> field "fixMode" decodeFix
        |> field "fixLimit" decodeFixLimit
        |> field "fileRemovalFixesEnabled" Decode.bool
        |> field "explainFixFailure" Decode.bool
        |> field "enableExtract" Decode.bool
        |> field "unsuppress" UnsuppressMode.decoder
        |> field "detailsMode" decodeDetailsMode
        |> field "report" decodeReportMode
        |> field "ignoreProblematicDependencies" Decode.bool
        |> field "rulesFilter" decodeRulesFilter
        |> field "ignoredDirs" (Decode.list Decode.string)
        |> field "ignoredFiles" (Decode.list Decode.string)
        |> field "writeSuppressionFiles" Decode.bool
        |> field "logger" CliCommunication.decoder
        |> field "suppress" Decode.bool
        |> field "watch" Decode.bool
        |> field "color" Decode.bool
        |> field "debug" Decode.bool


toDecodedFlags :
    (Bool -> FixMode)
    -> Maybe Int
    -> Bool
    -> Bool
    -> Bool
    -> UnsuppressMode
    -> Reporter.DetailsMode
    -> ReportMode
    -> Bool
    -> Maybe (Set String)
    -> List String
    -> List String
    -> Bool
    -> CliCommunication.Key
    -> Bool
    -> Bool
    -> Bool
    -> Bool
    -> Flags
toDecodedFlags fixMode fixLimit fileRemovalFixesEnabled explainFixFailure enableExtract unsuppressMode detailsMode reportMode ignoreProblematicDependencies rulesFilter ignoredDirs ignoredFiles writeSuppressionFiles logger suppress watch supportsColor debug =
    { fixMode = fixMode fileRemovalFixesEnabled
    , fixLimit = fixLimit
    , fixExplanation =
        if explainFixFailure then
            FixExplanation.Detailed

        else
            FixExplanation.Succinct
    , enableExtract = enableExtract
    , unsuppressMode = unsuppressMode
    , detailsMode = detailsMode
    , reportMode = reportMode
    , ignoreProblematicDependencies = ignoreProblematicDependencies
    , rulesFilter = rulesFilter
    , ignoredDirs = ignoredDirs
    , ignoredFiles = ignoredFiles
    , writeSuppressionFiles = writeSuppressionFiles
    , logger = logger
    , suppress = suppress
    , watch = watch
    , supportsColor = supportsColor
    , debug = debug
    }


default : Flags
default =
    { fixMode = Mode_DontFix
    , fixLimit = Nothing
    , enableExtract = False
    , fixExplanation = FixExplanation.Succinct
    , unsuppressMode = UnsuppressMode.UnsuppressNone
    , reportMode = HumanReadable
    , detailsMode = Reporter.WithDetails
    , ignoreProblematicDependencies = False
    , rulesFilter = Nothing
    , ignoredDirs = []
    , ignoredFiles = []
    , writeSuppressionFiles = False
    , logger = CliCommunication.dummy
    , suppress = False
    , watch = False
    , supportsColor = True
    , debug = False
    }


field : String -> Decode.Decoder a -> Decode.Decoder (a -> b) -> Decode.Decoder b
field key valDecoder decoder_ =
    Decode.map2
        (|>)
        (Decode.field key valDecoder)
        decoder_


decodeFix : Decode.Decoder (Bool -> FixMode)
decodeFix =
    Decode.string
        |> Decode.andThen
            (\fixMode ->
                case fixMode of
                    "dontfix" ->
                        Decode.succeed (always Mode_DontFix)

                    "fix" ->
                        Decode.succeed Mode_Fix

                    "fixAll" ->
                        Decode.succeed Mode_FixAll

                    _ ->
                        Decode.fail <| "I could not understand the following fix mode: " ++ fixMode
            )


decodeFixLimit : Decode.Decoder (Maybe Int)
decodeFixLimit =
    Decode.oneOf
        [ Decode.int
            |> Decode.map (\n -> Just (max 1 n))
        , Decode.null Nothing
        ]


decodeDetailsMode : Decode.Decoder Reporter.DetailsMode
decodeDetailsMode =
    Decode.string
        |> Decode.andThen
            (\detailsMode ->
                case detailsMode of
                    "with-details" ->
                        Decode.succeed Reporter.WithDetails

                    "without-details" ->
                        Decode.succeed Reporter.WithoutDetails

                    _ ->
                        Decode.fail <| "I could not understand the following details mode: " ++ detailsMode
            )


decodeReportMode : Decode.Decoder ReportMode
decodeReportMode =
    Decode.string
        |> Decode.andThen
            (\reportMode ->
                case reportMode of
                    "human" ->
                        Decode.succeed HumanReadable

                    "json" ->
                        Decode.succeed Json

                    _ ->
                        Decode.fail <| "I could not understand the following report mode: " ++ reportMode
            )


decodeRulesFilter : Decode.Decoder (Maybe (Set String))
decodeRulesFilter =
    Decode.oneOf
        [ Decode.list Decode.string
            |> Decode.map (Set.fromList >> Just)
        , Decode.null Nothing
        ]
