module Elm.Review.Reporter exposing
    ( Error, File, FilePath(..), Source(..), TextContent
    , Mode(..), DetailsMode(..), formatReport, formatIndividualError
    , formatFixProposals
    , FileWithError, Range, formatConfigurationErrors, formatSingleFixProposal
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
import Dict exposing (Dict)
import Elm.Review.FixExplanation as FixExplanation exposing (FixExplanation)
import Elm.Review.SuppressedErrors as SuppressedErrors exposing (SuppressedErrors)
import Elm.Review.Text as Text exposing (Text)
import Elm.Review.UnsuppressMode as UnsuppressMode exposing (UnsuppressMode)
import Elm.Review.Vendor.Diff as Diff
import Elm.Syntax.Range exposing (Location)
import Json.Decode
import Parser
import Review.Fix
import Review.Fix.FixProblem as FixProblem exposing (FixProblem)
import Review.Project as Project
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
    , fixProblem : Maybe FixProblem
    , providesFileRemovalFix : Bool
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


filePathToString : FilePath -> String
filePathToString path_ =
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
    | Fixing Bool


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
    , fixExplanation : FixExplanation
    , errorsHaveBeenFixedPreviously : Bool
    , mode : Mode
    }
    -> List FileWithError
    -> List TextContent
formatReport { suppressedErrors, unsuppressMode, originalNumberOfSuppressedErrors, detailsMode, fixExplanation, errorsHaveBeenFixedPreviously, mode } files =
    let
        { numberOfFileErrors, numberOfGlobalErrors } =
            countErrors files
    in
    if numberOfFileErrors + numberOfGlobalErrors == 0 then
        formatNoErrors suppressedErrors originalNumberOfSuppressedErrors errorsHaveBeenFixedPreviously

    else
        let
            filesWithErrors : List FileWithError
            filesWithErrors =
                files
                    |> List.filter (.errors >> List.isEmpty >> not)
                    |> List.sortBy (.path >> filePathToString)

            { rulesWithInvalidFixes, hasIgnoredFixableErrors, hasFileRemovalFixes } =
                classifyFixes (fixableErrors files)
        in
        [ formatReports detailsMode fixExplanation mode filesWithErrors
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
        , case mode of
            Fixing True ->
                Nothing

            _ ->
                if hasFileRemovalFixes then
                    if hasIgnoredFixableErrors then
                        Just
                            [ "Errors marked with (fix removes files) can be fixed automatically by\nalso using `--allow-remove-files`."
                                |> Text.from
                                |> Text.inBlue
                            ]

                    else
                        Just
                            [ """Errors marked with (fix removes files) can be fixed automatically
using `elm-review --fix --allow-remove-files`."""
                                |> Text.from
                                |> Text.inBlue
                            ]

                else
                    Nothing
        , case mode of
            Reviewing ->
                Nothing

            Fixing _ ->
                if not (Dict.isEmpty rulesWithInvalidFixes) then
                    [ ("I tried applying some fixes but they failed in ways the author(s) didn't expect. Please let the author(s) of the following rules know:"
                        |> Text.from
                        |> Text.inYellow
                      )
                        :: (Dict.toList rulesWithInvalidFixes |> List.concatMap listFailingRules)
                    , [ case fixExplanation of
                            FixExplanation.Succinct ->
                                "Before doing so, I highly recommend re-running `elm-review` with `--explain-fix-failure`, which provides more information that could help solve the issue."
                                    |> Text.from
                                    |> Text.inYellow

                            FixExplanation.Detailed ->
                                "Please try to provide a SSCCE (https://sscce.org/) and as much information as possible to help solve the issue."
                                    |> Text.from
                                    |> Text.inYellow
                      ]
                    ]
                        |> Text.join "\n\n"
                        |> Just

                else
                    Nothing
        , Just (formatTally filesWithErrors numberOfFileErrors numberOfGlobalErrors)
        ]
            |> List.filterMap identity
            |> Text.join "\n\n"
            |> Text.simplify
            |> List.map Text.toRecord


