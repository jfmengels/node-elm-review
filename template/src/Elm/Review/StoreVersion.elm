module Elm.Review.StoreVersion exposing (StoreVersion(..), increment, zero)

{-| Version of the Store's contents. Used to cheaply verify if there's anything to review again.
-}


type StoreVersion
    = StoreVersion Int


zero : StoreVersion
zero =
    StoreVersion 0


increment : StoreVersion -> StoreVersion
increment (StoreVersion version) =
    StoreVersion (version + 1)
