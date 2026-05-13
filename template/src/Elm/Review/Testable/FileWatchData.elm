module Elm.Review.Testable.FileWatchData exposing
    ( WatchOptions
    , FileEvent
    , EventType(..), toEventType
    )

{-|

@docs WatchOptions
@docs FileEvent
@docs EventType, toEventType

-}


{-| Options for file watching.
-}
type alias WatchOptions =
    { excludePaths : List String
    , recursive : Bool
    , coalesceMs : Int
    , eventMask : Int -- Bitmask: 1=Created, 2=Modified, 4=Deleted, 8=Renamed
    }


type alias FileEvent =
    { path : String
    , eventType : Int
    , timestamp : Int
    , subscriptionId : Int
    }


{-| Types of file system events.
-}
type EventType
    = Created
    | Modified
    | Deleted
    | Renamed


{-| Convert raw event type int to EventType.
-}
toEventType : Int -> EventType
toEventType n =
    if n == 1 then
        Created

    else if n == 2 then
        Modified

    else if n == 4 then
        Deleted

    else
        Renamed
