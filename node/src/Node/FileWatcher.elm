module Node.FileWatcher exposing (watchFiles)

import Dict exposing (Dict)
import Elm.Review.Testable.FileWatchData as FileWatchData exposing (FileEvent, WatchOptions)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Maybe exposing (Maybe(..))
import Platform
import Platform.Sub exposing (Sub)
import Task exposing (Task)


watchFiles : WatchOptions -> (FileEvent -> msg) -> Sub msg
watchFiles options toMsg =
    subscription (FileWatch options toMsg)


subscription : a -> Sub msg
subscription _ =
    -- Dummy implementation, will be replaced by effect manager code.
    -- The following values are referenced in order to avoid the Elm compiler
    -- from stripping them away.
    let
        _ =
            ( onEffects, onSelfMsg )

        _ =
            ( init, subMap )
    in
    Sub.none


type MySub msg
    = FileWatch WatchOptions (FileEvent -> msg)


subMap : (a -> b) -> MySub a -> MySub b
subMap f (FileWatch options toMsg) =
    FileWatch options (f << toMsg)


type alias State msg =
    { taggers : List ( Key, FileWatchData.FileEvent -> msg )
    , close : Dict Key (List CloseTask)
    }


type alias CloseTask =
    Task Never Int


type alias Key =
    String


toKey : WatchOptions -> Key
toKey watchOptions =
    String.join "^$^"
        [ watchOptions.path
        , String.join ";" watchOptions.excludePaths
        , if watchOptions.recursive then
            "1"

          else
            "0"
        , String.fromInt watchOptions.coalesceMs
        , String.fromInt watchOptions.eventMask
        ]


init : Task Never (State msg)
init =
    Task.succeed
        { taggers = []
        , close = Dict.empty
        }


type alias FoldState =
    { toClose : List CloseTask
    , notChanged : Dict Key (List CloseTask)
    , toStart : List (Task Never ( Key, CloseTask ))
    }


onEffects : Platform.Router msg Event -> List (MySub msg) -> State msg -> Task Never (State msg)
onEffects router subs state =
    let
        newSubs : Dict Key WatchOptions
        newSubs =
            List.foldl
                (\(FileWatch options _) dict ->
                    Dict.insert (toKey options) options dict
                )
                Dict.empty
                subs

        stepLeft : Key -> List CloseTask -> FoldState -> FoldState
        stepLeft _ close { toClose, notChanged, toStart } =
            { toClose = List.append close toClose
            , notChanged = notChanged
            , toStart = toStart
            }

        stepBoth : Key -> List CloseTask -> WatchOptions -> FoldState -> FoldState
        stepBoth key close _ { toClose, notChanged, toStart } =
            { toClose = toClose
            , notChanged = Dict.insert key close notChanged
            , toStart = toStart
            }

        stepRight : Key -> WatchOptions -> FoldState -> FoldState
        stepRight key options { toClose, notChanged, toStart } =
            { toClose = toClose
            , notChanged = notChanged
            , toStart = spawn router key options :: toStart
            }

        res : FoldState
        res =
            Dict.merge
                stepLeft
                stepBoth
                stepRight
                state.close
                newSubs
                { toClose = []
                , notChanged = Dict.empty
                , toStart = []
                }
    in
    Task.sequence res.toClose
        |> Task.andThen (\_ -> Task.sequence res.toStart)
        |> Task.andThen
            (\closeToAdd ->
                let
                    newClose : Dict Key (List CloseTask)
                    newClose =
                        List.foldl
                            (\( key, close ) dict ->
                                case Dict.get key dict of
                                    Nothing ->
                                        Dict.insert key [ close ] dict

                                    Just previousClose ->
                                        Dict.insert key (close :: previousClose) dict
                            )
                            res.notChanged
                            closeToAdd
                in
                Task.succeed
                    { taggers = List.map (\(FileWatch options tagger) -> ( toKey options, tagger )) subs
                    , close = newClose
                    }
            )


spawn : Platform.Router msg Event -> Key -> WatchOptions -> Task Never ( Key, CloseTask )
spawn router key options =
    let
        handler : String -> Task x ()
        handler fileEventStr =
            case Decode.decodeString decodeFileEvent fileEventStr of
                Ok fileEvent ->
                    Platform.sendToSelf router { key = key, fileEvent = fileEvent }

                Err _ ->
                    Task.succeed ()
    in
    handler
        |> kernelStartWatch (Encode.encode 0 (encode options))
        |> Task.map (\close -> ( key, close ))


kernelStartWatch : String -> (String -> msg) -> Task x CloseTask
kernelStartWatch watchOptions onFileEvent =
    -- Dummy implementation, will be replaced by a glob invocation.
    Task.succeed (Task.succeed 0)


decodeFileEvent : Decoder FileEvent
decodeFileEvent =
    Decode.map4 FileEvent
        (Decode.field "path" Decode.string)
        (Decode.field "eventType" Decode.int)
        (Decode.field "timestamp" Decode.int)
        (Decode.field "subscriptionId" Decode.int)


encode : WatchOptions -> Encode.Value
encode watchOptions =
    Encode.object
        [ ( "path", Encode.string watchOptions.path )
        , ( "excluded", Encode.list Encode.string watchOptions.excludePaths )
        , ( "recursive", Encode.bool watchOptions.recursive )
        , ( "coalesceMs", Encode.int watchOptions.coalesceMs )
        , ( "eventMask", Encode.int watchOptions.eventMask )
        ]


type alias Event =
    { key : Key
    , fileEvent : FileEvent
    }


onSelfMsg : Platform.Router msg Event -> Event -> State msg -> Task Never (State msg)
onSelfMsg router { key, fileEvent } state =
    state.taggers
        |> List.filter (\( watcherKey, _ ) -> key == watcherKey)
        |> List.map (\( _, tagger ) -> Platform.sendToApp router (tagger fileEvent))
        |> Task.sequence
        |> Task.map (\_ -> state)
