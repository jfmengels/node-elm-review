module Elm.Review.SuppressedErrors exposing
    ( SuppressedErrors
    , addFromFile
    , addToReviewOptions
    , apply
    , count
    , createFOR_TESTS
    , decoder
    , empty
    , encode
    , fromReviewErrors
    , member
    , suppressedFolder
    , write
    )

import Dict exposing (Dict)
import Elm.Review.Options exposing (Options)
import Elm.Review.UnsuppressMode as UnsuppressMode exposing (UnsuppressMode)
import Elm.Review.Vendor.List.Extra as ListExtra
import ElmReview.Color exposing (Color(..))
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem)
import ElmRun.FsExtra as FsExtra
import ElmRun.TaskExtra as TaskExtra
import Fs exposing (FileSystem, FsError)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Review.Options as ReviewOptions exposing (ReviewOptions)
import Review.Rule as Rule
import Set exposing (Set)
import Task exposing (Task)


suppressedFolder : Options -> Path
suppressedFolder options =
    Path.join2 options.reviewFolder "suppressed"


type SuppressedErrors
    = SuppressedErrors (Dict ( String, Path ) Int)


empty : SuppressedErrors
empty =
    SuppressedErrors Dict.empty


addFromFile : String -> String -> SuppressedErrors -> Result Problem SuppressedErrors
addFromFile filePath suppressionFileContent (SuppressedErrors previous) =
    case Decode.decodeString suppressionFileDecoder suppressionFileContent of
        Ok { version, suppressions } ->
            if version /= 1 then
                { title = "UNKNOWN VERSION FOR SUPPRESSION FILE"
                , message =
                    \c ->
                        "I was trying to read " ++ c Orange filePath ++ " but the version of that file is " ++ c Red ("\"" ++ String.fromInt version ++ "\"") ++ " whereas I only support version " ++ c YellowBright "1" ++ """.

Try updating """ ++ c GreenBright "elm-review" ++ " to a version that supports this version of suppression files."
                }
                    |> Problem.from Problem.Unrecoverable
                    |> Problem.withPath filePath
                    |> Err

            else
                let
                    ruleName : String
                    ruleName =
                        -- Remove trailing ".json"
                        String.dropRight 5 filePath
                in
                List.foldl
                    (\( path, count_ ) dict -> Dict.insert ( ruleName, path ) count_ dict)
                    (Dict.filter (\( ruleName_, _ ) _ -> ruleName /= ruleName_) previous)
                    suppressions
                    |> SuppressedErrors
                    |> Ok

        Err err ->
            { title = "PROBLEM READING SUPPRESSION FILE"
            , message = \c -> "I was trying to read " ++ c Orange filePath ++ " but encountered some problems:\n\n" ++ Decode.errorToString err
            }
                |> Problem.from Problem.Unrecoverable
                |> Problem.withPath filePath
                |> Err


fromReviewErrors : List Rule.ReviewError -> SuppressedErrors
fromReviewErrors reviewErrors =
    List.foldl
        (\error acc ->
            Dict.update
                ( Rule.errorRuleName error, Rule.errorFilePath error )
                (Maybe.withDefault 0 >> (+) 1 >> Just)
                acc
        )
        Dict.empty
        reviewErrors
        |> SuppressedErrors


apply : UnsuppressMode -> SuppressedErrors -> List Rule.ReviewError -> List Rule.ReviewError
apply unsuppressMode (SuppressedErrors suppressedErrors) errors =
    if Dict.isEmpty suppressedErrors then
        errors

    else
        case unsuppressMode of
            UnsuppressMode.UnsuppressAll ->
                errors

            UnsuppressMode.UnsuppressRules ruleNames ->
                applyHelp (filterSuppressed ruleNames suppressedErrors) errors

            UnsuppressMode.UnsuppressNone ->
                applyHelp suppressedErrors errors


filterSuppressed : Set String -> Dict ( String, String ) a -> Dict ( String, String ) a
filterSuppressed ruleNames suppressedErrors =
    Dict.filter
        (\( ruleName, _ ) _ ->
            not (Set.member ruleName ruleNames)
        )
        suppressedErrors


