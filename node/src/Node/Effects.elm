module Node.Effects exposing (effects, subEffects)

import Elm.Review.Testable exposing (Effects)
import Elm.Review.Testable.FileWatchData exposing (FileEvent, WatchOptions)
import Elm.Review.Testable.TSub exposing (SubEffects)
import ElmReview.Path exposing (Path)


effects : Effects
effects =
    { -- File system
      readTextFile = \path -> Debug.todo "readTextFile"
    , writeTextFile = \path string -> Debug.todo "writeTextFile"
    , stat = \path -> Debug.todo "stat"
    , deleteFile = \path -> Debug.todo "deleteFile"
    , createDirectory = \path -> Debug.todo "createDirectory"
    , removeDirectory = \path -> Debug.todo "removeDirectory"
    , copyDirectory = \path -> Debug.todo "copyDirectory"
    , walkTree = \path pattern matchKind -> Debug.todo "walkTree"

    -- Http
    , httpGet = \url -> Debug.todo "httpGet"

    -- Stdin / Stdout
    , readKey = \() -> Debug.todo "readKey"
    , println = \console string -> Debug.todo "println"
    , exit = \code -> Debug.todo "exit"

    -- Process
    , runProcess = \command options -> Debug.todo "runProcess"
    , spawnProcess = \command options -> Debug.todo "spawnProcess"
    , waitProcess = \pid -> Debug.todo "waitProcess"
    , killProcess = \pid signal -> Debug.todo "killProcess"
    }


subEffects : SubEffects msg
subEffects =
    { watchFiles = watchFiles
    }


watchFiles : Path -> WatchOptions -> (FileEvent -> msg) -> Sub msg
watchFiles path watchOptions toMsg =
    Sub.none
