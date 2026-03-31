module Wrapper.FolderHash exposing (hashFiles)

import Task exposing (Task)
import Wrapper.Hash as Hash exposing (Hash)


hashFiles : String -> Task x Hash
hashFiles input =
    Task.succeed (Hash.fromString ("<hash for " ++ input ++ ">"))
