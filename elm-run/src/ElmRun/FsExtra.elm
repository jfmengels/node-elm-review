module ElmRun.FsExtra exposing (errorToString)

import Fs exposing (FsError)


errorToString : FsError -> String
errorToString fsError =
    case fsError of
        Fs.NotFound path ->
            "File not found: " ++ path

        Fs.PermissionDenied ->
            "Permission denied"

        Fs.IoError msg ->
            "Unknown error: " ++ msg
