module Wrapper.FetchRemoteTemplate exposing (checkoutGitRepository)

{-|

@docs checkoutGitRepository

-}

import ElmReview.Color exposing (Color(..), Colorize)
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem, ProblemSimple)
import ElmRun.OsExtra as OsExtra
import ElmRun.TaskExtra as TaskExtra
import Fs exposing (FileSystem)
import Os exposing (ProcessCapability)
import Os.Process as Process exposing (ProcessError)
import Task exposing (Task)
import Wrapper.RemoteTemplate exposing (RemoteTemplate)


type alias CommitHash =
    String


checkoutGitRepository : FileSystem -> ProcessCapability -> RemoteTemplate -> Bool -> Task Problem Path
checkoutGitRepository fs os remoteTemplate debug =
    let
        repoFolder : Path
        repoFolder =
            Path.join
                [ -- TODO Use HOME and/or XDG_CACHE_HOME
                  "/Users/m1/.cache/elm-review/templates"
                , remoteTemplate.repoName
                ]

        git : List String -> Task String ()
        git args =
            Process.run os
                "git"
                { args = args
                , cwd = Just repoFolder
                , env = Nothing
                , stdin = Process.NullStdin
                , stdout = stdoutSpec debug
                , stderr = stderrSpec debug
                }
                |> Task.mapError (\error -> "$ git " ++ String.join " " args ++ "\n\n" ++ OsExtra.errorToString error)
                |> Task.map (\_ -> ())

        {- Same as the `git` function but captures and returns the stdout output. -}
        gitCapture : List String -> Task String String
        gitCapture args =
            Process.run os
                "git"
                { args = args
                , cwd = Just repoFolder
                , env = Nothing
                , stdin = Process.NullStdin
                , stdout = Process.CaptureStdout { maxBytes = 1024, onOverflow = Process.TruncateOutput }
                , stderr = Process.CaptureStderr { maxBytes = 1024, onOverflow = Process.TruncateOutput }
                }
                |> Task.mapError OsExtra.errorToString
                |> Task.andThen
                    (\result ->
                        if result.exitCode == 0 then
                            Task.succeed (Maybe.withDefault "" result.stdout)

                        else
                            Task.fail (Maybe.withDefault "No process output." result.stderr)
                    )
                |> Task.mapError (\error -> "$ git " ++ String.join " " args ++ "\n\n" ++ error)
    in
    Task.map2 (\() () -> Path.join2 repoFolder (Maybe.withDefault "." remoteTemplate.pathToFolder))
        (createRepoIfNecessary fs git remoteTemplate repoFolder)
        (pullAndCheckout { git = git, gitCapture = gitCapture } remoteTemplate)


stdoutSpec : Bool -> Process.StdoutSpec
stdoutSpec debug =
    if debug then
        Process.InheritStdout

    else
        Process.NullStdout


stderrSpec : Bool -> Process.StderrSpec
stderrSpec debug =
    if debug then
        Process.InheritStderr

    else
        Process.NullStderr


createRepoIfNecessary : FileSystem -> (List String -> Task String ()) -> RemoteTemplate -> Path -> Task Problem ()
createRepoIfNecessary fs git remoteTemplate repoFolder =
    Fs.stat fs (Path.join2 repoFolder ".git")
        |> TaskExtra.toResultTask
        |> Task.andThen
            (\stat ->
                case stat of
                    Ok _ ->
                        Task.succeed ()

                    Err () ->
                        -- First time checkout out the repo, let's create it
                        createRepo fs git remoteTemplate repoFolder
            )


createRepo : FileSystem -> (List String -> Task String ()) -> RemoteTemplate -> Path -> Task Problem ()
createRepo fs git remoteTemplate repoFolder =
    let
        repository : String
        repository =
            "git@github.com:" ++ remoteTemplate.repoName ++ ".git"
    in
    TaskExtra.sequence
        [ Fs.createDirectory fs repoFolder
            |> Task.onError (\_ -> Task.succeed ())
        , git [ "init" ]

        -- TODO
        -- , git [ "sparse-checkout", "set", "--no-cone", "'!/*'", "'**/*.elm'", "'**/elm.json'", "'!**/tests/**/*.elm'" ]
        , git [ "remote", "add", "origin", repository ]
        ]
        |> Task.mapError (\error -> Problem.unexpectedError "while checking out the template" error)


