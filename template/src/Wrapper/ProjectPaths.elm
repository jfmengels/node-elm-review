module Wrapper.ProjectPaths exposing
    ( ProjectPaths, from
    , projectRoot, reviewApp, buildFolder
    , resultCacheFolder
    )

{-|

@docs ProjectPaths, from
@docs projectRoot, reviewApp, buildFolder

-}

import Elm.Review.CliVersion as CliVersion
import ElmReview.Path as Path exposing (Path)
import Wrapper.Hash as Hash exposing (Hash)
import Wrapper.OutputTarget as OutputTarget exposing (OutputTarget)


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


reviewApp : ProjectPaths -> OutputTarget -> Bool -> Hash -> Path
reviewApp projectPaths outputTarget debug hash =
    let
        extension : String
        extension =
            case outputTarget of
                OutputTarget.JavaScriptTarget ->
                    ".js"

                OutputTarget.ElmRunTarget ->
                    ""

        debugSuffix : String
        debugSuffix =
            if debug then
                "-debug"

            else
                ""
    in
    Path.join
        [ elmStuff projectPaths
        , "review-applications"
        , Hash.toString hash ++ debugSuffix ++ extension
        ]


buildFolder : ProjectPaths -> Path -> Path
buildFolder projectPaths subFolder =
    Path.join
        [ elmStuff projectPaths
        , "build-project"
        , subFolder
        ]


resultCacheFolder : ProjectPaths -> Hash -> Path
resultCacheFolder projectPaths hash =
    Path.join
        [ elmStuff projectPaths
        , "result-cache"
        , Hash.toString hash
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
