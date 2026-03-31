module Wrapper.CopyDirectory exposing (copyDirectory)

import Os exposing (ProcessCapability)
import Os.Process as Process exposing (ProcessError, defaultSpawnOptions)
import Task exposing (Task)


{-| Remove this when elm-run provides this functionality.
-}
copyDirectory : ProcessCapability -> { from : String, to : String } -> Task ProcessError ()
copyDirectory os { from, to } =
    Process.run os
        "cp"
        { defaultSpawnOptions
            | args = [ "-R", from, to ]
            , stdout = Process.NullStdout
            , stderr = Process.NullStderr
        }
        |> Task.map (\_ -> ())
