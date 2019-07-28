module Reporter exposing (formatReport)

import Array exposing (Array)
import Elm.Syntax.Range exposing (Range)
import File exposing (File)
import Lint exposing (LintError)
import List.Extra
import Text exposing (Text)


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
            (prefix ++ String.padLeft (80 - String.length prefix) '-' (" " ++ File.name file))
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
formatErrorWithExtract file { ruleName, message, details, range } =
    let
        title : List Text
        title =
            [ Text.from ruleName
                |> Text.inRed
            , Text.from <| ": " ++ message
            ]

        codeExtract_ : List Text
        codeExtract_ =
            codeExtract file range

        details_ : List Text
        details_ =
            List.map Text.from details
                |> List.intersperse (Text.from "\n\n")
    in
    [ title, codeExtract_, details_ ]
        |> List.filter (List.isEmpty >> not)
        |> List.intersperse [ Text.from "\n\n" ]
        |> List.concat


codeExtract : File -> Range -> List Text
codeExtract file =
    let
        getRowAtLine_ : Int -> String
        getRowAtLine_ =
            getRowAtLine file
    in
    \({ start, end } as range) ->
        if range.start == range.end then
            []

        else if start.row == end.row then
            [ Text.from <| getRowAtLine_ (start.row - 2)
            , Text.from <| getRowAtLine_ (start.row - 1)
            , underlineError (start.row - 1) { start = start.column, end = end.column }
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
                  , underlineError
                        (start.row - 1)
                        { start = start.column
                        , end = String.length startLine - offsetBecauseOfLineNumber (start.row - 1)
                        }
                  ]
                , linesBetweenStartAndEnd
                    |> List.indexedMap Tuple.pair
                    |> List.concatMap
                        (\( lineNumber, line ) ->
                            [ Text.from <| line
                            , underlineError
                                lineNumber
                                { start = getIndexOfFirstNonSpace (offsetBecauseOfLineNumber lineNumber) line
                                , end = String.length line - offsetBecauseOfLineNumber lineNumber
                                }
                            ]
                        )
                , [ Text.from <| endLine
                  , underlineError
                        (end.row - 1)
                        { start = getIndexOfFirstNonSpace (offsetBecauseOfLineNumber (end.row - 1)) endLine
                        , end = String.length endLine - offsetBecauseOfLineNumber (end.row - 1)
                        }
                  , Text.from <| getRowAtLine_ end.row
                  ]
                ]


getIndexOfFirstNonSpace : Int -> String -> Int
getIndexOfFirstNonSpace offset string =
    string
        |> String.indexes (String.trim <| String.dropLeft offset string)
        |> List.head
        |> Maybe.withDefault 0
        |> (\n -> n - offset + 1)


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
underlineError lineNumber { start, end } =
    let
        baseText : String
        baseText =
            String.repeat (offsetBecauseOfLineNumber lineNumber + start - 1) " " ++ String.repeat (end - start) "^" ++ "\n"
    in
    baseText
        |> Text.from
        |> Text.inRed


offsetBecauseOfLineNumber : Int -> Int
offsetBecauseOfLineNumber lineNumber =
    lineNumber
        |> String.fromInt
        |> String.length
        |> (+) 2


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


formatReport : List ( File, List LintError ) -> List Text
formatReport errors =
    case List.isEmpty errors of
        True ->
            [ Text.from "I found no linting errors.\nYou're all good!" ]

        False ->
            List.concat
                [ formatReports errors
                , [ Text.from <| "\n\n\n\n" ++ summary errors ]
                ]


formatReports : List ( File, List LintError ) -> List Text
formatReports errors =
    case errors of
        [] ->
            []

        [ error ] ->
            formatReportForFileWithExtract error

        (( fileA, error ) as a) :: (( fileB, _ ) as b) :: restOfErrors ->
            List.concat
                [ formatReportForFileWithExtract a
                , [ fileSeparator fileA fileB ]
                , formatReports (b :: restOfErrors)
                ]


fileSeparator : File -> File -> Text
fileSeparator file1 file2 =
    let
        str : String
        str =
            "\n\n"
                ++ String.padLeft 80 ' ' (File.name file1 ++ "  ↑    ")
                ++ "\n====o======================================================================o===="
                ++ "\n    ↓  "
                ++ File.name file2
                ++ "\n\n\n"
    in
    Text.from str
        |> Text.inRed
