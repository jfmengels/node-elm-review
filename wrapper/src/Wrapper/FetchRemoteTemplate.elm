module Wrapper.FetchRemoteTemplate exposing (checkoutGitRepository)

{-|

@docs checkoutGitRepository

-}

import ElmReview.Color exposing (Color(..), Colorize)
import ElmReview.Path as Path exposing (Path)
import ElmReview.Problem as Problem exposing (Problem)
import ElmRun.ProcessExtra as ProcessExtra
import ElmRun.TaskExtra as TaskExtra
import Fs exposing (FileSystem)
import Os exposing (ProcessCapability)
import Os.Process as Process
import Task exposing (Task)
import Wrapper.RemoteTemplate exposing (RemoteTemplate)


checkoutGitRepository : FileSystem -> ProcessCapability -> Bool -> RemoteTemplate -> Bool -> Task Problem Path
checkoutGitRepository fs os offline remoteTemplate debug =
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
            ProcessExtra.runButFailOnError os
                "git"
                { args = args
                , cwd = Just repoFolder
                , env = Nothing
                , stdin = Process.NullStdin
                , stdout = ProcessExtra.stdoutSpec debug
                , stderr = Process.CaptureStderr { maxBytes = 1024, onOverflow = Process.TruncateOutput }
                }
                |> Task.mapError (\error -> fromGitError args error)
                |> Task.map (\_ -> ())

        {- Same as the `git` function but captures and returns the stdout output. -}
        gitCapture : List String -> Task String String
        gitCapture args =
            ProcessExtra.runButFailOnError os
                "git"
                { args = args
                , cwd = Just repoFolder
                , env = Nothing
                , stdin = Process.NullStdin
                , stdout = Process.CaptureStdout { maxBytes = 1024, onOverflow = Process.TruncateOutput }
                , stderr = Process.CaptureStderr { maxBytes = 1024, onOverflow = Process.TruncateOutput }
                }
                |> Task.mapError (\error -> fromGitError args error)
                |> Task.map (\result -> Maybe.withDefault "" result.stdout)
    in
    Task.map2 (\() () -> Path.join2 repoFolder (Maybe.withDefault "." remoteTemplate.pathToFolder))
        (createRepoIfNecessary fs git offline remoteTemplate repoFolder)
        (pullAndCheckout { git = git, gitCapture = gitCapture } offline remoteTemplate)


fromGitError : List String -> ProcessExtra.SpawnError -> String
fromGitError args error =
    let
        errorDetails : String
        errorDetails =
            case error of
                ProcessExtra.ProcessRunError processError ->
                    ProcessExtra.errorToString processError

                ProcessExtra.CommandNotFound ->
                    "Command `git` not found"

                ProcessExtra.CommandFailed completed ->
                    Maybe.withDefault "No Git output." completed.stderr
    in
    "$ git " ++ String.join " " args ++ "\n\n" ++ errorDetails


createRepoIfNecessary : FileSystem -> (List String -> Task String ()) -> Bool -> RemoteTemplate -> Path -> Task Problem ()
createRepoIfNecessary fs git offline remoteTemplate repoFolder =
    Fs.stat fs (Path.join2 repoFolder ".git")
        |> TaskExtra.toResultTask
        |> Task.andThen
            (\stat ->
                case stat of
                    Ok _ ->
                        Task.succeed ()

                    Err _ ->
                        -- First time checkout out the repo, let's create it
                        if offline then
                            { title = "BRANCH OR COMMIT NOT FOUND"
                            , message = \c -> "You requested to run with the template at the " ++ c Yellow remoteTemplate.repoName ++ " but this is the first time using it. I therefore require network access, but you requested to run " ++ c Cyan "--offline" ++ """.
                            
Please acquire network access and re-run without """ ++ c Cyan "--offline" ++ ", or select another configuration to use."
                            }
                                |> Problem.from Problem.Unrecoverable
                                |> Task.fail

                        else
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

        -- TODO Support sparse-checkout to check out less files
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


pullAndCheckout : Git -> Bool -> RemoteTemplate -> Task Problem ()
pullAndCheckout { git, gitCapture } offline remoteTemplate =
    if offline then
        getDefaultBranchFromLocalInformation gitCapture
            |> Task.andThen (\reference -> switchToBranch git reference)

    else
        remoteTemplate.reference
            |> TaskExtra.otherwise (\() -> findRemoteDefaultBranch gitCapture remoteTemplate)
            |> Task.andThen
                (\reference ->
                    Task.map2 (\() () -> ())
                        (fetchGitReference git reference remoteTemplate)
                        (switchToBranch git reference)
                )


switchToBranch : (List String -> Task String ()) -> String -> Task Problem ()
switchToBranch git reference =
    git [ "switch", "--discard-changes", reference ]
        |> Task.mapError (\error -> Problem.unexpectedError "while checking out the template's code" error)


fetchGitReference : (List String -> Task String ()) -> String -> RemoteTemplate -> Task Problem ()
fetchGitReference git reference remoteTemplate =
    git [ "fetch", "origin", reference, "--depth=1" ]
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
                        |> Problem.from Problem.Unrecoverable

                else if String.contains "couldn't find remote ref" searchableError then
                    { title = "BRANCH OR COMMIT NOT FOUND"
                    , message = \c -> "I found the " ++ c Yellow remoteTemplate.repoName ++ " repository, but I could not find the branch or commit " ++ c Yellow reference ++ """.

Please check the spelling and make sure it has been pushed."""
                    }
                        |> Problem.from Problem.Unrecoverable

                else
                    Problem.unexpectedError ("while fetching the contents of " ++ reference ++ " in the template") error
            )


findRemoteDefaultBranch : (List String -> Task String String) -> RemoteTemplate -> Task Problem String
findRemoteDefaultBranch gitCapture remoteTemplate =
    gitCapture [ "remote", "show", "origin" ]
        |> Task.onError
            (\error ->
                if String.contains "repository not found" (String.toLower error) then
                    { title = "REPOSITORY NOT FOUND"
                    , message = \c -> "I could not find the " ++ c Yellow remoteTemplate.repoName ++ """ repository.

Check the spelling and make sure it is a public repository, as I can't work with private ones at the moment."""
                    }
                        |> Problem.from Problem.Unrecoverable
                        |> Task.fail

                else
                    getDefaultBranchFromLocalInformation gitCapture
                        |> Task.mapError (\_ -> Problem.unexpectedError "while trying to figure out the remote template's default Git branch" error)
            )
        |> Task.andThen (\output -> headBranchName output |> TaskExtra.fromResult)


getDefaultBranchFromLocalInformation : (List String -> Task String String) -> Task Problem String
getDefaultBranchFromLocalInformation gitCapture =
    gitCapture [ "symbolic-ref", "--short", "refs/remotes/origin/HEAD" ]
        |> Task.mapError
            (\error ->
                Problem.unexpectedError "while trying to figure out the remote template's default Git branch offline" error
            )
        -- Output is "origin/<branchname>\n"
        |> Task.map (\output -> String.dropLeft 7 (String.trim output))


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
                |> Problem.from Problem.Unrecoverable
                |> Err


headBranchNotFoundError : String -> String -> Colorize -> String
headBranchNotFoundError searchTarget output c =
    "Since you did not specify a branch or commit when using " ++ c Cyan "--template" ++ """, I am trying to figure that out. In doing so, I used Git to figure that information and got a response.
            
I was looking for a line containing the string '""" ++ c Yellow searchTarget ++ """' but could not find it. Here is the full response:

""" ++ output
