module Reporter.CliReporter exposing (formatReport)

import Array exposing (Array)
import Elm.Syntax.Range exposing (Range)
import File exposing (File)
import Lint exposing (LintError, Severity(..), lintSource)
import Lint.Rule exposing (Rule)


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


formatReportForFileWithExtract : ( File, List ( Severity, LintError ) ) -> String
formatReportForFileWithExtract ( file, errors ) =
    let
        formattedErrors : List String
        formattedErrors =
            List.map (formatErrorWithExtract file) errors
    in
    ("-- LINTING ERROR ----------------------------------- " ++ File.name file ++ "\n\n")
        ++ String.join "\n\n\n" formattedErrors


formatErrorShort : File -> ( Severity, LintError ) -> String
formatErrorShort file ( severity, { ruleName, message, range } ) =
    String.pad maxSeverityLength ' ' (formatSeverity severity)
        ++ " "
        ++ ruleName
        ++ ": "
        ++ message


formatErrorWithExtract : File -> ( Severity, LintError ) -> String
formatErrorWithExtract file ( severity, { ruleName, message, range } ) =
    getCodeAtLocationInSourceCode file range
        ++ ("\n" ++ formatSeverity severity ++ " " ++ ruleName ++ ": " ++ message)


getCodeAtLocationInSourceCode : File -> Range -> String
getCodeAtLocationInSourceCode file =
    let
        getRowAtLine_ : Int -> String
        getRowAtLine_ =
            getRowAtLine file
    in
    \({ start, end } as range) ->
        if start.row == end.row then
            getRowAtLine_ (start.row - 2)
                ++ getRowAtLine_ (start.row - 1)
                ++ underlineError range
                ++ getRowAtLine_ end.row

        else
            "TODO multiline support"


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


underlineError : Range -> String
underlineError { start, end } =
    let
        offsetBecauseOfLineNumber : Int
        offsetBecauseOfLineNumber =
            (end.row + 1)
                |> String.fromInt
                |> String.length
                |> (+) 2
    in
    String.repeat (offsetBecauseOfLineNumber + start.column - 1) " "
        ++ String.repeat (end.column - start.column) "^"
        ++ "\n"


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


formatReport : List ( File, List ( Severity, LintError ) ) -> String
formatReport errors =
    case List.isEmpty errors of
        True ->
            "I found no linting errors.\nYou're all good!"

        False ->
            let
                fileReports : String
                fileReports =
                    errors
                        |> List.map formatReportForFileWithExtract
                        |> String.join "\n\n\n\n"
            in
            fileReports ++ "\n\n\n\n" ++ summary errors