listFailingRules : ( String, Maybe String ) -> List Text
listFailingRules ( ruleName, rulePackage ) =
    let
        base : Text
        base =
            ("\n- " ++ ruleName)
                |> Text.from
                |> Text.inYellow
    in
    case rulePackage of
        Just rulePackageName ->
            [ base
            , Text.from " ("
            , rulePackageName
                |> Text.from
                |> Text.withLink (Just ("https://github.com/" ++ rulePackageName ++ "/issues"))
            , Text.from ")"
            ]

        Nothing ->
            [ base ]


{-| Reports configuration errors reported by `elm-review` in a nice human-readable way.
-}
formatConfigurationErrors : { detailsMode : DetailsMode, mode : Mode, configurationErrors : List Error } -> List TextContent
formatConfigurationErrors { detailsMode, mode, configurationErrors } =
    let
        filesWithErrors : List FileWithError
        filesWithErrors =
            [ { path = ConfigurationError
              , source = Source ""
              , errors = configurationErrors
              }
            ]
    in
    [ formatReports detailsMode FixExplanation.Succinct mode filesWithErrors
    , [ Text.from "I found "
      , pluralize (List.length configurationErrors) "configuration error" |> Text.from |> Text.inRed
      , Text.from "."
      ]
    ]
        |> Text.join "\n\n"
        |> Text.simplify
        |> List.map Text.toRecord


formatTally : List a -> Int -> Int -> List Text
formatTally filesWithErrors numberOfFileErrors numberOfGlobalErrors =
    Text.join ""
        [ [ Text.from "I found " ]
        , [ if numberOfFileErrors > 0 then
                let
                    numberOfFilesWithErrors : Int
                    numberOfFilesWithErrors =
                        if numberOfGlobalErrors > 0 then
                            List.length filesWithErrors - 1

                        else
                            List.length filesWithErrors
                in
                Just
                    [ pluralize numberOfFileErrors "error" |> Text.from |> Text.inRed
                    , Text.from " in "
                    , pluralize numberOfFilesWithErrors "file" |> Text.from |> Text.inYellow
                    ]

            else
                Nothing
          , if numberOfGlobalErrors > 0 then
                Just
                    [ pluralize numberOfGlobalErrors "global error" |> Text.from |> Text.inRed
                    ]

            else
                Nothing
          ]
            |> List.filterMap identity
            |> Text.join " and "
        , [ Text.from "." ]
        ]


classifyFixes : List Error -> { rulesWithInvalidFixes : Dict String (Maybe String), hasIgnoredFixableErrors : Bool, hasFileRemovalFixes : Bool }
classifyFixes errors =
    classifyFixesHelp
        errors
        { rulesWithInvalidFixes = Dict.empty, hasIgnoredFixableErrors = False, hasFileRemovalFixes = False }


classifyFixesHelp :
    List Error
    -> { rulesWithInvalidFixes : Dict String (Maybe String), hasIgnoredFixableErrors : Bool, hasFileRemovalFixes : Bool }
    -> { rulesWithInvalidFixes : Dict String (Maybe String), hasIgnoredFixableErrors : Bool, hasFileRemovalFixes : Bool }
classifyFixesHelp errors acc =
    case errors of
        [] ->
            acc

        error :: rest ->
            case error.fixProblem of
                Just _ ->
                    classifyFixesHelp
                        rest
                        { rulesWithInvalidFixes = Dict.insert error.ruleName (packageName error) acc.rulesWithInvalidFixes
                        , hasIgnoredFixableErrors = acc.hasIgnoredFixableErrors
                        , hasFileRemovalFixes = acc.hasFileRemovalFixes
                        }

                Nothing ->
                    classifyFixesHelp
                        rest
                        { rulesWithInvalidFixes = acc.rulesWithInvalidFixes
                        , hasIgnoredFixableErrors = not error.providesFileRemovalFix || acc.hasIgnoredFixableErrors
                        , hasFileRemovalFixes = error.providesFileRemovalFix || acc.hasFileRemovalFixes
                        }


packageName : Error -> Maybe String
packageName error =
    error.ruleLink
        |> Maybe.andThen
            (\link ->
                case
                    link
                        |> String.replace "https://package.elm-lang.org/packages/" ""
                        |> String.split "/"
                of
                    author :: pkg :: _ ->
                        Just (author ++ "/" ++ pkg)

                    _ ->
                        Nothing
            )


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


