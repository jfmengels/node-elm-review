module Wrapper.PrepareOffline exposing
    ( Model, init
    , Msg, update
    )

{-|

@docs Model, init
@docs Msg, update

-}

import Elm.License exposing (License)
import Elm.Module as Module
import Elm.Package
import Elm.Review.Testable.Cli as Cli
import Elm.Review.Testable.Cmd as TCmd
import Elm.Review.Testable.Internal exposing (TCmd)
import Elm.Review.Testable.TTask as TTask exposing (TTask)
import ElmReview.Color as Color exposing (Color(..), Colorize)
import ElmReview.Problem as Problem exposing (Problem)
import ElmReview.ReportMode as ReportMode
import Wrapper.Build as Build
import Wrapper.Options exposing (PrepareOfflineOptions)
import Wrapper.Options.RuleType exposing (RuleType)


type alias Model =
    PrepareOfflineOptions


type Msg
    = Done (Result Problem ())


type alias Input =
    { authorName : String
    , packageName : String
    , fullPackageName : Elm.Package.Name
    , ruleName : Module.Name
    , ruleType : RuleType
    , license : License
    }


type alias Warning =
    Colorize -> String


init : PrepareOfflineOptions -> ( Model, TCmd Msg )
init options =
    ( options
    , run options
        |> TTask.attempt Done
    )


run : PrepareOfflineOptions -> TTask Problem ()
run options =
    TTask.sequence
        [ -- TODO Download the target project's dependencies like the Elm compiler would
          Build.build options
            |> TTask.map (\_ -> ())
        ]


update : Msg -> Model -> TCmd Msg
update msg options =
    case msg of
        Done result ->
            case result of
                Ok () ->
                    TCmd.batch
                        [ case options.reportMode of
                            ReportMode.HumanReadable ->
                                Cli.printlnStdout (successMessage (Color.toAnsi options.color))

                            ReportMode.Json ->
                                TCmd.none

                            ReportMode.NDJson ->
                                TCmd.none
                        , Cli.exit 0
                        ]

                Err problem ->
                    Problem.stop
                        { color = options.color
                        , reportMode = ReportMode.HumanReadable
                        , debug = options.debug
                        , attemptFutureRecovery = False
                        }
                        problem


successMessage : Colorize -> String
successMessage c =
    c GreenBright "elm-review" ++ " is now ready to be run " ++ c Cyan "--offline" ++ """.
  
You will need to run """ ++ c Yellow "elm-review prepare-offline" ++ " to keep the offline mode working if either your review configuration or your project's dependencies change."
