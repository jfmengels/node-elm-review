module Wrapper.ProjectPaths exposing
    ( ProjectPaths, from
    , projectRoot, reviewApp, buildFolder
    )

{-|

@docs ProjectPaths, from
@docs projectRoot, reviewApp, buildFolder

-}

import Elm.Review.CliVersion as CliVersion
import ElmReview.Path as Path exposing (Path)
import Wrapper.Hash as Hash exposing (Hash)


type ProjectPaths
    = ProjectPaths
        { projectRoot : Path
        , namespace : String
        }


from : { projectRoot : Path, namespace : String } -> ProjectPaths
from =
    ProjectPaths


projectRoot : ProjectPaths -> Path
projectRoot (ProjectPaths paths) =
    paths.projectRoot


reviewApp : ProjectPaths -> Hash -> Path
reviewApp projectPaths hash =
    Path.join
        [ elmStuff projectPaths
        , "review-applications"
        , Hash.toString hash
        ]


buildFolder : ProjectPaths -> Path -> Path
buildFolder projectPaths subFolder =
    Path.join
        [ elmStuff projectPaths
        , "build-project"
        , subFolder
        ]


elmStuff : ProjectPaths -> Path
elmStuff (ProjectPaths paths) =
    Path.join
        [ paths.projectRoot
        , "elm-stuff"
        , "generated-code"
        , "jfmengels"
        , "elm-review"
        , paths.namespace
        , CliVersion.version
        ]
