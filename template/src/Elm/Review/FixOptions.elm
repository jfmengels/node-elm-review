module Elm.Review.FixOptions exposing
    ( Mode(..), fixModeToReviewOptions
    , Explanation(..)
    )

{-|

@docs Mode, fixModeToReviewOptions
@docs Explanation

-}

import Review.Options as ReviewOptions


type Mode
    = DontFix
    | Fix
    | FixAll


type Explanation
    = Succinct
    | Detailed


fixModeToReviewOptions : Bool -> { options | fixMode : Mode, fixLimit : Maybe Int } -> ReviewOptions.FixMode
fixModeToReviewOptions fixesAllowed { fixMode, fixLimit } =
    if not fixesAllowed then
        ReviewOptions.fixedDisabled

    else
        case fixMode of
            DontFix ->
                ReviewOptions.fixedDisabled

            Fix ->
                case fixLimit of
                    Just limit ->
                        ReviewOptions.fixesEnabledWithLimit limit

                    Nothing ->
                        ReviewOptions.fixesEnabledWithLimit 1

            FixAll ->
                case fixLimit of
                    Just limit ->
                        ReviewOptions.fixesEnabledWithLimit limit

                    Nothing ->
                        ReviewOptions.fixesEnabledWithoutLimits
