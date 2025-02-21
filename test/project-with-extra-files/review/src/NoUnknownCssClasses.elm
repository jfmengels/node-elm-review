module NoUnknownCssClasses exposing (rule)

import Dict exposing (Dict)
import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.Node as Node exposing (Node)
import Elm.Syntax.Range exposing (Range)
import Regex exposing (Regex)
import Review.FilePattern as FilePattern
import Review.Rule as Rule exposing (Rule)
import Set exposing (Set)

rule : Rule
rule =
    Rule.newModuleRuleSchema "NoUnknownCssClasses" initialContext
        |> Rule.withExtraFilesModuleVisitor cssFilesVisitor
            [ FilePattern.include "**/*.css" ]
        |> Rule.withExpressionEnterVisitor expressionVisitor
        |> Rule.fromModuleRuleSchema

type alias Context =
    { knownCssClasses : Set String
    }

initialContext : Context
initialContext =
    { knownCssClasses = Set.empty
    }

cssClassRegex : Regex
cssClassRegex =
    Regex.fromString "\\.([\\w-_]+)"
        |> Maybe.withDefault Regex.never

cssFilesVisitor : Dict String String -> Context -> Context
cssFilesVisitor files context =
    { knownCssClasses =
        files
            |> Dict.values
            |> List.concatMap (\cssSource -> Regex.find cssClassRegex cssSource)
            |> List.map (\m -> String.dropLeft 1 m.match)
            |> Set.fromList
    }

expressionVisitor : Node Expression -> Context -> ( List (Rule.Error {}), Context )
expressionVisitor node context =
    case Node.value node of
        Expression.Application [ function, firstArg ] ->
            case Node.value function of
                Expression.FunctionOrValue [ "Html", "Attributes" ] "class" ->
                    case Node.value firstArg of
                        Expression.Literal stringLiteral ->
                            ( stringLiteral
                                |> String.split " "
                                |> List.filterMap (checkForUnknownCssClass context.knownCssClasses (Node.range firstArg))
                            , context
                            )

                        _ ->
                            ( [], context )

                _ ->
                    ( [], context )

        _ ->
            ( [], context )

checkForUnknownCssClass : Set String -> Range -> String -> Maybe (Rule.Error {})
checkForUnknownCssClass knownCssClasses range class =
    if Set.member class knownCssClasses then
        Nothing

    else
        Just
            (Rule.error
                { message = "Unknown CSS class " ++ class
                , details =
                    [ "This CSS class does not appear in the project's `.css` files."
                    , "Could it be that you misspelled the name of the class, or that the class recently got removed?"
                    ]
                }
                range
            )