formatReportForFileWithExtract : DetailsMode -> FixExplanation -> Mode -> FileWithError -> List Text
formatReportForFileWithExtract detailsMode fixExplanation mode file =
    file.errors
        |> List.sortWith compareErrorPositions
        |> List.indexedMap
            (\index error ->
                Text.join "\n\n"
                    [ [ header (index == 0) file.path error.range ]
                    , formatErrorWithExtract detailsMode fixExplanation mode file.source error
                    ]
            )
        |> Text.join "\n\n"


firstErrorPrefix : String
firstErrorPrefix =
    "-- ELM-REVIEW ERROR -"


header : Bool -> FilePath -> Range -> Text
header isFirstError filePath range =
    let
        position : String
        position =
            case filePath of
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


formatIndividualError : DetailsMode -> FixExplanation -> Source -> Error -> List TextContent
formatIndividualError detailsMode fixExplanation source error =
    formatErrorWithExtract detailsMode fixExplanation Reviewing source error
        |> Text.simplify
        |> List.map Text.toRecord


formatErrorWithExtract : DetailsMode -> FixExplanation -> Mode -> Source -> Error -> List Text
formatErrorWithExtract detailsMode fixExplanation mode source error =
    let
        codeExtract_ : List Text
        codeExtract_ =
            case codeExtract source error.range Nothing of
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
                Fixing _ ->
                    case error.fixProblem of
                        Just problem ->
                            Text.from "\n\n"
                                :: reasonFromProblem fixExplanation problem

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
        Fixing fileRemovalFixesEnabled ->
            case error.fixProblem of
                Just _ ->
                    ("(FIX FAILED) "
                        |> Text.from
                        |> Text.inYellow
                    )
                        :: previous

                Nothing ->
                    if not fileRemovalFixesEnabled && error.providesFileRemovalFix then
                        ("(fix removes files) "
                            |> Text.from
                            |> Text.inBlue
                        )
                            :: previous

                    else
                        previous

        Reviewing ->
            case error.fixProblem of
                Just _ ->
                    ("(failing fix) "
                        |> Text.from
                        |> Text.inYellow
                    )
                        :: previous

                Nothing ->
                    if error.providesFix then
                        if error.providesFileRemovalFix then
                            ("(fix removes files) "
                                |> Text.from
                                |> Text.inBlue
                            )
                                :: previous

                        else
                            ("(fix) "
                                |> Text.from
                                |> Text.inBlue
                            )
                                :: previous

                    else
                        previous


reasonFromProblem : FixExplanation -> FixProblem -> List Text
reasonFromProblem fixExplanation problem =
    case fixExplanation of
        FixExplanation.Succinct ->
            succinctReasonFromProblem problem

        FixExplanation.Detailed ->
            detailedReasonFromProblem problem


succinctReasonFromProblem : FixProblem -> List Text
succinctReasonFromProblem problem =
    case problem of
        FixProblem.Unchanged { filePath } ->
            [ "I failed to apply the automatic fix because it resulted in the same source code for "
                |> Text.from
                |> Text.inYellow
            , filePath
                |> Text.from
                |> Text.inRed
            , "."
                |> Text.from
                |> Text.inYellow
            ]

        FixProblem.InvalidElm { filePath } ->
            [ "I failed to apply the automatic fix because it resulted in invalid Elm code for "
                |> Text.from
                |> Text.inYellow
            , filePath
                |> Text.from
                |> Text.inRed
            , "."
                |> Text.from
                |> Text.inYellow
            ]

        FixProblem.InvalidJson { filePath } ->
            [ "I failed to apply the automatic fix because it resulted in invalid JSON for "
                |> Text.from
                |> Text.inYellow
            , filePath
                |> Text.from
                |> Text.inRed
            , "."
                |> Text.from
                |> Text.inYellow
            ]

        FixProblem.HasCollisionsInEditRanges _ ->
            [ "I failed to apply the automatic fix because it contained edits with collisions."
                |> Text.from
                |> Text.inYellow
            ]

        FixProblem.EditWithNegativeRange _ ->
            [ "I failed to apply the automatic fix because it contained edits with negative ranges."
                |> Text.from
                |> Text.inYellow
            ]

        FixProblem.CreatesImportCycle _ ->
            [ "I failed to apply the automatic fix because it resulted in an import cycle."
                |> Text.from
                |> Text.inYellow
            ]

        FixProblem.RemovesUnknownFile filePath ->
            [ ("I failed to apply the automatic fix because it attempted to remove " ++ filePath ++ """ which is unknown to me.
This should not be possible in theory, so please open an issue so this can be fixed.""")
                |> Text.from
                |> Text.inYellow
            ]

        FixProblem.Other problemDescription ->
            [ ("I failed to apply the automatic fix.\n\n" ++ problemDescription)
                |> Text.from
                |> Text.inYellow
            ]


