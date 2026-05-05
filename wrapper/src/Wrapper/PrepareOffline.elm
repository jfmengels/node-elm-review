module Wrapper.PrepareOffline exposing
    ( Model, init
    , Msg, update
    )

{-|

@docs Model, init
@docs Msg, update

-}

import Capabilities exposing (Console)
import Cli
import Elm.License exposing (License)
import Elm.Module as Module
import Elm.Package
import ElmReview.Color as Color exposing (Color(..), Colorize)
import ElmReview.Problem as Problem exposing (Problem)
import ElmReview.ReportMode as ReportMode
import ElmRun.TaskExtra as TaskExtra
import Fs exposing (FileSystem)
import Os exposing (ProcessCapability)
import Task exposing (Task)
import Wrapper.Build as Build
import Wrapper.Options exposing (PrepareOfflineOptions)
import Wrapper.Options.RuleType exposing (RuleType)


type Model
    = Model ModelData


type alias ModelData =
    { stdout : Console
    , stderr : Console
    , fs : FileSystem
    , os : ProcessCapability
    , options : PrepareOfflineOptions
    }


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


init : { env | stdout : Console, stderr : Console } -> { capabilities | fs : FileSystem, os : ProcessCapability } -> PrepareOfflineOptions -> ( Model, Cmd Msg )
init { stdout, stderr } { fs, os } options =
    ( Model
        { stdout = stdout
        , stderr = stderr
        , fs = fs
        , os = os
        , options = options
        }
    , run fs os options
        |> Task.attempt Done
    )


run : FileSystem -> ProcessCapability -> PrepareOfflineOptions -> Task Problem ()
run fs os options =
    TaskExtra.sequence
        [ -- TODO Download the target project's dependencies like the Elm compiler would
          Build.build fs os options
            |> Task.map (\_ -> ())
        ]


update : Msg -> Model -> Cmd Msg
update msg (Model model) =
    case msg of
        Done result ->
            case result of
                Ok () ->
                    Cmd.batch
                        [ case model.options.reportMode of
                            ReportMode.HumanReadable ->
                                Cli.println model.stdout (successMessage (Color.toAnsi model.options.color))

                            ReportMode.Json ->
                                Cmd.none

                            ReportMode.NDJson ->
                                Cmd.none
                        , Cli.exit 0
                        ]

                Err problem ->
                    Problem.stop model.stderr
                        { color = model.options.color
                        , reportMode = ReportMode.HumanReadable
                        , debug = model.options.debug
                        , attemptFutureRecovery = False
                        }
                        problem


successMessage : Colorize -> String
successMessage c =
    c GreenBright "elm-review" ++ " is now ready to be run " ++ c Cyan "--offline" ++ """.
  
You will need to run """ ++ c Yellow "elm-review prepare-offline" ++ " to keep the offline mode working if either your review configuration or your project's dependencies change."
