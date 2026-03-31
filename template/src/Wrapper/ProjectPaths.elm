module Wrapper.ProjectPaths exposing (ProjectPaths, from)

{-|

@docs ProjectPaths, from

-}

import Wrapper.Path exposing (Path)


type ProjectPaths
    = ProjectPaths
        { projectRoot : Path
        , namespace : String
        }


from : { projectRoot : Path, namespace : String } -> ProjectPaths
from =
    ProjectPaths