detailedReasonFromProblem : FixProblem -> List Text
detailedReasonFromProblem problem =
    case problem of
        FixProblem.Unchanged { filePath, edits } ->
            [ ("""I failed to apply the automatic fix because it resulted in the same source code.

After applying the fixes, """ ++ filePath)
                |> Text.from
                |> Text.inYellow
            , "\n\nHere are the individual edits for the file:"
                |> Text.from
                |> Text.inYellow
            , Text.from "\n\n    "
            , List.map (Review.Fix.toRecord >> editToFix) edits
                |> String.join "\n    , "
                |> wrapIn "[ " "\n    ]"
                |> Text.from
                |> Text.inYellow
            ]

        FixProblem.InvalidElm invalid ->
            let
                firstParsingError : Parser.DeadEnd
                firstParsingError =
                    List.head invalid.parsingErrors
                        |> Maybe.withDefault { row = 1, col = 1, problem = Parser.Problem "Parsing error" }
            in
            List.concat
                [ [ "I failed to apply the automatic fix because it resulted in "
                        |> Text.from
                        |> Text.inYellow
                  , invalid.filePath
                        |> Text.from
                        |> Text.inRed
                  , " being invalid Elm code:"
                        |> Text.from
                        |> Text.inYellow
                  , Text.from "\n\n"
                  , deadEndsToString invalid.parsingErrors
                        |> Text.from
                        |> Text.inYellow
                  , Text.from "\n\n"
                  ]
                , codeExtract (Source invalid.source)
                    { start = { row = firstParsingError.row, column = firstParsingError.col }
                    , end = { row = firstParsingError.row, column = firstParsingError.col + 1 }
                    }
                    (Just (problemToString firstParsingError.problem))
                , [ Text.from "\n\n"
                  , "Here are the individual edits for the file:"
                        |> Text.from
                        |> Text.inYellow
                  , Text.from "\n\n    "
                  , List.map (Review.Fix.toRecord >> editToFix) invalid.edits
                        |> String.join "\n    , "
                        |> wrapIn "[ " "\n    ]"
                        |> Text.from
                        |> Text.inYellow
                  ]
                ]

        FixProblem.InvalidJson { filePath, source, edits, decodingError } ->
            [ "I failed to apply the automatic fix because it resulted in "
                |> Text.from
                |> Text.inYellow
            , filePath
                |> Text.from
                |> Text.inRed
            , " being invalid Elm code:"
                |> Text.from
                |> Text.inYellow
            , Text.from "\n\n"
            , ("    " ++ Json.Decode.errorToString decodingError)
                |> Text.from
                |> Text.inYellow
            , Text.from "\n\n"
            , source
                |> Text.from
            , "\n\nHere are the individual edits for the file:"
                |> Text.from
                |> Text.inYellow
            , Text.from "\n\n    "
            , List.map (Review.Fix.toRecord >> editToFix) edits
                |> String.join "\n    , "
                |> wrapIn "[ " "\n    ]"
                |> Text.from
                |> Text.inYellow
            ]

        FixProblem.HasCollisionsInEditRanges { filePath, edits } ->
            [ ("I failed to apply the automatic fix because some edits for " ++ filePath ++ " collide:\n\n    " ++ String.join "\n\n    " (List.map (Review.Fix.toRecord >> editToFix) edits))
                |> Text.from
                |> Text.inYellow
            ]

        FixProblem.EditWithNegativeRange { filePath, edit } ->
            [ ("I failed to apply the automatic fix because I have found an edit for " ++ filePath ++ " where the start is positioned after the end:\n\n  " ++ editToFix (Review.Fix.toRecord edit))
                |> Text.from
                |> Text.inYellow
            ]

        FixProblem.CreatesImportCycle cycle ->
            ("I failed to apply the automatic fix because it resulted in an import cycle."
                |> Text.from
                |> Text.inYellow
            )
                :: Text.from "\n\n"
                :: printCycle cycle

        FixProblem.RemovesUnknownFile filePath ->
            [ ("I failed to apply the automatic fix because it attempted to remove " ++ filePath ++ """ which is unknown to me.
This should not be possible in theory, so please open an issue so this can be fixed.""")
                |> Text.from
                |> Text.inYellow
            ]

        FixProblem.Other problemDescription ->
            [ ("I failed to apply the automatic fix.\n\n" ++ problemDescription)
                |> Text.from
                |> Text.inYellow
            ]


