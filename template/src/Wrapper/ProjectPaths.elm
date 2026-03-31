module Wrapper.ProjectPaths exposing
    ( ProjectPaths, from
    , reviewApp
    )

{-|

@docs ProjectPaths, from
@docs reviewApp

-}

import Elm.Review.CliVersion as CliVersion
import Wrapper.Hash as Hash exposing (Hash)
import Wrapper.Path as Path exposing (Path)


type ProjectPaths
    = ProjectPaths
        { projectRoot : Path
        , namespace : String
        }


from : { projectRoot : Path, namespace : String } -> ProjectPaths
from =
    ProjectPaths


reviewApp : ProjectPaths -> Hash -> Path
reviewApp projectPaths hash =
    Path.join
        [ elmStuff projectPaths
        , "review-applications"
        , Hash.toString hash
        ]


elmStuff : ProjectPaths -> Path
elmStuff (ProjectPaths { projectRoot, namespace }) =
    Path.join
        [ projectRoot
        , "elm-stuff"
        , "generated-code"
        , "jfmengels"
        , "elm-review"
        , namespace
        , CliVersion.version
        ]