applyHelp : Dict ( String, String ) Int -> List Rule.ReviewError -> List Rule.ReviewError
applyHelp suppressedErrors errors =
    errors
        |> ListExtra.gatherWith (\a b -> (Rule.errorFilePath a == Rule.errorFilePath b) && (Rule.errorRuleName a == Rule.errorRuleName b))
        |> List.concatMap
            (\( head, tail ) ->
                case Dict.get ( Rule.errorRuleName head, Rule.errorFilePath head ) suppressedErrors of
                    Just nbSuppressedErrors ->
                        if List.length tail <= nbSuppressedErrors - 1 then
                            []

                        else
                            head :: tail

                    Nothing ->
                        head :: tail
            )


addToReviewOptions : SuppressedErrors -> ReviewOptions -> ReviewOptions
addToReviewOptions (SuppressedErrors suppressedErrors) reviewOptions =
    ReviewOptions.withSuppressedErrors suppressedErrors reviewOptions


count : SuppressedErrors -> Int
count (SuppressedErrors suppressedErrors) =
    suppressedErrors
        |> Dict.values
        |> List.sum


member : Rule.ReviewError -> SuppressedErrors -> Bool
member error (SuppressedErrors suppressedErrors) =
    Dict.member ( Rule.errorRuleName error, Rule.errorFilePath error ) suppressedErrors



-- DECODER


decoder : Decoder SuppressedErrors
decoder =
    Decode.list suppressedErrorEntryDecoder
        |> Decode.map (List.concat >> Dict.fromList >> SuppressedErrors)


suppressedErrorEntryDecoder : Decoder (List ( ( String, String ), Int ))
suppressedErrorEntryDecoder =
    Decode.map2
        (\rule suppressions ->
            List.map
                (\( filePath, nbSuppressedErrors ) ->
                    ( ( rule, filePath ), nbSuppressedErrors )
                )
                suppressions
        )
        (Decode.field "rule" Decode.string)
        (Decode.field "suppressions" (Decode.list fileEntryDecoder))


suppressionFileDecoder : Decoder { version : Int, suppressions : List ( String, Int ) }
suppressionFileDecoder =
    Decode.map2 (\version suppressions -> { version = version, suppressions = suppressions })
        (Decode.field "version" Decode.int)
        (Decode.field "suppressions" (Decode.list fileEntryDecoder))


fileEntryDecoder : Decoder ( String, Int )
fileEntryDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "filePath" Decode.string)
        (Decode.field "count" Decode.int)



-- ENCODE


encode : List String -> SuppressedErrors -> Encode.Value
encode ruleNames (SuppressedErrors suppressedErrors) =
    let
        suppressedErrorsList : List ( ( String, String ), Int )
        suppressedErrorsList =
            Dict.toList suppressedErrors

        rulesWithSuppressions : Set String
        rulesWithSuppressions =
            suppressedErrorsList
                |> List.map (Tuple.first >> Tuple.first)
                |> Set.fromList

        rulesWithoutSuppressions : List ( String, List a )
        rulesWithoutSuppressions =
            ruleNames
                |> List.filter (\ruleName -> not (Set.member ruleName rulesWithSuppressions))
                |> List.map (\ruleName -> ( ruleName, [] ))

        suppressionsPerRule : List ( String, List ( Int, Path ) )
        suppressionsPerRule =
            suppressedErrorsList
                |> List.foldl
                    (\( ( ruleName, path ), nbSuppressedErrors ) acc ->
                        Dict.update
                            ruleName
                            (Maybe.withDefault [] >> (::) ( nbSuppressedErrors, path ) >> Just)
                            acc
                    )
                    Dict.empty
                |> Dict.toList
    in
    Encode.list
        (\( ruleName, fileSuppressions ) ->
            encodeRuleSuppression ruleName (encodeFileSuppressions fileSuppressions)
        )
        (suppressionsPerRule ++ rulesWithoutSuppressions)


encodeRuleSuppression : String -> Encode.Value -> Encode.Value
encodeRuleSuppression ruleName fileSuppressions =
    Encode.object
        [ ( "rule", Encode.string ruleName )
        , ( "suppressions", fileSuppressions )
        ]


encodeFileSuppressions : List ( Int, Path ) -> Encode.Value
encodeFileSuppressions countPerFile =
    Encode.list encodeFileSuppression countPerFile


encodeFileSuppression : ( Int, Path ) -> Encode.Value
encodeFileSuppression ( nbSuppressedErrors, path ) =
    Encode.object
        [ ( "count", Encode.int nbSuppressedErrors )
        , ( "filePath", Encode.string path )
        ]



-- WRITE


