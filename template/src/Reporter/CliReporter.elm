module Reporter.CliReporter exposing (formatReport)

import Array exposing (Array)
import Elm.Syntax.Range exposing (Range)
import File exposing (File)
import Json.Encode as Encode
import Lint exposing (LintError, lintSource)
import Lint.Rule exposing (Rule)
import Reporter.Text as Text exposing (Text)


formatReportForFileShort : ( File, List LintError ) -> List Text
formatReportForFileShort ( file, errors ) =
    let
        formattedErrors : List (List Text)
        formattedErrors =
            List.map (formatErrorShort file) errors
    in
    List.concatMap identity
        [ [ Text.from <| File.name file ++ " - " ++ String.fromInt (List.length errors) ++ " error(s):\n\n\t" ]
        , Text.join "\n\t" formattedErrors
        ]


formatReportForFileWithExtract : ( File, List LintError ) -> List Text
formatReportForFileWithExtract ( file, errors ) =
    let
        formattedErrors : List (List Text)
        formattedErrors =
            List.map (formatErrorWithExtract file) errors

        prefix : String
        prefix =
            "-- ELM-LINT ERROR "

        header : Text
        header =
            (prefix ++ String.padLeft (80 - String.length prefix) '-' (File.name file))
                |> Text.from
                |> Text.inGreen
    in
    header :: Text.from "\n\n" :: Text.join "\n\n\n" formattedErrors


formatErrorShort : File -> LintError -> List Text
formatErrorShort file { ruleName, message, range } =
    [ Text.from ("    " ++ ruleName)
        |> Text.inRed
    , Text.from <| ": " ++ message
    ]


formatErrorWithExtract : File -> LintError -> List Text
formatErrorWithExtract file { ruleName, message, range } =
    List.concat
        [ getCodeAtLocationInSourceCode file range
        , [ Text.from ("\n    " ++ ruleName)
                |> Text.inRed
          , Text.from <| ": " ++ message
          ]
        ]


getCodeAtLocationInSourceCode : File -> Range -> List Text
getCodeAtLocationInSourceCode file =
    let
        getRowAtLine_ : Int -> String
        getRowAtLine_ =
            getRowAtLine file
    in
    \({ start, end } as range) ->
        let
            offsetBecauseOfLineNumber : Int
            offsetBecauseOfLineNumber =
                (end.row + 1)
                    |> String.fromInt
                    |> String.length
                    |> (+) 2

            underlineError_ : { start : Int, end : Int } -> Text
            underlineError_ =
                underlineError offsetBecauseOfLineNumber
        in
        if start.row == end.row then
            [ Text.from <| getRowAtLine_ (start.row - 2)
            , Text.from <| getRowAtLine_ (start.row - 1)
            , underlineError_ { start = start.column, end = end.column }
            , Text.from <| getRowAtLine_ end.row
            ]

        else
            let
                startLine : String
                startLine =
                    getRowAtLine_ (start.row - 1)

                linesBetweenStartAndEnd : List String
                linesBetweenStartAndEnd =
                    List.range start.row (end.row - 2)
                        |> List.map getRowAtLine_

                endLine : String
                endLine =
                    getRowAtLine_ (end.row - 1)
            in
            List.concat
                [ [ Text.from <| getRowAtLine_ (start.row - 2)
                  , Text.from <| startLine
                  , underlineError_
                        { start = start.column
                        , end = String.length startLine - offsetBecauseOfLineNumber
                        }
                  ]
                , linesBetweenStartAndEnd
                    |> List.concatMap
                        (\line ->
                            [ Text.from <| line
                            , underlineError_
                                { start = getIndexOfFirstNonSpace offsetBecauseOfLineNumber line
                                , end = String.length line - offsetBecauseOfLineNumber
                                }
                            ]
                        )
                , [ Text.from <| endLine
                  , underlineError_
                        { start = getIndexOfFirstNonSpace offsetBecauseOfLineNumber endLine
                        , end = String.length endLine - offsetBecauseOfLineNumber
                        }
                  , Text.from <| getRowAtLine_ end.row
                  ]
                ]


getIndexOfFirstNonSpace : Int -> String -> Int
getIndexOfFirstNonSpace offsetBecauseOfLineNumber string =
    string
        |> String.indexes (String.trim <| String.dropLeft offsetBecauseOfLineNumber string)
        |> List.head
        |> Maybe.withDefault 0
        |> (\n -> n - offsetBecauseOfLineNumber + 1)


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
                    String.fromInt (rowIndex + 1) ++ "| " ++ line ++ "\n"

                else
                    ""

            Nothing ->
                ""


underlineError : Int -> { start : Int, end : Int } -> Text
underlineError offsetBecauseOfLineNumber { start, end } =
    let
        baseText : String
        baseText =
            String.repeat (offsetBecauseOfLineNumber + start - 1) " " ++ String.repeat (end - start) "^" ++ "\n"
    in
    baseText
        |> Text.from
        |> Text.inRed


summary : List ( File, List LintError ) -> String
summary errors =
    let
        errorCount : Int
        errorCount =
            errors
                |> List.concatMap Tuple.second
                |> List.length
    in
    if errorCount == 0 then
        ""

    else
        String.fromInt errorCount ++ " problem(s)."


formatReport : List ( File, List LintError ) -> Encode.Value
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
