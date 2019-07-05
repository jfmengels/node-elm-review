module Reporter.CliReporter exposing (formatReport)

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


formatReportForFile : ( File, List ( Severity, LintError ) ) -> String
formatReportForFile ( file, errors ) =
    let
        formattedErrors : List String
        formattedErrors =
            List.map
                (\( severity, { ruleName, message } ) ->
                    String.pad maxSeverityLength ' ' (formatSeverity severity) ++ " " ++ ruleName ++ ": " ++ message
                )
                errors
    in
    File.name file
        ++ " - "
        ++ String.fromInt (List.length errors)
        ++ " error(s):\n\n\t"
        ++ String.join "\n\t" formattedErrors


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
                        |> List.map formatReportForFile
                        |> String.join "\n\n\n\n"
            in
            fileReports ++ "\n\n\n\n" ++ summary errors
