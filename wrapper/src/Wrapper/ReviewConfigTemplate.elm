module Wrapper.ReviewConfigTemplate exposing (create)

import Elm.Version exposing (Version)
import ElmReview.Path as Path exposing (Path)
import ElmRun.FsExtra as FsExtra
import Fs exposing (FileSystem, FsError)
import Task exposing (Task)


create : FileSystem -> Version -> Path -> Maybe String -> Task FsError ()
create fs elmVersion directory maybeRuleName =
    Task.sequence
        [ FsExtra.createFileAndItsDirectory
            fs
            (Path.join2 directory "src/ReviewConfig.elm")
            (reviewConfig maybeRuleName)
        , Fs.writeTextFile
            fs
            (Path.join2 directory "elm.json")
            (createNewReviewElmJson elmVersion (maybeRuleName /= Nothing))
        ]
        |> Task.map (\_ -> ())


createNewReviewElmJson : Version -> Bool -> String
createNewReviewElmJson elmVersion addParentSourceDirectory =
    let
        parentSources : String
        parentSources =
            if addParentSourceDirectory then
                ",\n        \"../src\""

            else
                ""
    in
    -- TODO Update dependencies to the latest version
    -- Maybe avoid this when options.forTests == True
    -- and have a test just checking that without tests the elm.json file is different but valid?
    -- TODO Make sure jfmengels/elm-review is always at least MinVersion.supportedRange
    """{
    "type": "application",
    "source-directories": [
        "src\"""" ++ parentSources ++ """
    ],
    "elm-version": \"""" ++ Elm.Version.toString elmVersion ++ """",
    "dependencies": {
        "direct": {
            "elm/core": "1.0.5",
            "jfmengels/elm-review": "2.16.6",
            "stil4m/elm-syntax": "7.3.9"
        },
        "indirect": {
            "elm/bytes": "1.0.8",
            "elm/html": "1.0.1",
            "elm/json": "1.1.4",
            "elm/parser": "1.1.0",
            "elm/project-metadata-utils": "1.0.2",
            "elm/random": "1.0.0",
            "elm/regex": "1.0.0",
            "elm/time": "1.0.0",
            "elm/virtual-dom": "1.0.5",
            "elm-explorations/test": "2.2.1",
            "rtfeldman/elm-hex": "1.0.0",
            "stil4m/structured-writer": "1.0.3"
        }
    },
    "test-dependencies": {
        "direct": {
            "elm-explorations/test": "2.2.1"
        },
        "indirect": {}
    }
}
"""


initTemplatePath : Path -> Path
initTemplatePath templatePath =
    Path.join2
        -- TODO Use path relative to this binary
        "/Users/m1/dev/node-elm-review/init-templates"
        templatePath


reviewConfig : Maybe String -> String
reviewConfig maybeRuleName =
    let
        ( import_, config ) =
            case maybeRuleName of
                Just ruleName ->
                    ( "\nimport " ++ ruleName
                    , "[ " ++ ruleName ++ ".rule\n    ]"
                    )

                Nothing ->
                    ( "", "[]" )
    in
    """module ReviewConfig exposing (config)

{-| Do not rename the ReviewConfig module or the config function, because
`elm-review` will look for these.

To add packages that contain rules, add them to this review project using

    `elm install author/packagename`

when inside the directory containing this file.

-}
""" ++ import_ ++ """
import Review.Rule exposing (Rule)


config : List Rule
config =
    """ ++ config ++ "\n"
