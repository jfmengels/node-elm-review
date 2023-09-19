module Elm.Review.Reporter exposing
    ( Error, File, FilePath(..), Source(..), TextContent
    , Mode(..), DetailsMode(..), formatReport, formatIndividualError
    , formatFixProposal, formatFixProposals
    , FileWithError, Range
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
import Elm.Review.SuppressedErrors as SuppressedErrors exposing (SuppressedErrors)
import Elm.Review.Text as Text exposing (Text)
import Elm.Review.UnsuppressMode as UnsuppressMode exposing (UnsuppressMode)
import Elm.Review.Vendor.Diff as Diff
import Review.Fix
import Set exposing (Set)


{-| Contents of an error. Convert the errors from
[`Review`](https://package.elm-lang.org/packages/jfmengels/elm-review/2.10.0/Review#Error)
to this type.
-}
type alias Error =
    { ruleName : String
    , ruleLink : Maybe String
    , message : String
    , details : List String
    , range : Range
    , providesFix : Bool
    , fixFailure : Maybe Review.Fix.Problem
    , suppressed : Bool
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
    | Global
    | ConfigurationError


filePath : FilePath -> String
filePath path_ =
    case path_ of
        FilePath str ->
            str

        Global ->
            ""

        ConfigurationError ->
            ""


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
formatReport :
    { suppressedErrors : SuppressedErrors
    , unsuppressMode : UnsuppressMode
    , originalNumberOfSuppressedErrors : Int
    , detailsMode : DetailsMode
    , errorsHaveBeenFixedPreviously : Bool
    , mode : Mode
    }
    -> List FileWithError
    -> List TextContent
formatReport { suppressedErrors, unsuppressMode, originalNumberOfSuppressedErrors, detailsMode, mode, errorsHaveBeenFixedPreviously } files =
    let
        numberOfErrors : Int
        numberOfErrors =
            totalNumberOfErrors files
    in
    if numberOfErrors == 0 then
        formatNoErrors suppressedErrors originalNumberOfSuppressedErrors errorsHaveBeenFixedPreviously

    else
        let
            filesWithErrors : List FileWithError
            filesWithErrors =
                files
                    |> List.filter (.errors >> List.isEmpty >> not)
                    |> List.sortBy (.path >> filePath)

            { rulesWithInvalidFixes, hasIgnoredFixableErrors } =
                classifyFixes (fixableErrors files)
        in
        [ formatReports detailsMode mode filesWithErrors
            |> Just
        , if showUnsuppressedWarning unsuppressMode files then
            Just
                [ "Errors marked with (unsuppressed) were previously suppressed, but you introduced new errors for the same rule and file. There are now more of those than what I previously allowed. Please fix them until you have at most as many errors as before. Maybe fix a few more while you're there?"
                    |> Text.from
                    |> Text.inOrange
                ]

          else
            Nothing
        , if hasIgnoredFixableErrors then
            Just
                [ "Errors marked with (fix) can be fixed automatically using `elm-review --fix`."
                    |> Text.from
                    |> Text.inBlue
                ]

          else
            Nothing
        , if mode == Fixing && not (Set.isEmpty rulesWithInvalidFixes) then
            Just
                [ ("I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:\n- "
                    ++ String.join "\n- " (Set.toList rulesWithInvalidFixes)
                  )
                    |> Text.from
                    |> Text.inYellow
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


classifyFixes : List Error -> { rulesWithInvalidFixes : Set String, hasIgnoredFixableErrors : Bool }
classifyFixes errors =
    let
        { rulesWithInvalidFixes, hasIgnoredFixableErrors } =
            classifyFixesHelp
                errors
                { rulesWithInvalidFixes = Set.empty, hasIgnoredFixableErrors = False }
    in
    { rulesWithInvalidFixes = rulesWithInvalidFixes
    , hasIgnoredFixableErrors = hasIgnoredFixableErrors
    }


classifyFixesHelp : List Error -> { rulesWithInvalidFixes : Set String, hasIgnoredFixableErrors : Bool } -> { rulesWithInvalidFixes : Set String, hasIgnoredFixableErrors : Bool }
classifyFixesHelp errors acc =
    case errors of
        [] ->
            acc

        error :: rest ->
            case error.fixFailure of
                Just _ ->
                    classifyFixesHelp
                        rest
                        { rulesWithInvalidFixes = Set.insert error.ruleName acc.rulesWithInvalidFixes, hasIgnoredFixableErrors = acc.hasIgnoredFixableErrors }

                Nothing ->
                    classifyFixesHelp
                        rest
                        { rulesWithInvalidFixes = acc.rulesWithInvalidFixes, hasIgnoredFixableErrors = True }


pluralize : Int -> String -> String
pluralize n word =
    String.fromInt n ++ " " ++ pluralizeEnding n word


pluralizeEnding : Int -> String -> String
pluralizeEnding n word =
    if n > 1 then
        word ++ "s"

    else
        word


showUnsuppressedWarning : UnsuppressMode -> List FileWithError -> Bool
showUnsuppressedWarning unsuppressMode files =
    case unsuppressMode of
        UnsuppressMode.UnsuppressAll ->
            False

        UnsuppressMode.UnsuppressRules set ->
            List.any
                (\file ->
                    List.any
                        (\error ->
                            error.suppressed && not (Set.member error.ruleName set)
                        )
                        file.errors
                )
                files

        UnsuppressMode.UnsuppressNone ->
            List.any
                (\file ->
                    List.any (\error -> error.suppressed) file.errors
                )
                files


formatNoErrors : SuppressedErrors -> Int -> Bool -> List Text.TextContent
formatNoErrors suppressedErrors originalNumberOfSuppressedErrors errorsHaveBeenFixedPreviously =
    let
        mainMessage : String
        mainMessage =
            if errorsHaveBeenFixedPreviously then
                "I found no more errors!"

            else
                "I found no errors!"

        numberOfSuppressedErrors : Int
        numberOfSuppressedErrors =
            SuppressedErrors.count suppressedErrors

        suppressedErrorMessage : List Text
        suppressedErrorMessage =
            if numberOfSuppressedErrors == 0 then
                []

            else
                let
                    are : String
                    are =
                        if numberOfSuppressedErrors == 1 then
                            "is"

                        else
                            "are"
                in
                List.concat
                    [ [ Text.from ("\n\nThere " ++ are ++ " still ")
                      , (String.fromInt numberOfSuppressedErrors ++ " suppressed " ++ pluralizeEnding numberOfSuppressedErrors "error")
                            |> Text.from
                            |> Text.inOrange
                      , Text.from " to address"
                      ]
                    , if numberOfSuppressedErrors < originalNumberOfSuppressedErrors then
                        [ Text.from ", and you just fixed "
                        , (originalNumberOfSuppressedErrors - numberOfSuppressedErrors)
                            |> String.fromInt
                            |> Text.from
                            |> Text.inGreen
                        , Text.from "!"
                        ]

                      else
                        [ Text.from "." ]
                    ]
    in
    (Text.from mainMessage :: suppressedErrorMessage)
        |> List.map Text.toRecord


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
header isFirstError filePath_ range =
    let
        position : String
        position =
            case filePath_ of
                FilePath str ->
                    " " ++ str ++ ":" ++ String.fromInt range.start.row ++ ":" ++ String.fromInt range.start.column

                Global ->
                    " GLOBAL ERROR"

                ConfigurationError ->
                    " CONFIGURATION ERROR"
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
            case codeExtract source error.range of
                [] ->
                    []

                sourceCodeExtract ->
                    Text.from "\n\n" :: sourceCodeExtract

        details : List Text
        details =
            case detailsMode of
                WithDetails ->
                    Text.from "\n\n"
                        :: (List.map Text.from error.details
                                |> List.intersperse (Text.from "\n\n")
                           )

                WithoutDetails ->
                    []

        fixFailMessage : List Text
        fixFailMessage =
            case mode of
                Fixing ->
                    case error.fixFailure of
                        Just problem ->
                            [ Text.from "\n\n"
                            , ("I failed to apply the automatic fix because " ++ reasonFromProblem problem)
                                |> Text.from
                                |> Text.inYellow
                            ]

                        Nothing ->
                            []

                Reviewing ->
                    []
    in
    List.concat
        [ formatErrorTitle mode error
        , codeExtract_
        , details
        , fixFailMessage
        ]


formatErrorTitle : Mode -> Error -> List Text
formatErrorTitle mode error =
    [ Text.from error.ruleName
        |> Text.inRed
        |> Text.withLink error.ruleLink
    , Text.from (": " ++ error.message)
    ]
        |> addFixPrefix mode error
        |> addSuppressedPrefix error


addSuppressedPrefix : Error -> List Text -> List Text
addSuppressedPrefix error previous =
    if error.suppressed then
        ("(unsuppressed) "
            |> Text.from
            |> Text.inOrange
        )
            :: previous

    else
        previous


addFixPrefix : Mode -> Error -> List Text -> List Text
addFixPrefix mode error previous =
    case mode of
        Fixing ->
            case error.fixFailure of
                Just _ ->
                    ("(FIX FAILED) "
                        |> Text.from
                        |> Text.inYellow
                    )
                        :: previous

                Nothing ->
                    previous

        Reviewing ->
            if error.providesFix then
                case error.fixFailure of
                    Just _ ->
                        previous

                    Nothing ->
                        ("(fix) "
                            |> Text.from
                            |> Text.inBlue
                        )
                            :: previous

            else
                previous


reasonFromProblem : Review.Fix.Problem -> String
reasonFromProblem problem =
    case problem of
        Review.Fix.Unchanged ->
            "it resulted in the same source code."

        Review.Fix.SourceCodeIsNotValid _ ->
            "it resulted in invalid Elm code."

        Review.Fix.HasCollisionsInFixRanges ->
            "it was invalid."


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

            getRowWithLineNumber : Int -> String
            getRowWithLineNumber rowIndex =
                lineNumberPrefix maxLineNumberLength rowIndex ++ getRowAtLine rowIndex

            getRowWithLineNumberUnlessEmpty : Int -> List Text
            getRowWithLineNumberUnlessEmpty rowIndex =
                let
                    line : String
                    line =
                        getRowAtLine rowIndex
                in
                if String.isEmpty line then
                    []

                else
                    [ Text.from (lineNumberPrefix maxLineNumberLength rowIndex ++ line) ]
        in
        if start.row == end.row then
            if start.column == end.column then
                []

            else
                let
                    lineContent : String
                    lineContent =
                        getRowWithLineNumber (start.row - 1)
                in
                [ getRowWithLineNumberUnlessEmpty (start.row - 2)
                , [ Text.from lineContent ]
                , underline gutterLength { start = start.column, end = end.column, lineContent = lineContent }
                , getRowWithLineNumberUnlessEmpty end.row
                ]
                    |> List.filter (not << List.isEmpty)
                    |> Text.join "\n"

        else
            let
                startLineNumber : Int
                startLineNumber =
                    start.row - 1

                startLineContent : String
                startLineContent =
                    getRowAtLine startLineNumber

                startLineContentWithLineNumber : String
                startLineContentWithLineNumber =
                    lineNumberPrefix maxLineNumberLength startLineNumber ++ startLineContent

                linesBetweenStartAndEnd : List Int
                linesBetweenStartAndEnd =
                    List.range start.row (end.row - 2)

                endLine : Int
                endLine =
                    end.row - 1

                endLineContent : String
                endLineContent =
                    getRowAtLine endLine

                endLineContentWithLineNumber : String
                endLineContentWithLineNumber =
                    lineNumberPrefix maxLineNumberLength endLine ++ endLineContent
            in
            [ getRowWithLineNumberUnlessEmpty (startLineNumber - 1)
            , [ Text.from startLineContentWithLineNumber ]
            , underline gutterLength
                { start = start.column
                , end = List.length (String.toList startLineContent) + 1
                , lineContent = startLineContentWithLineNumber
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
                                :: underlineWholeLine gutterLength line
                    )
                |> Text.join "\n"
            , [ Text.from endLineContentWithLineNumber ]
            , underline gutterLength
                { start = getIndexOfFirstNonSpace endLineContent + 1
                , end = end.column
                , lineContent = endLineContentWithLineNumber
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


underlineWholeLine : Int -> String -> List Text
underlineWholeLine gutterLength line =
    let
        start : Int
        start =
            getIndexOfFirstNonSpace line

        end : Int
        end =
            String.length line
    in
    [ Text.from <| String.repeat (gutterLength + start) " "
    , String.repeat (end - start) "^"
        |> Text.from
        |> Text.inRed
    ]


underline : Int -> { start : Int, end : Int, lineContent : String } -> List Text
underline gutterLength { start, end, lineContent } =
    let
        lineChars : List Char
        lineChars =
            String.toList lineContent

        preText : List Char
        preText =
            List.take (gutterLength + start - 1) lineChars

        unicodePreOffset : Int
        unicodePreOffset =
            -- Some characters like 🔧 are considered as 1 character by elm-syntax's range and editors' position coordinates,
            -- but are in practice shown as 2 character's wide in the editor and in the CLI.
            -- String.length "🔧" == 2
            -- List.length (String.toList "🔧") == 1
            String.length (String.fromList preText) - List.length preText

        inText : List Char
        inText =
            lineChars
                |> List.drop (gutterLength + start - 1)
                |> List.take (end - start)

        unicodeInOffset : Int
        unicodeInOffset =
            -- We want to show enough ^ characters to cover the whole underlined zone,
            -- and for unicode characters that sometimes means 2 ^
            String.length (String.fromList inText) - List.length inText
    in
    [ Text.from <| String.repeat (gutterLength + unicodePreOffset + start - 1) " "
    , String.repeat (unicodeInOffset + end - start) "^"
        |> Text.from
        |> Text.inRed
    ]


totalNumberOfErrors : List FileWithError -> Int
totalNumberOfErrors files =
    totalNumberOfErrorsHelp files 0


totalNumberOfErrorsHelp : List FileWithError -> Int -> Int
totalNumberOfErrorsHelp files acc =
    case files of
        [] ->
            acc

        file :: xs ->
            totalNumberOfErrorsHelp xs (acc + List.length file.errors)


fixableErrors : List FileWithError -> List Error
fixableErrors files =
    List.concatMap (\{ errors } -> List.filter (\error -> error.providesFix) errors) files


formatReports : DetailsMode -> Mode -> List FileWithError -> List Text
formatReports detailsMode mode files =
    formatReportsEndingWith [] detailsMode mode files


formatReportsEndingWith : List (List Text) -> DetailsMode -> Mode -> List FileWithError -> List Text
formatReportsEndingWith soFarReverse detailsMode mode files =
    case files of
        [] ->
            soFarReverse |> reverseThenConcat

        [ firstFile ] ->
            formatReportForFileWithExtract detailsMode mode firstFile
                :: soFarReverse
                |> reverseThenConcat

        firstFile :: secondFile :: restOfFiles ->
            formatReportsEndingWith
                (fileSeparator firstFile.path secondFile.path
                    :: formatReportForFileWithExtract detailsMode mode firstFile
                    :: soFarReverse
                )
                detailsMode
                mode
                (secondFile :: restOfFiles)


reverseThenConcat : List (List a) -> List a
reverseThenConcat reverseLists =
    List.foldl (++) [] reverseLists


fileSeparator : FilePath -> FilePath -> List Text
fileSeparator pathAbove pathBelow =
    [ Text.from <| "\n\n" ++ String.repeat (73 - String.length (filePath pathAbove)) " "
    , (filePath pathAbove ++ "  ↑")
        ++ "\n====o======================================================================o===="
        ++ "\n    ↓  "
        ++ filePath pathBelow
        |> Text.from
        |> Text.inRed
    , Text.from "\n\n\n"
    ]



-- FIX


{-| Reports a fix proposal for a single error in a nice human-readable way.
-}
formatFixProposal : DetailsMode -> File -> Error -> Source -> List TextContent
formatFixProposal detailsMode file error fixedSource =
    List.concat
        [ Text.join "\n\n"
            [ formatReportForFileWithExtract
                detailsMode
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
        :: List.concatMap (\error -> Text.from "\n  " :: formatErrorTitle Fixing error) (List.reverse file.errors)
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
                (\change ( currentMax, lineNumber ) ->
                    case change of
                        Diff.NoChange _ ->
                            ( currentMax, lineNumber + 1 )

                        Diff.Removed _ ->
                            ( lineNumber + 1, lineNumber + 1 )

                        Diff.Added _ ->
                            ( lineNumber, lineNumber )
                )
                ( 0, 0 )
                changes
                |> Tuple.first
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
