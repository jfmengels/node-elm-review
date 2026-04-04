module Elm.Review.SuppressedErrors exposing
    ( Msg
    , SuppressedErrors
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
    , update
    , write
    )

import Cli
import Dict exposing (Dict)
import Elm.Review.UnsuppressMode as UnsuppressMode exposing (UnsuppressMode)
import Elm.Review.Vendor.List.Extra as ListExtra
import ElmReview.Path as Path exposing (Path)
import ElmRun.FsExtra as FsExtra
import Fs exposing (FileSystem, FsError)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Review.Options as ReviewOptions exposing (ReviewOptions)
import Review.Rule as Rule
import Set exposing (Set)
import Task exposing (Task)
import Worker.Capabilities exposing (Console)


type SuppressedErrors
    = SuppressedErrors (Dict ( String, Path ) Int)


empty : SuppressedErrors
empty =
    SuppressedErrors Dict.empty


addFromFile : String -> String -> SuppressedErrors -> SuppressedErrors
addFromFile ruleName suppressionFileContent ((SuppressedErrors previous) as untouched) =
    case Decode.decodeString suppressionFileDecoder suppressionFileContent of
        Ok newSuppressions ->
            List.foldl
                (\( filePath, count_ ) dict -> Dict.insert ( ruleName, filePath ) count_ dict)
                (Dict.filter (\( ruleName_, _ ) _ -> ruleName /= ruleName_) previous)
                newSuppressions
                |> SuppressedErrors

        Err _ ->
            -- TODO Report error?
            untouched


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


suppressionFileDecoder : Decoder (List ( String, Int ))
suppressionFileDecoder =
    Decode.field "suppressions" (Decode.list fileEntryDecoder)


fileEntryDecoder : Decoder ( String, Int )
fileEntryDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "filePath" Decode.string)
        (Decode.field "count" Decode.int)



-- ENCODE


type Msg
    = WroteSuppressionFiles (Result String ())


update : Console -> Msg -> Cmd msg
update stdout (WroteSuppressionFiles result) =
    case result of
        Ok () ->
            Cmd.none

        Err error ->
            -- TODO Use Problem
            Cmd.batch
                [ Cli.println stdout error
                , Cli.exit 1
                ]


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


write : FileSystem -> { options | usesRemoteTemplate : Bool, suppress : Bool, usesRulesFilter : Bool } -> List String -> SuppressedErrors -> Cmd Msg
write fs options ruleNames suppressedErrors =
    if options.usesRemoteTemplate && not options.suppress then
        Cmd.none

    else
        let
            deleteAllRules : Bool
            deleteAllRules =
                options.suppress && not options.usesRulesFilter

            suppressedErrorsFolder : Path
            suppressedErrorsFolder =
                -- TODO Compute suppressedErrorsFolder
                Debug.todo "Compute suppressedErrorsFolder"
        in
        (if deleteAllRules then
            Fs.removeDirectory fs suppressedErrorsFolder

         else
            Task.succeed ()
        )
            |> Task.andThen (\() -> Fs.createDirectory fs suppressedErrorsFolder)
            |> Task.mapError FsExtra.errorToString
            |> Task.andThen
                (\() ->
                    suppressedErrors
                        |> suppressionsX ruleNames
                        |> taskMapAll (\suppressions -> writeFile fs suppressedErrorsFolder deleteAllRules suppressions)
                )
            |> Task.map (\_ -> ())
            |> Task.attempt WroteSuppressionFiles


{-| Like Task.map f >> Task.sequence but the return value is ()
-}
taskMapAll : (a -> Task x ()) -> List a -> Task x ()
taskMapAll f list =
    List.foldl (\task acc -> Task.map2 always (f task) acc) (Task.succeed ()) list


writeFile : FileSystem -> Path -> Bool -> ( String, List ( Int, Path ) ) -> Task String ()
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
                |> Task.mapError FsExtra.errorToString

    else
        let
            contents : String
            contents =
                formatSuppressionFile list
        in
        Fs.readTextFile fs filePath
            |> Task.andThen
                (\previousContents ->
                    if previousContents == contents then
                        Task.succeed ()

                    else
                        Fs.writeTextFile fs filePath contents
                )
            |> Task.mapError
                (\_ ->
                    -- TODO Use Problem
                    "FAILED TO UPDATE SUPPRESSION FILE"
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
