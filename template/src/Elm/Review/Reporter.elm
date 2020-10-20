module Elm.Review.Reporter exposing
    ( Error, File, FilePath(..), Source(..), TextContent
    , Mode(..), DetailsMode(..), formatReport, formatIndividualError
    , formatFixProposal, formatFixProposals
    )

{-| Formats the result of `elm-review` in a nice human-readable way.


# Types

@docs Error, File, FilePath, Source, TextContent


# Report

@docs Mode, DetailsMode, formatReport, formatIndividualError


# Fix

@docs formatFixProposal, formatFixProposals

-}

import Array exposing (Array)
import Elm.Review.Text as Text exposing (Text)
import Elm.Review.Vendor.Diff as Diff


{-| Contents of an error. Convert the errors from
[`Review`](https://package.elm-lang.org/packages/jfmengels/elm-review/1.0.0/Review#Error)
to this type.
-}
type alias Error =
    { ruleName : String
    , ruleLink : Maybe String
    , message : String
    , details : List String
    , range : Range
    , hasFix : Bool
    }


{-| Represents a file.

  - path is the file path
  - source is the raw contents of the file

-}
type alias File =
    { path : FilePath
    , source : Source
    }


type alias FileWithError =
    { path : FilePath
    , source : Source
    , errors : List Error
    }


type FilePath
    = FilePath String


filePath : FilePath -> String
filePath (FilePath str) =
    str


type Source
    = Source String


{-| Represents styled text.

Formatter functions return a list of these, that should be
styled in the viewing medium according to the associated colors and joined
together without spaces.

-}
type alias TextContent =
    Text.TextContent


type alias Range =
    { start :
        { row : Int
        , column : Int
        }
    , end :
        { row : Int
        , column : Int
        }
    }


{-| Mode in which `elm-review` is running.
-}
type Mode
    = Reviewing
    | Fixing


type DetailsMode
    = WithDetails
    | WithoutDetails


{-| Reports the errors reported by `elm-review` in a nice human-readable way.
-}
formatReport : DetailsMode -> Bool -> List FileWithError -> List TextContent
formatReport detailsMode errorsHaveBeenFixedPreviously files =
    let
        numberOfErrors : Int
        numberOfErrors =
            totalNumberOfErrors files

        filesWithErrors : List FileWithError
        filesWithErrors =
            files
                |> List.filter (.errors >> List.isEmpty >> not)
                |> List.sortBy (.path >> filePath)
    in
    if numberOfErrors == 0 then
        if errorsHaveBeenFixedPreviously then
            "I found no more errors!"
                |> Text.from
                |> Text.toRecord
                |> List.singleton

        else
            "I found no errors!"
                |> Text.from
                |> Text.toRecord
                |> List.singleton

    else
        [ formatReports detailsMode filesWithErrors
            |> Just
        , if hasFixableErrors files then
            Just
                [ "Errors marked with (fix) can be fixed automatically using `elm-review --fix`."
                    |> Text.from
                    |> Text.inBlue
                ]

          else
            Nothing
        , [ Text.from "I found "
          , pluralize numberOfErrors "error" |> Text.from |> Text.inRed
          , Text.from " in "
          , pluralize (List.length filesWithErrors) "file" |> Text.from |> Text.inYellow
          , Text.from "."
          ]
            |> Just
        ]
            |> List.filterMap identity
            |> Text.join "\n\n"
            |> Text.simplify
            |> List.map Text.toRecord


pluralize : Int -> String -> String
pluralize n word =
    (String.fromInt n ++ " " ++ word)
        ++ (if n > 1 then
                "s"

            else
                ""
           )


formatReportForFileWithExtract : DetailsMode -> Mode -> FileWithError -> List Text
formatReportForFileWithExtract detailsMode mode file =
    file.errors
        |> List.sortWith compareErrorPositions
        |> List.indexedMap
            (\index error ->
                Text.join "\n\n"
                    [ [ header (index == 0) file.path error.range ]
                    , formatErrorWithExtract detailsMode mode file.source error
                    ]
            )
        |> Text.join "\n\n"


firstErrorPrefix : String
firstErrorPrefix =
    "-- ELM-REVIEW ERROR -"


header : Bool -> FilePath -> Range -> Text
header isFirstError (FilePath filePath_) range =
    let
        position : String
        position =
            " " ++ filePath_ ++ ":" ++ String.fromInt range.start.row ++ ":" ++ String.fromInt range.start.column
    in
    if isFirstError then
        (firstErrorPrefix ++ String.padLeft (80 - String.length firstErrorPrefix) '-' position)
            |> Text.from
            |> Text.inBlue

    else
        ("────" ++ String.padLeft 76 '─' position)
            |> Text.from


formatIndividualError : DetailsMode -> Source -> Error -> List TextContent
formatIndividualError detailsMode source error =
    formatErrorWithExtract detailsMode Reviewing source error
        |> Text.simplify
        |> List.map Text.toRecord


formatErrorWithExtract : DetailsMode -> Mode -> Source -> Error -> List Text
formatErrorWithExtract detailsMode mode source error =
    let
        codeExtract_ : List Text
        codeExtract_ =
            codeExtract source error.range

        details_ : List Text
        details_ =
            case detailsMode of
                WithDetails ->
                    Text.from "\n\n"
                        :: (List.map Text.from error.details
                                |> List.intersperse (Text.from "\n\n")
                           )

                WithoutDetails ->
                    []
    in
    List.concat
        [ formatErrorTitle mode error
        , [ Text.from "\n\n" ]
        , codeExtract_
        , details_
        ]


formatErrorTitle : Mode -> Error -> List Text
formatErrorTitle mode error =
    let
        fixPrefix : Text
        fixPrefix =
            case mode of
                Reviewing ->
                    if error.hasFix then
                        "(fix) "
                            |> Text.from
                            |> Text.inBlue

                    else
                        Text.from ""

                Fixing ->
                    Text.from ""
    in
    [ fixPrefix
    , Text.from error.ruleName
        |> Text.inRed
        |> Text.withLink error.ruleLink
    , Text.from <| ": " ++ error.message
    ]


compareErrorPositions : Error -> Error -> Order
compareErrorPositions a b =
    compareRange a.range b.range


compareRange : Range -> Range -> Order
compareRange a b =
    if a.start.row < b.start.row then
        LT

    else if a.start.row > b.start.row then
        GT

    else
    -- Start row is the same from here on
    if
        a.start.column < b.start.column
    then
        LT

    else if a.start.column > b.start.column then
        GT

    else
    -- Start row and column are the same from here on
    if
        a.end.row < b.end.row
    then
        LT

    else if a.end.row > b.end.row then
        GT

    else
    -- Start row and column, and end row are the same from here on
    if
        a.end.column < b.end.column
    then
        LT

    else if a.end.column > b.end.column then
        GT

    else
        EQ


codeExtract : Source -> Range -> List Text
codeExtract (Source source) =
    let
        lines : Array String
        lines =
            source
                |> String.lines
                |> Array.fromList

        getRowAtLine : Int -> String
        getRowAtLine rowIndex =
            case Array.get rowIndex lines of
                Just line ->
                    String.trimRight line

                Nothing ->
                    ""
    in
    \{ start, end } ->
        let
            maxLineNumber : Int
            maxLineNumber =
                if String.isEmpty (getRowAtLine (end.row + 1)) then
                    end.row

                else
                    end.row + 1

            maxLineNumberLength : Int
            maxLineNumberLength =
                lengthOfLineNumber maxLineNumber

            gutterLength : Int
            gutterLength =
                lineNumberPrefix maxLineNumberLength maxLineNumber |> String.length

            underlineError_ : { start : Int, end : Int } -> List Text
            underlineError_ =
                underlineError gutterLength

            getRowWithLineNumber : Int -> String
            getRowWithLineNumber rowIndex =
                lineNumberPrefix maxLineNumberLength rowIndex ++ getRowAtLine rowIndex

            getRowWithLineNumberUnlessEmpty : Int -> List Text
            getRowWithLineNumberUnlessEmpty rowIndex =
                let
                    line =
                        getRowAtLine rowIndex
                in
                if String.isEmpty line then
                    []

                else
                    [ Text.from (lineNumberPrefix maxLineNumberLength rowIndex ++ line) ]
        in
        if start == end then
            []

        else if start.row == end.row then
            [ getRowWithLineNumberUnlessEmpty (start.row - 2)
            , [ Text.from <| getRowWithLineNumber (start.row - 1) ]
            , underlineError_ { start = start.column, end = end.column }
            , getRowWithLineNumberUnlessEmpty end.row
            ]
                |> List.filter (not << List.isEmpty)
                |> Text.join "\n"

        else
            let
                startLine : Int
                startLine =
                    start.row - 1

                linesBetweenStartAndEnd : List Int
                linesBetweenStartAndEnd =
                    List.range start.row (end.row - 2)

                endLine : Int
                endLine =
                    end.row - 1
            in
            [ getRowWithLineNumberUnlessEmpty (startLine - 1)
            , [ Text.from <| getRowWithLineNumber startLine ]
            , underlineError_
                { start = start.column
                , end = String.length (getRowAtLine startLine) + 1
                }
            , linesBetweenStartAndEnd
                |> List.map
                    (\middleLine ->
                        let
                            line : String
                            line =
                                getRowAtLine middleLine
                        in
                        if String.isEmpty line then
                            [ Text.from (getRowWithLineNumber middleLine) ]

                        else
                            Text.from (getRowWithLineNumber middleLine)
                                :: Text.from "\n"
                                :: underlineError_
                                    { start = getIndexOfFirstNonSpace line + 1
                                    , end = String.length line + 1
                                    }
                    )
                |> Text.join "\n"
            , [ Text.from (getRowWithLineNumber endLine) ]
            , let
                line =
                    getRowAtLine endLine
              in
              underlineError_
                { start = getIndexOfFirstNonSpace line + 1
                , end = String.length line + 1
                }
            , getRowWithLineNumberUnlessEmpty (endLine + 1)
            ]
                |> List.filter (not << List.isEmpty)
                |> Text.join "\n"


getIndexOfFirstNonSpace : String -> Int
getIndexOfFirstNonSpace string =
    String.length string - String.length (String.trimLeft string)


lineNumberPrefix : Int -> Int -> String
lineNumberPrefix maxLineNumberLength rowIndex =
    ((rowIndex + 1)
        |> String.fromInt
        |> String.padLeft maxLineNumberLength ' '
    )
        ++ "| "


lengthOfLineNumber : Int -> Int
lengthOfLineNumber lineNumber =
    lineNumber
        |> String.fromInt
        |> String.length


underlineError : Int -> { start : Int, end : Int } -> List Text
underlineError gutterLength { start, end } =
    [ Text.from <| String.repeat (gutterLength + start - 1) " "
    , String.repeat (end - start) "^"
        |> Text.from
        |> Text.inRed
    ]


offsetBecauseOfLineNumber : Int -> Int
offsetBecauseOfLineNumber lineNumber =
    lineNumber
        |> String.fromInt
        |> String.length
        |> (+) 2
        |> (*) 0


totalNumberOfErrors : List FileWithError -> Int
totalNumberOfErrors files =
    files
        |> List.concatMap .errors
        |> List.length


hasFixableErrors : List FileWithError -> Bool
hasFixableErrors files =
    List.any (.errors >> List.any .hasFix) files


formatReports : DetailsMode -> List FileWithError -> List Text
formatReports detailsMode files =
    case files of
        [] ->
            []

        [ file ] ->
            formatReportForFileWithExtract detailsMode Reviewing file

        firstFile :: secondFile :: restOfFiles ->
            List.concat
                [ formatReportForFileWithExtract detailsMode Reviewing firstFile
                , fileSeparator firstFile.path secondFile.path
                , formatReports detailsMode (secondFile :: restOfFiles)
                ]


fileSeparator : FilePath -> FilePath -> List Text
fileSeparator (FilePath pathAbove) (FilePath pathBelow) =
    [ Text.from <| "\n\n" ++ String.repeat (73 - String.length pathAbove) " "
    , (pathAbove ++ "  ↑")
        ++ "\n====o======================================================================o===="
        ++ "\n    ↓  "
        ++ pathBelow
        |> Text.from
        |> Text.inRed
    , Text.from "\n\n\n"
    ]



-- FIX


{-| Reports a fix proposal for a single errorin a nice human-readable way.
-}
formatFixProposal : DetailsMode -> File -> Error -> Source -> List TextContent
formatFixProposal detailsMode file error fixedSource =
    List.concat
        [ Text.join "\n\n"
            [ formatReportForFileWithExtract detailsMode
                Fixing
                { path = file.path
                , source = file.source
                , errors = [ error ]
                }
            , [ "I think I can fix this. Here is my proposal:"
                    |> Text.from
                    |> Text.inBlue
              ]
            , diff file.source fixedSource
            ]
        , [ Text.from "\n" ]
        ]
        |> List.map Text.toRecord


{-| Reports the proposal for the fix-all changes in a nice human-readable way.
-}
formatFixProposals : List { path : FilePath, source : Source, fixedSource : Source, errors : List Error } -> List TextContent
formatFixProposals changedFiles =
    let
        headerText : String
        headerText =
            "-- ELM-REVIEW FIX-ALL PROPOSAL "

        fixAllHeader : Text
        fixAllHeader =
            headerText
                |> String.padRight 80 '-'
                |> Text.from
                |> Text.inBlue

        filesListing : List Text
        filesListing =
            Text.from "I found fixable errors for the following files:"
                :: List.concatMap
                    (\file ->
                        [ Text.from "\n  "
                        , "- " ++ filePath file.path |> Text.from |> Text.inYellow
                        ]
                    )
                    changedFiles

        body : List Text
        body =
            [ [ fixAllHeader ]
            , filesListing
            , [ Text.from "Here is how the code would change if you applied each fix." ]
            , formatFileDiffs changedFiles
            ]
                |> Text.join "\n\n"
    in
    (body ++ [ Text.from "\n" ])
        |> List.map Text.toRecord


formatFileDiffs : List { path : FilePath, source : Source, fixedSource : Source, errors : List Error } -> List Text
formatFileDiffs changedFiles =
    case changedFiles of
        [] ->
            []

        [ file ] ->
            formatFileDiff file

        firstFile :: secondFile :: restOfFiles ->
            List.concat
                [ formatFileDiff firstFile
                , [ Text.from "\n" ]
                , fileSeparator firstFile.path secondFile.path
                , formatFileDiffs (secondFile :: restOfFiles)
                ]


formatFileDiff : { path : FilePath, source : Source, fixedSource : Source, errors : List Error } -> List Text
formatFileDiff file =
    [ [ (" " ++ filePath file.path)
            |> String.padLeft 80 '-'
            |> Text.from
            |> Text.inBlue
      ]
    , Text.from "Applied from the fixes for the following errors:"
        :: List.concatMap (\error -> Text.from "\n  " :: formatErrorTitle Fixing error) file.errors
    , diff file.source file.fixedSource
    ]
        |> Text.join "\n\n"


diff : Source -> Source -> List Text
diff (Source before) (Source after) =
    Diff.diffLines before after
        |> addLineNumbers
        |> List.map extractValueFromChange
        |> List.intersperse (Text.from "\n")


addLineNumbers : List (Diff.Change String) -> List (Diff.Change Text)
addLineNumbers changes =
    let
        maxLineNumberLength : Int
        maxLineNumberLength =
            List.foldl
                (\change lineNumber ->
                    case change of
                        Diff.NoChange _ ->
                            lineNumber + 1

                        Diff.Removed _ ->
                            lineNumber + 1

                        Diff.Added str ->
                            lineNumber
                )
                0
                changes
                |> lengthOfLineNumber

        ( _, unchangedLines, diffLines ) =
            List.foldl
                (\change ( lineNumber, previousUnchangedLines, accDiffLines ) ->
                    case change of
                        Diff.NoChange str ->
                            ( lineNumber + 1, Diff.NoChange (Text.from <| lineNumberPrefix maxLineNumberLength lineNumber ++ str) :: previousUnchangedLines, accDiffLines )

                        Diff.Removed str ->
                            let
                                line : Text
                                line =
                                    (lineNumberPrefix maxLineNumberLength lineNumber ++ str)
                                        |> Text.from
                                        |> Text.inRed
                            in
                            ( lineNumber + 1, [], Diff.Removed line :: (removeUnchangedLines maxLineNumberLength previousUnchangedLines ++ accDiffLines) )

                        Diff.Added str ->
                            let
                                line : Text
                                line =
                                    (lineNumberPrefix maxLineNumberLength lineNumber ++ str)
                                        |> Text.from
                                        |> Text.inGreen
                            in
                            ( lineNumber, [], Diff.Added line :: (removeUnchangedLines maxLineNumberLength previousUnchangedLines ++ accDiffLines) )
                )
                ( 0, [], [] )
                changes
    in
    (unchangedLines ++ diffLines)
        |> dropNonInterestingUnchangedLines
        |> List.reverse
        |> dropNonInterestingUnchangedLines


removeUnchangedLines : Int -> List (Diff.Change Text) -> List (Diff.Change Text)
removeUnchangedLines maxLineNumberLength list =
    if List.length list >= 4 then
        List.take 1 list
            ++ Diff.NoChange (Text.from <| String.repeat (maxLineNumberLength + 1) "·")
            :: (list
                    |> List.reverse
                    |> List.take 1
                    |> List.reverse
               )

    else
        list


extractValueFromChange : Diff.Change a -> a
extractValueFromChange change =
    case change of
        Diff.NoChange value ->
            value

        Diff.Removed value ->
            value

        Diff.Added value ->
            value


dropNonInterestingUnchangedLines : List (Diff.Change a) -> List (Diff.Change a)
dropNonInterestingUnchangedLines changes =
    case findIndex (not << isNoChange) changes of
        Nothing ->
            changes

        Just index ->
            List.drop (index - 1) changes


findIndex : (a -> Bool) -> List a -> Maybe Int
findIndex predicate list =
    findIndexInternal predicate 0 list


findIndexInternal : (a -> Bool) -> Int -> List a -> Maybe Int
findIndexInternal predicate index list =
    case list of
        [] ->
            Nothing

        item :: rest ->
            if predicate item then
                Just index

            else
                findIndexInternal predicate (index + 1) rest


isNoChange : Diff.Change a -> Bool
isNoChange change =
    case change of
        Diff.NoChange _ ->
            True

        Diff.Removed _ ->
            False

        Diff.Added _ ->
            False
