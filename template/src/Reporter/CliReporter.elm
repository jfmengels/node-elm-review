module Reporter.CliReporter exposing (formatReport)

import Array exposing (Array)
import Elm.Syntax.Range exposing (Range)
import File exposing (File)
import Json.Encode as Encode
import Lint exposing (LintError, Severity(..), lintSource)
import Lint.Rule exposing (Rule)
import Reporter.Text as Text exposing (Text)


formatSeverity : Severity -> String
formatSeverity severity =
    case severity of
        Disabled ->
            "(Disabled)"

        Warning ->
            "(Warning) "

        Critical ->
            "(Critical)"


maxSeverityLength : Int
maxSeverityLength =
    [ Disabled, Warning, Critical ]
        |> List.map (formatSeverity >> String.length)
        |> List.maximum
        |> Maybe.withDefault 0


formatReportForFileShort : ( File, List ( Severity, LintError ) ) -> String
formatReportForFileShort ( file, errors ) =
    let
        formattedErrors : List String
        formattedErrors =
            List.map (formatErrorShort file) errors
    in
    File.name file
        ++ " - "
        ++ String.fromInt (List.length errors)
        ++ " error(s):\n\n\t"
        ++ String.join "\n\t" formattedErrors


formatReportForFileWithExtract : ( File, List ( Severity, LintError ) ) -> List Text
formatReportForFileWithExtract ( file, errors ) =
    let
        formattedErrors : List (List Text)
        formattedErrors =
            List.map (formatErrorWithExtract file) errors

        header : Text
        header =
            Text.from ("-- LINTING ERROR ----------------------------------- " ++ File.name file ++ "\n\n")
                |> Text.inGreen
    in
    header :: Text.join "\n\n\n" formattedErrors


formatErrorShort : File -> ( Severity, LintError ) -> String
formatErrorShort file ( severity, { ruleName, message, range } ) =
    String.pad maxSeverityLength ' ' (formatSeverity severity)
        ++ " "
        ++ ruleName
        ++ ": "
        ++ message


formatErrorWithExtract : File -> ( Severity, LintError ) -> List Text
formatErrorWithExtract file ( severity, { ruleName, message, range } ) =
    List.concat
        [ getCodeAtLocationInSourceCode file range
        , [ Text.from "\n" ]
        , [ Text.from <| formatSeverity severity ]
        , [ Text.from <| " " ++ ruleName ++ ": " ++ message ]
        ]


getCodeAtLocationInSourceCode : File -> Range -> List Text
getCodeAtLocationInSourceCode file =
    let
        getRowAtLine_ : Int -> String
        getRowAtLine_ =
            getRowAtLine file
    in
    \({ start, end } as range) ->
        if start.row == end.row then
            List.concat
                [ [ Text.from <| getRowAtLine_ (start.row - 2) ]
                , [ Text.from <| getRowAtLine_ (start.row - 1) ]
                , underlineError range
                , [ Text.from <| getRowAtLine_ end.row ]
                ]

        else
            [ Text.from "TODO multiline support" ]


getRowAtLine : File -> Int -> String
getRowAtLine file =
    let
        lines : Array String
        lines =
            file
                |> File.source
                |> String.lines
                |> Array.fromList
    in
    \rowIndex ->
        case Array.get rowIndex lines of
            Just line ->
                if String.trim line /= "" then
                    String.fromInt rowIndex ++ "| " ++ line ++ "\n"

                else
                    ""

            Nothing ->
                ""


underlineError : Range -> List Text
underlineError { start, end } =
    let
        offsetBecauseOfLineNumber : Int
        offsetBecauseOfLineNumber =
            (end.row + 1)
                |> String.fromInt
                |> String.length
                |> (+) 2
    in
    [ Text.from <| String.repeat (offsetBecauseOfLineNumber + start.column - 1) " "
    , String.repeat (end.column - start.column) "^"
        |> Text.from
        |> Text.inRed
    , Text.from "\n"
    ]


summary : List ( File, List ( Severity, LintError ) ) -> String
summary errors =
    let
        allErrors : List ( Severity, LintError )
        allErrors =
            List.concatMap Tuple.second errors

        criticalCount : Int
        criticalCount =
            allErrors
                |> List.filter (Tuple.first >> (==) Critical)
                |> List.length

        warningCount : Int
        warningCount =
            allErrors
                |> List.filter (Tuple.first >> (==) Warning)
                |> List.length

        criticalMessage : String
        criticalMessage =
            if criticalCount == 0 then
                ""

            else
                String.fromInt criticalCount ++ " critical problem(s)"

        warningMessage : String
        warningMessage =
            if warningCount == 0 then
                ""

            else
                String.fromInt warningCount ++ " warning(s)"

        tallyMessage : String
        tallyMessage =
            [ criticalMessage, warningMessage ]
                |> List.filter ((/=) "")
                |> String.join ", "
    in
    tallyMessage ++ "."


formatReport : List ( File, List ( Severity, LintError ) ) -> Encode.Value
formatReport errors =
    case List.isEmpty errors of
        True ->
            [ Text.from "I found no linting errors.\nYou're all good!" ]
                |> Text.encode

        False ->
            let
                fileReports : List Text
                fileReports =
                    errors
                        |> List.map formatReportForFileWithExtract
                        |> Text.join "\n\n\n\n"
            in
            [ fileReports
            , [ Text.from "\n\n\n\n" ]
            , [ Text.from <| summary errors ]
            ]
                |> List.concat
                |> Text.encode
