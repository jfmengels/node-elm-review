module Wrapper.Review exposing
    ( Model, init
    , Msg, update
    )

{-|

@docs Model, init
@docs Msg, update

-}

import Capabilities exposing (Console)
import Cli exposing (Env)
import Elm.Project
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (FormatOptions, Problem)
import ElmRun.OsExtra
import Fs exposing (FileSystem, FsError)
import Os exposing (ProcessCapability)
import Os.Process as Process exposing (ProcessError)
import Task exposing (Task)
import Wrapper.Build as Build
import Wrapper.Options exposing (ReviewOptions)
import Wrapper.ProjectPaths as ProjectPaths


type Model
    = Model ModelData


type alias ModelData =
    { stdout : Console
    , stderr : Console
    , fs : FileSystem
    , os : ProcessCapability
    , options : ReviewOptions
    }


type Msg
    = BuildCompleted (Result Problem Build.BuildData)
    | ReviewProcessEnded (Result Problem Process.Completed)


init : { env | stdout : Console, stderr : Console } -> { capabilities | fs : FileSystem, os : ProcessCapability } -> ReviewOptions -> ( Model, Cmd Msg )
init { stdout, stderr } { fs, os } options =
    let
        -- TODO Get from somewhere
        elmHomePath : String
        elmHomePath =
            "/Users/m1/.elm"
    in
    ( Model
        { stdout = stdout
        , stderr = stderr
        , fs = fs
        , os = os
        , options = options
        }
    , Build.build fs os options elmHomePath
        |> Task.attempt BuildCompleted
    )


update : Msg -> Model -> Cmd Msg
update msg (Model model) =
    case msg of
        BuildCompleted result ->
            case result of
                Ok { elmJsonPath, reviewElmJson, reviewAppPath, packagesLocation } ->
                    runReviewProcess model
                        { reviewAppPath = reviewAppPath
                        , reviewElmJson = reviewElmJson
                        , reviewFolder = Path.dirname elmJsonPath
                        , packagesLocation = packagesLocation
                        }

                Err problem ->
                    Problem.exit model.stderr model.options problem

        ReviewProcessEnded result ->
            case result of
                Ok completed ->
                    Cli.exit completed.exitCode

                Err problem ->
                    Problem.exit model.stderr model.options problem


runReviewProcess :
    ModelData
    ->
        { reviewAppPath : Path
        , reviewElmJson : Elm.Project.ApplicationInfo
        , reviewFolder : Path
        , packagesLocation : Path
        }
    -> Cmd Msg
runReviewProcess { os, options } { reviewAppPath, reviewElmJson, reviewFolder, packagesLocation } =
    let
        reviewAppFlags : List String
        reviewAppFlags =
            ("--review-folder=" ++ reviewFolder)
                :: ("--packages-location=" ++ packagesLocation)
                :: options.reviewAppFlags

        ( cmd, args ) =
            if options.debug then
                -- TODO Get host-cli from somewhere?
                ( "host-cli"
                , "-v" :: "--trust" :: reviewAppPath :: reviewAppFlags
                )

            else
                ( reviewAppPath, reviewAppFlags )
    in
    Process.run os
        cmd
        { args = args
        , cwd = Just (ProjectPaths.projectRoot options.projectPaths)
        , env = Nothing
        , stdin = Process.InheritStdin
        , stdout = Process.InheritStdout
        , stderr = Process.InheritStderr
        }
        |> Task.mapError
            (\err ->
                Problem.unexpectedError "when running the review application" (ElmRun.OsExtra.errorToString err)
                    |> Problem.withPath reviewAppPath
            )
        |> Task.attempt ReviewProcessEnded
