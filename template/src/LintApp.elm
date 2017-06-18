port module LintApp exposing (..)

import Reporter.CliReporter
import Json.Decode
import Lint exposing (countErrors, lintSource)
import Lint.Types exposing (File, LintRule, LintError, Severity(..))
import LintConfig exposing (config)


port linting : (List File -> msg) -> Sub msg


port resultPort : { success : Bool, report : String } -> Cmd msg


type alias Model =
    {}


type Msg
    = Lint (List File)


enabledRules : List ( Severity, LintRule )
enabledRules =
    config
        |> List.filter (Tuple.first >> (/=) Disabled)


lint : String -> List ( Severity, LintError )
lint source =
    lintSource enabledRules source
        |> (\result ->
                case result of
                    Err errors ->
                        [ ( Critical, { rule = "Parsing error", message = String.join "\n" errors } )
                        ]

                    Ok result ->
                        result
           )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Lint files ->
            let
                errors =
                    files
                        |> List.map (\file -> ( file, lint file.source ))
                        |> List.filter
                            (Tuple.second >> List.isEmpty >> not)

                success =
                    countErrors Critical errors == 0

                report =
                    Reporter.CliReporter.formatReport errors
            in
                ( model
                , resultPort { success = success, report = report }
                )


subscriptions : Model -> Sub Msg
subscriptions model =
    linting Lint


main : Program Never Model Msg
main =
    Platform.program
        { init = ( Model, Cmd.none )
        , update = update
        , subscriptions = subscriptions
        }
