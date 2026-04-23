module Wrapper.ProjectPaths exposing
    ( ProjectPaths, from
    , projectRoot, reviewApp, buildFolder, templateElmModulePath
    )

{-|

@docs ProjectPaths, from
@docs projectRoot, reviewApp, buildFolder, templateElmModulePath

-}

import Elm.Review.CliVersion as CliVersion
import ElmReview.Path as Path exposing (Path)
import Wrapper.Hash as Hash exposing (Hash)
import Wrapper.RemoteTemplate exposing (RemoteTemplate)


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


templateElmModulePath :
    { options | projectPaths : ProjectPaths, debug : Bool }
    -> RemoteTemplate
    -> String
    -> Path
templateElmModulePath { projectPaths, debug } remoteTemplate commit =
    Path.join
        [ elmStuff projectPaths
        , "review-applications"
        , remoteTemplate.repoName
        , Maybe.withDefault "___root___" remoteTemplate.pathToFolder
        , String.concat
            [ commit
            , if debug then
                "-debug"

              else
                ""

            -- TODO?  localElmReview ? "-local" : ""
            ]
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