printCycle : List String -> List Text
printCycle moduleNames =
    [ [ "    ┌─────┐\n    │    "
            |> Text.from
      ]
    , moduleNames
        |> List.map (\moduleName -> moduleName |> Text.from |> Text.inYellow)
        |> List.intersperse (Text.from "\n    │     ↓\n    │    ")
    , [ "\n    └─────┘"
            |> Text.from
      ]
    ]
        |> Text.join ""


wrapInCycle : String -> String
wrapInCycle string =
    "    ┌─────┐\n    │    " ++ string ++ "\n    └─────┘"


editToFix : { range : Range, replacement : String } -> String
editToFix { range, replacement } =
    if replacement == "" then
        "Review.Fix.removeRange\n         " ++ rangeAsString range

    else if range.start == range.end then
        "Review.Fix.insertAt\n         " ++ locationAsString range.start ++ "\n         " ++ wrapInDoubleOrTripleQuotes replacement

    else
        "Review.Fix.replaceRangeBy\n         " ++ rangeAsString range ++ "\n         " ++ wrapInDoubleOrTripleQuotes replacement


rangeAsString : Range -> String
rangeAsString { start, end } =
    "{ start = " ++ locationAsString start ++ ", end = " ++ locationAsString end ++ " }"


locationAsString : Location -> String
locationAsString location =
    "{ row = " ++ String.fromInt location.row ++ ", column = " ++ String.fromInt location.column ++ " }"


wrapIn : String -> String -> String -> String
wrapIn start end string =
    start ++ string ++ end ++ ""


wrapInDoubleOrTripleQuotes : String -> String
wrapInDoubleOrTripleQuotes string =
    if String.contains "\"" string then
        "\"\"\"" ++ string ++ "\"\"\""

    else
        "\"" ++ string ++ "\""


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


codeExtract : Source -> Range -> Maybe String -> List Text
codeExtract (Source source) { start, end } messageAfterCarets =
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
            let
                line : String
                line =
                    getRowAtLine rowIndex
            in
            if String.isEmpty line then
                lineNumberPrefixUnpadded maxLineNumberLength rowIndex

            else
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
            , underline gutterLength { start = start.column, end = end.column, lineContent = lineContent } messageAfterCarets
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
            messageAfterCarets
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
            messageAfterCarets
        , getRowWithLineNumberUnlessEmpty (endLine + 1)
        ]
            |> List.filter (not << List.isEmpty)
            |> Text.join "\n"


getIndexOfFirstNonSpace : String -> Int
getIndexOfFirstNonSpace string =
    String.length string - String.length (String.trimLeft string)


lineNumberPrefix : Int -> Int -> String
lineNumberPrefix maxLineNumberLength rowIndex =
    lineNumberPrefixUnpadded maxLineNumberLength rowIndex ++ " "


lineNumberPrefixUnpadded : Int -> Int -> String
lineNumberPrefixUnpadded maxLineNumberLength rowIndex =
    ((rowIndex + 1)
        |> String.fromInt
        |> String.padLeft maxLineNumberLength ' '
    )
        ++ "|"


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


