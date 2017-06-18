module Reporter.CliReporter exposing (formatReport)

import Lint exposing (countErrors)
import Lint.Types exposing (File, LintRule, LintError, Reporter, Severity(..))


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
formatReportForFile ( { filename }, errors ) =
    let
        formattedErrors =
            List.map
                (\( severity, { rule, message } ) ->
                    String.pad maxSeverityLength ' ' (formatSeverity severity) ++ " " ++ rule ++ ": " ++ message
                )
                errors
    in
        (toString (List.length errors))
            ++ " errors found in '"
            ++ filename
            ++ "':\n\n\t"
            ++ (String.join "\n\t" formattedErrors)


summary : List ( File, List ( Severity, LintError ) ) -> String
summary errors =
    let
        criticalCount =
            countErrors Critical errors

        warningCount =
            countErrors Warning errors

        criticalMessage =
            if criticalCount == 0 then
                ""
            else
                toString criticalCount ++ " critical problem(s)"

        warningMessage =
            if warningCount == 0 then
                ""
            else
                toString warningCount ++ " warning(s)"

        tallyMessage =
            [ criticalMessage, warningMessage ]
                |> List.filter ((/=) "")
                |> String.join ", "
    in
        tallyMessage ++ "."


formatReport : Reporter String
formatReport errors =
    case List.isEmpty errors of
        True ->
            "No linting errors."

        False ->
            let
                fileReports =
                    errors
                        |> List.map formatReportForFile
                        |> String.join "\n\n"
            in
                fileReports ++ "\n\n" ++ (summary errors)