write : FileSystem -> Options -> List String -> SuppressedErrors -> Maybe (Task Problem ())
write fs options ruleNames suppressedErrors =
    if options.usesRemoteTemplate && not options.suppress then
        Nothing

    else
        let
            deleteAllRules : Bool
            deleteAllRules =
                options.suppress && options.rulesFilter == Nothing

            suppressedErrorsFolder : Path
            suppressedErrorsFolder =
                suppressedFolder options
        in
        TaskExtra.sequence
            [ if deleteAllRules then
                Fs.removeDirectory fs suppressedErrorsFolder
                    |> Task.onError (\_ -> Task.succeed ())

              else
                Task.succeed ()
            , Fs.createDirectory fs suppressedErrorsFolder
                |> Task.onError (\_ -> Task.succeed ())
            , suppressedErrors
                |> suppressionsX ruleNames
                |> TaskExtra.mapAllAndIgnore (\suppressions -> writeFile fs suppressedErrorsFolder deleteAllRules suppressions)
            ]
            |> Task.mapError
                (\err ->
                    Problem.from Problem.Recoverable
                        { title = "PROBLEM WRITING SUPPRESSION FILES"
                        , message = \_ -> "I was trying to write suppressions files but encountered a problem:\n\n" ++ FsExtra.errorToString err
                        }
                )
            |> Just


writeFile : FileSystem -> Path -> Bool -> ( String, List ( Int, Path ) ) -> Task FsError ()
writeFile fs suppressedErrorsFolder deleteAllRules ( ruleName, list ) =
    let
        filePath : Path
        filePath =
            Path.join2 suppressedErrorsFolder (ruleName ++ ".json")
    in
    if List.isEmpty list then
        if deleteAllRules then
            Task.succeed ()

        else
            Fs.deleteFile fs filePath

    else
        Fs.readTextFile fs filePath
            |> Task.andThen
                (\previousContents ->
                    let
                        contents : String
                        contents =
                            formatSuppressionFile list
                    in
                    if previousContents == contents then
                        Task.succeed ()

                    else
                        Fs.writeTextFile fs filePath contents
                )


suppressionsX : List String -> SuppressedErrors -> List ( String, List ( Int, Path ) )
suppressionsX ruleNames (SuppressedErrors suppressedErrors) =
    let
        suppressedErrorsList : List ( ( String, String ), Int )
        suppressedErrorsList =
            Dict.toList suppressedErrors

        rulesWithSuppressions : Set String
        rulesWithSuppressions =
            suppressedErrorsList
                |> List.map (Tuple.first >> Tuple.first)
                |> Set.fromList

        rulesWithoutSuppressions : List ( String, List a )
        rulesWithoutSuppressions =
            ruleNames
                |> List.filter (\ruleName -> not (Set.member ruleName rulesWithSuppressions))
                |> List.map (\ruleName -> ( ruleName, [] ))

        suppressionsPerRule : List ( String, List ( Int, Path ) )
        suppressionsPerRule =
            suppressedErrorsList
                |> List.foldl
                    (\( ( ruleName, path ), nbSuppressedErrors ) acc ->
                        Dict.update
                            ruleName
                            (Maybe.withDefault [] >> (::) ( nbSuppressedErrors, path ) >> Just)
                            acc
                    )
                    Dict.empty
                |> Dict.toList
    in
    suppressionsPerRule ++ rulesWithoutSuppressions


formatSuppressionFile : List ( Int, Path ) -> String
formatSuppressionFile countPerFile =
    let
        suppressions : String
        suppressions =
            countPerFile
                |> List.sortBy (\( nb, _ ) -> -nb)
                |> List.map formatSuppressionEntry
                |> String.join ",\n    "
    in
    """{
  "version": 1,
  "automatically created by": "elm-review suppress",
  "learn more": "elm-review suppress --help",
  "suppressions": [
    """ ++ suppressions ++ """
  ]
}"""


formatSuppressionEntry : ( Int, Path ) -> String
formatSuppressionEntry ( nbSuppressedErrors, filePath ) =
    "{ \"count\": " ++ String.fromInt nbSuppressedErrors ++ ", \"filePath\": \"" ++ filePath ++ "\" }"



-- TESTS ONLY


createFOR_TESTS : List ( ( String, String ), Int ) -> SuppressedErrors
createFOR_TESTS =
    Dict.fromList >> SuppressedErrors