underline : Int -> { start : Int, end : Int, lineContent : String } -> Maybe String -> List Text
underline gutterLength { start, end, lineContent } messageAfterCarets =
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

        baseCarets : String
        baseCarets =
            String.repeat (unicodeInOffset + end - start) "^"

        caretLine : String
        caretLine =
            case messageAfterCarets of
                Just message ->
                    baseCarets ++ " " ++ message

                Nothing ->
                    baseCarets
    in
    [ Text.from <| String.repeat (gutterLength + unicodePreOffset + start - 1) " "
    , caretLine
        |> Text.from
        |> Text.inRed
    ]


countErrors : List FileWithError -> { numberOfFileErrors : Int, numberOfGlobalErrors : Int }
countErrors files =
    countErrorsHelp files { numberOfFileErrors = 0, numberOfGlobalErrors = 0 }


countErrorsHelp : List FileWithError -> { numberOfFileErrors : Int, numberOfGlobalErrors : Int } -> { numberOfFileErrors : Int, numberOfGlobalErrors : Int }
countErrorsHelp files acc =
    case files of
        [] ->
            acc

        file :: xs ->
            case file.path of
                FilePath _ ->
                    countErrorsHelp xs
                        { numberOfFileErrors = acc.numberOfFileErrors + List.length file.errors
                        , numberOfGlobalErrors = acc.numberOfGlobalErrors
                        }

                Global ->
                    countErrorsHelp xs
                        { numberOfFileErrors = acc.numberOfFileErrors
                        , numberOfGlobalErrors = acc.numberOfGlobalErrors + List.length file.errors
                        }

                ConfigurationError ->
                    countErrorsHelp xs acc


fixableErrors : List FileWithError -> List Error
fixableErrors files =
    List.concatMap (\{ errors } -> List.filter (\error -> error.providesFix) errors) files


formatReports : DetailsMode -> FixExplanation -> Mode -> List FileWithError -> List Text
formatReports detailsMode fixExplanation mode files =
    formatReportsEndingWith [] detailsMode fixExplanation mode files


formatReportsEndingWith : List (List Text) -> DetailsMode -> FixExplanation -> Mode -> List FileWithError -> List Text
formatReportsEndingWith soFarReverse detailsMode fixExplanation mode files =
    case files of
        [] ->
            soFarReverse |> reverseThenConcat

        [ firstFile ] ->
            formatReportForFileWithExtract detailsMode fixExplanation mode firstFile
                :: soFarReverse
                |> reverseThenConcat

        firstFile :: secondFile :: restOfFiles ->
            formatReportsEndingWith
                (fileSeparator firstFile.path secondFile.path
                    :: formatReportForFileWithExtract detailsMode fixExplanation mode firstFile
                    :: soFarReverse
                )
                detailsMode
                fixExplanation
                mode
                (secondFile :: restOfFiles)


reverseThenConcat : List (List a) -> List a
reverseThenConcat reverseLists =
    List.foldl (++) [] reverseLists


fileSeparator : FilePath -> FilePath -> List Text
fileSeparator pathAbove pathBelow =
    [ Text.from <| "\n\n" ++ String.repeat (73 - String.length (filePathToString pathAbove)) " "
    , (filePathToString pathAbove ++ "  ↑")
        ++ "\n====o======================================================================o===="
        ++ "\n    ↓  "
        ++ filePathToString pathBelow
        |> Text.from
        |> Text.inRed
    , Text.from "\n\n\n"
    ]



-- FIX