nextIndex : String -> String -> Maybe Int
nextIndex needle string =
    String.indexes needle string |> List.head


type alias Git =
    { git : List String -> Task String ()
    , gitCapture : List String -> Task String String
    }


pullAndCheckout : Git -> RemoteTemplate -> Task Problem ()
pullAndCheckout { git, gitCapture } remoteTemplate =
    remoteTemplate.reference
        |> TaskExtra.otherwise (\() -> findRemoteDefaultBranch gitCapture remoteTemplate)
        |> Task.andThen
            (\reference ->
                Task.map2 (\() () -> ())
                    (git [ "fetch", "origin", reference, "--depth=1" ]
                        |> Task.mapError
                            (\error ->
                                let
                                    searchableError : String
                                    searchableError =
                                        String.toLower error
                                in
                                if String.contains "repository not found" searchableError then
                                    { title = "REPOSITORY NOT FOUND"
                                    , message = \c -> "I could not find the " ++ c Yellow remoteTemplate.repoName ++ """ repository.

Check the spelling and make sure it is a public repository, as I can't work with private ones at the moment."""
                                    }
                                        |> Problem.from

                                else if String.contains "couldn't find remote ref" searchableError then
                                    { title = "BRANCH OR COMMIT NOT FOUND"
                                    , message = \c -> "I found the " ++ c Yellow remoteTemplate.repoName ++ " repository, but I could not find the branch or commit " ++ c Yellow reference ++ """.

Please check the spelling and make sure it has been pushed."""
                                    }
                                        |> Problem.from

                                else
                                    Problem.unexpectedError ("while fetching the contents of " ++ reference ++ " in the template") error
                            )
                    )
                    (git [ "switch", "--discard-changes", reference ]
                        |> Task.mapError (\error -> Problem.unexpectedError "while checking out the template's code" error)
                    )
            )


findRemoteDefaultBranch : (List String -> Task String String) -> RemoteTemplate -> Task Problem String
findRemoteDefaultBranch gitCapture remoteTemplate =
    gitCapture [ "remote", "show", "origin" ]
        |> Task.mapError
            (\error ->
                if String.contains "repository not found" (String.toLower (Debug.log "error" error)) then
                    { title = "REPOSITORY NOT FOUND"
                    , message = \c -> "I could not find the " ++ c Yellow remoteTemplate.repoName ++ """ repository.

Check the spelling and make sure it is a public repository, as I can't work with private ones at the moment."""
                    }
                        |> Problem.from

                else
                    Problem.unexpectedError "while trying to figure out the remote template's default Git branch" error
            )
        |> Task.andThen (\output -> headBranchName output |> TaskExtra.resultToTask)


headBranchName : String -> Result Problem String
headBranchName output =
    let
        searchTarget : String
        searchTarget =
            "HEAD branch: "

        maybeBranchName : Maybe String
        maybeBranchName =
            nextIndex searchTarget output
                |> Maybe.andThen
                    (\index ->
                        let
                            str : String
                            str =
                                output |> String.dropLeft (index + String.length searchTarget)
                        in
                        nextIndex "\n" str
                            |> Maybe.map (\endIndex -> String.left endIndex str)
                    )
    in
    case maybeBranchName of
        Just branchName ->
            Ok branchName

        Nothing ->
            { title = "COULD NOT FIGURE DEFAULT BRANCH FOR REMOTE"
            , message = \c -> headBranchNotFoundError searchTarget output c
            }
                |> Problem.from
                |> Err


headBranchNotFoundError : String -> String -> Colorize -> String
headBranchNotFoundError searchTarget output c =
    "Since you did not specify a branch or commit when using " ++ c Cyan "--template" ++ """, I am trying to figure that out. In doing so, I used Git to figure that information and got a response.
            
I was looking for a line containing the string '""" ++ c Yellow searchTarget ++ """' but could not find it. Here is the full response:

""" ++ output
