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
import Elm.Review.Testable.Internal exposing (TCmd)
import Elm.Review.Testable.TTask as TTask exposing (TTask)
import ElmReview.Color as Color exposing (Color(..), Colorize)
import ElmReview.Problem as Problem exposing (Problem)
import ElmReview.ReportMode as ReportMode
import Wrapper.Build as Build
import Wrapper.Options exposing (PrepareOfflineOptions)
import Wrapper.Options.RuleType exposing (RuleType)


type alias Model =
    ()


type Msg
    = Done (Result Problem.Exit ())


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


init : PrepareOfflineOptions -> TCmd Msg
init options =
    run options
        |> TTask.andThen
            (\() ->
                case options.reportMode of
                    ReportMode.HumanReadable ->
                        Cli.printlnStdoutTask (successMessage (Color.toAnsi options.color))

                    ReportMode.Json ->
                        TTask.succeed ()

                    ReportMode.NDJson ->
                        TTask.succeed ()
            )
        |> TTask.onError (\problem -> Problem.exitOnUnrecoverable (formatOptions options) problem)
        |> TTask.attempt Done


formatOptions : PrepareOfflineOptions -> Problem.FormatOptions {}
formatOptions options =
    { color = options.color
    , reportMode = ReportMode.HumanReadable
    , debug = options.debug
    , attemptFutureRecovery = False
    }


run : PrepareOfflineOptions -> TTask Problem ()
run options =
    TTask.sequence
        [ -- TODO Download the target project's dependencies like the Elm compiler would
          Build.build options
            |> TTask.map (\_ -> ())
        ]


update : Msg -> TCmd Msg
update msg =
    case msg of
        Done result ->
            case result of
                Ok () ->
                    Cli.exit 0

                Err exit ->
                    Problem.exit exit


successMessage : Colorize -> String
successMessage c =
    c GreenBright "elm-review" ++ " is now ready to be run " ++ c Cyan "--offline" ++ """.
  
You will need to run """ ++ c Yellow "elm-review prepare-offline" ++ " to keep the offline mode working if either your review configuration or your project's dependencies change."