{-| Reports a fix proposal for a single error in a nice human-readable way.
-}
formatSingleFixProposal : DetailsMode -> FixExplanation -> Bool -> File -> Error -> List { path : String, diff : Project.Diff } -> List TextContent
formatSingleFixProposal detailsMode fixExplanation fileRemovalFixesEnabled file error diffs =
    List.concat
        [ Text.join "\n\n"
            [ formatReportForFileWithExtract
                detailsMode
                fixExplanation
                (Fixing fileRemovalFixesEnabled)
                { path = file.path
                , source = file.source
                , errors = [ error ]
                }
            , [ "I think I can fix this. Here is my proposal:"
                    |> Text.from
                    |> Text.inBlue
              ]
            , case diffs of
                [ { path, diff } ] ->
                    case diff of
                        Project.Edited { before, after } ->
                            if FilePath path /= file.path then
                                formatFilePathForSingleFix path
                                    :: Text.from "\n\n"
                                    :: formatDiff before after

                            else
                                formatDiff before after

                        Project.Removed ->
                            if FilePath path /= file.path then
                                [ formatFilePathForSingleFix path
                                , Text.from "\n\n"
                                , Text.inRed (Text.from "    REMOVE FILE")
                                ]

                            else
                                [ Text.inRed (Text.from ("    REMOVE FILE " ++ path)) ]

                _ ->
                    let
                        numberOfDiffs : Int
                        numberOfDiffs =
                            List.length diffs
                    in
                    diffs
                        |> List.sortBy
                            (\{ path, diff } ->
                                case diff of
                                    -- Sort so that the file the error was for is presented first
                                    -- and deleted files show up at the end.
                                    Project.Edited _ ->
                                        if FilePath path == file.path then
                                            ( 0, "" )

                                        else
                                            ( 0, path )

                                    Project.Removed ->
                                        ( 1, path )
                            )
                        |> List.indexedMap
                            (\index { path, diff } ->
                                formatFilePathForSingleFixWith (index + 1) numberOfDiffs path
                                    :: Text.from "\n\n"
                                    :: (case diff of
                                            Project.Edited { before, after } ->
                                                formatDiff before after

                                            Project.Removed ->
                                                [ Text.inRed (Text.from "    REMOVE FILE") ]
                                       )
                            )
                        |> Text.join "\n\n"
            ]
        , [ Text.from "\n" ]
        ]
        |> List.map Text.toRecord


formatFilePathForSingleFix : String -> Text
formatFilePathForSingleFix path =
    path
        |> String.padLeft 80 '-'
        |> Text.from
        |> Text.inBlue


formatFilePathForSingleFixWith : Int -> Int -> String -> Text
formatFilePathForSingleFixWith fileNo numberOfFiles path =
    let
        page : String
        page =
            String.fromInt fileNo ++ "/" ++ String.fromInt numberOfFiles ++ " -"
    in
    (page ++ String.padLeft (80 - String.length page) '-' (" " ++ path))
        |> Text.from
        |> Text.inBlue


{-| Reports the proposal for the fix-all changes in a nice human-readable way.
-}
formatFixProposals :
    Bool
    -> Dict String (List Error)
    -> List { path : String, diff : Project.Diff }
    -> List TextContent
formatFixProposals fileRemovalFixesEnabled errorsForFile unsortedDiffs =
    let
        diffs : List { path : String, diff : Project.Diff }
        diffs =
            List.sortBy
                (\{ path, diff } ->
                    case diff of
                        -- Sort so that the file the error was for is presented first
                        -- and deleted files show up at the end.
                        Project.Edited _ ->
                            ( 0, path )

                        Project.Removed ->
                            ( 1, path )
                )
                unsortedDiffs

        fixAllHeader : Text
        fixAllHeader =
            "-- ELM-REVIEW FIX-ALL PROPOSAL "
                |> String.padRight 80 '-'
                |> Text.from
                |> Text.inBlue

        filesListing : List Text
        filesListing =
            Text.from "I found fixable errors for the following files:"
                :: List.concatMap
                    (\{ path } ->
                        [ Text.from "\n  "
                        , "- " ++ path |> Text.from |> Text.inYellow
                        ]
                    )
                    diffs

        body : List Text
        body =
            [ [ fixAllHeader ]
            , filesListing
            , [ Text.from "Here is how the code would change if you applied each fix." ]
            , formatFileDiffs fileRemovalFixesEnabled errorsForFile diffs
            ]
                |> Text.join "\n\n"
    in
    (body ++ [ Text.from "\n" ])
        |> List.map Text.toRecord


formatFileDiffs : Bool -> Dict String (List Error) -> List { path : String, diff : Project.Diff } -> List Text
formatFileDiffs fileRemovalFixesEnabled errorsForFile diffs =
    case diffs of
        [] ->
            []

        [ diff ] ->
            formatFileDiff fileRemovalFixesEnabled errorsForFile diff

        firstDiff :: secondDiff :: restOfDiffs ->
            List.concat
                [ formatFileDiff fileRemovalFixesEnabled errorsForFile firstDiff
                , [ Text.from "\n" ]
                , fileSeparator (FilePath firstDiff.path) (FilePath secondDiff.path)
                , formatFileDiffs fileRemovalFixesEnabled errorsForFile (secondDiff :: restOfDiffs)
                ]


formatFileDiff :
    Bool
    -> Dict String (List Error)
    -> { path : String, diff : Project.Diff }
    -> List Text
formatFileDiff fileRemovalFixesEnabled errorsForFile { path, diff } =
    [ [ (" " ++ path)
            |> String.padLeft 80 '-'
            |> Text.from
            |> Text.inBlue
      ]
    , Text.from "Modified by the following error fixes:"
        :: List.concatMap (\error -> Text.from "\n" :: formatErrorTitle (Fixing fileRemovalFixesEnabled) error) (List.reverse (Dict.get path errorsForFile |> Maybe.withDefault []))
    , case diff of
        Project.Edited { before, after } ->
            formatDiff before after

        Project.Removed ->
            [ Text.inRed (Text.from "    REMOVE FILE") ]
    ]
        |> Text.join "\n\n"


formatDiff : String -> String -> List Text
formatDiff before after =
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
                            let
                                line : String
                                line =
                                    if String.isEmpty str then
                                        lineNumberPrefixUnpadded maxLineNumberLength lineNumber

                                    else
                                        lineNumberPrefix maxLineNumberLength lineNumber ++ str
                            in
                            ( lineNumber + 1
                            , Diff.NoChange (Text.from line) :: previousUnchangedLines
                            , accDiffLines
                            )

                        Diff.Removed str ->
                            let
                                line : String
                                line =
                                    if String.isEmpty str then
                                        lineNumberPrefixUnpadded maxLineNumberLength lineNumber

                                    else
                                        lineNumberPrefix maxLineNumberLength lineNumber ++ str
                            in
                            ( lineNumber + 1
                            , []
                            , Diff.Removed (Text.inRed <| Text.from <| line)
                                :: (removeUnchangedLines maxLineNumberLength previousUnchangedLines ++ accDiffLines)
                            )

                        Diff.Added str ->
                            let
                                line : String
                                line =
                                    if String.isEmpty str then
                                        String.repeat (maxLineNumberLength - 1) " " ++ "+|"

                                    else
                                        String.repeat (maxLineNumberLength - 1) " " ++ "+| " ++ str
                            in
                            ( lineNumber
                            , []
                            , Diff.Added (Text.inGreen <| Text.from <| line)
                                :: (removeUnchangedLines maxLineNumberLength previousUnchangedLines ++ accDiffLines)
                            )
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


deadEndsToString : List Parser.DeadEnd -> String
deadEndsToString deadEnds =
    String.concat (List.intersperse "\n" (List.map deadEndToString deadEnds))


deadEndToString : Parser.DeadEnd -> String
deadEndToString deadend =
    problemToString deadend.problem ++ " at row " ++ String.fromInt deadend.row ++ ", column " ++ String.fromInt deadend.col


problemToString : Parser.Problem -> String
problemToString p =
    case p of
        Parser.Expecting s ->
            "Expecting '" ++ s ++ "'"

        Parser.ExpectingInt ->
            "Expecting int"

        Parser.ExpectingHex ->
            "Expecting hex"

        Parser.ExpectingOctal ->
            "Expecting octal"

        Parser.ExpectingBinary ->
            "Expecting binary"

        Parser.ExpectingFloat ->
            "Expecting float"

        Parser.ExpectingNumber ->
            "Expecting number"

        Parser.ExpectingVariable ->
            "Expecting variable"

        Parser.ExpectingSymbol s ->
            "Expecting symbol '" ++ s ++ "'"

        Parser.ExpectingKeyword s ->
            "Expecting keyword '" ++ s ++ "'"

        Parser.ExpectingEnd ->
            "Expecting end"

        Parser.UnexpectedChar ->
            "Unexpected char"

        Parser.Problem s ->
            s

        Parser.BadRepeat ->
            "Bad repeat"
