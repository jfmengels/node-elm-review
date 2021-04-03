module Elm.Review.AstCodec exposing (decode, encode)

import Elm.Review.Vendor.Serialize as S exposing (Codec)
import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Exposing exposing (ExposedType, Exposing(..), TopLevelExpose(..))
import Elm.Syntax.Expression exposing (CaseBlock, Expression(..), Function, FunctionImplementation, Lambda, LetBlock, LetDeclaration(..), RecordSetter)
import Elm.Syntax.File exposing (File)
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.Infix exposing (Infix, InfixDirection(..))
import Elm.Syntax.Module exposing (DefaultModuleData, EffectModuleData, Module(..))
import Elm.Syntax.Node exposing (Node(..))
import Elm.Syntax.Pattern exposing (Pattern(..), QualifiedNameRef)
import Elm.Syntax.Range exposing (Range)
import Elm.Syntax.Signature exposing (Signature)
import Elm.Syntax.Type exposing (Type, ValueConstructor)
import Elm.Syntax.TypeAlias exposing (TypeAlias)
import Elm.Syntax.TypeAnnotation exposing (RecordDefinition, TypeAnnotation(..))
import Json.Decode as Decode
import Json.Encode as Encode


encode : File -> Encode.Value
encode file_ =
    S.encodeToJson file file_


decode : Decode.Decoder File
decode =
    Decode.value
        |> Decode.andThen
            (\data ->
                case S.decodeFromJson file data of
                    Ok res ->
                        Decode.succeed res

                    Err _ ->
                        Decode.fail "Not a valid file"
            )


range : Codec e Range
range =
    S.record
        (\startRow startColumn endRow endColumn ->
            { start = { row = startRow, column = startColumn }
            , end = { row = endRow, column = endColumn }
            }
        )
        |> S.field (.start >> .row) S.int
        |> S.field (.start >> .column) S.int
        |> S.field (.end >> .row) S.int
        |> S.field (.end >> .column) S.int
        |> S.finishRecord


node : Codec e a -> Codec e (Node a)
node codec =
    S.record (\a b c d e -> Node { start = { row = a, column = b }, end = { row = c, column = d } } e)
        |> S.field (\(Node range_ _) -> range_.start.row) S.int
        |> S.field (\(Node range_ _) -> range_.start.column) S.int
        |> S.field (\(Node range_ _) -> range_.end.row) S.int
        |> S.field (\(Node range_ _) -> range_.end.column) S.int
        |> S.field (\(Node _ a) -> a) codec
        |> S.finishRecord


char : Codec DecodeError Char
char =
    S.string
        |> S.mapValid
            (\string ->
                case String.toList string of
                    head :: _ ->
                        Ok head

                    [] ->
                        Err InvalidChar
            )
            String.fromChar


type DecodeError
    = InvalidChar


infixDirection : Codec e InfixDirection
infixDirection =
    S.enum Left [ Right, Non ]


expression : Codec DecodeError Expression
expression =
    S.customType
        (\application operatorApplication functionOrValue integer floatable literal tuple parenthesized record listExpr unit ifBlock prefixOperator hex negation charExpr letExpr caseExpr lambdaExpr recordAccess recordAccessFunction recordUpdateExpr glsl operator value ->
            case value of
                Application a ->
                    application a

                OperatorApplication a b c d ->
                    operatorApplication a b c d

                FunctionOrValue a b ->
                    functionOrValue a b

                Integer a ->
                    integer a

                Floatable a ->
                    floatable a

                Literal a ->
                    literal a

                TupledExpression a ->
                    tuple a

                ParenthesizedExpression a ->
                    parenthesized a

                RecordExpr a ->
                    record a

                ListExpr a ->
                    listExpr a

                UnitExpr ->
                    unit

                PrefixOperator a ->
                    prefixOperator a

                Hex a ->
                    hex a

                Negation a ->
                    negation a

                CharLiteral a ->
                    charExpr a

                LetExpression a ->
                    letExpr a

                CaseExpression a ->
                    caseExpr a

                LambdaExpression a ->
                    lambdaExpr a

                IfBlock a b c ->
                    ifBlock a b c

                RecordAccess a b ->
                    recordAccess a b

                RecordAccessFunction a ->
                    recordAccessFunction a

                RecordUpdateExpression a b ->
                    recordUpdateExpr a b

                GLSLExpression a ->
                    glsl a

                Operator a ->
                    operator a
        )
        |> S.variant1 Application (S.list (node lazyExpression))
        |> S.variant4 OperatorApplication S.string infixDirection (node lazyExpression) (node lazyExpression)
        |> S.variant2 FunctionOrValue (S.list S.string) S.string
        |> S.variant1 Integer S.int
        |> S.variant1 Floatable S.float
        |> S.variant1 Literal S.string
        |> S.variant1 TupledExpression (S.list (node lazyExpression))
        |> S.variant1 ParenthesizedExpression (node lazyExpression)
        |> S.variant1 RecordExpr (S.list (node recordSetter))
        |> S.variant1 ListExpr (S.list (node lazyExpression))
        -- The expressions above should be the top 10 used expressions, in order
        -- to have them take a single less character in the resulting JSON
        |> S.variant0 UnitExpr
        |> S.variant3 IfBlock (node lazyExpression) (node lazyExpression) (node lazyExpression)
        |> S.variant1 PrefixOperator S.string
        |> S.variant1 Hex S.int
        |> S.variant1 Negation (node lazyExpression)
        |> S.variant1 CharLiteral char
        |> S.variant1 LetExpression letBlock
        |> S.variant1 CaseExpression caseBlock
        |> S.variant1 LambdaExpression lambda
        |> S.variant2 RecordAccess (node lazyExpression) (node S.string)
        |> S.variant1 RecordAccessFunction S.string
        |> S.variant2 RecordUpdateExpression (node S.string) (S.list (node recordSetter))
        |> S.variant1 GLSLExpression S.string
        |> S.variant1 Operator S.string
        |> S.finishCustomType


caseBlock : Codec DecodeError CaseBlock
caseBlock =
    S.record CaseBlock
        |> S.field .expression (node lazyExpression)
        |> S.field .cases (S.list (S.tuple (node pattern) (node lazyExpression)))
        |> S.finishRecord


lambda : Codec DecodeError Lambda
lambda =
    S.record Lambda
        |> S.field .args (S.list (node pattern))
        |> S.field .expression (node lazyExpression)
        |> S.finishRecord


recordSetter : Codec DecodeError RecordSetter
recordSetter =
    S.tuple (node S.string) (node lazyExpression)


letBlock : Codec DecodeError LetBlock
letBlock =
    S.record LetBlock
        |> S.field .declarations (S.list (node letDeclaration))
        |> S.field .expression (node lazyExpression)
        |> S.finishRecord


letDeclaration : Codec DecodeError LetDeclaration
letDeclaration =
    S.customType
        (\e0 e1 value ->
            case value of
                LetFunction a ->
                    e0 a

                LetDestructuring a b ->
                    e1 a b
        )
        |> S.variant1 LetFunction function
        |> S.variant2 LetDestructuring (node pattern) (node lazyExpression)
        |> S.finishCustomType


function : Codec DecodeError Function
function =
    S.record Function
        |> S.field .documentation (S.maybe (node S.string))
        |> S.field .signature (S.maybe (node signature))
        |> S.field .declaration (node functionImplementation)
        |> S.finishRecord


signature =
    S.record Signature
        |> S.field .name (node S.string)
        |> S.field .typeAnnotation (node typeAnnotation)
        |> S.finishRecord


typeAnnotation : Codec e TypeAnnotation
typeAnnotation =
    S.customType
        (\e0 e1 e2 e3 e4 e5 e6 value ->
            case value of
                GenericType a ->
                    e0 a

                Typed a b ->
                    e1 a b

                Unit ->
                    e2

                Tupled a ->
                    e3 a

                Record a ->
                    e4 a

                GenericRecord a b ->
                    e5 a b

                FunctionTypeAnnotation a b ->
                    e6 a b
        )
        |> S.variant1 GenericType S.string
        |> S.variant2 Typed (node (S.tuple (S.list S.string) S.string)) (S.list (node lazyTypeAnnotation))
        |> S.variant0 Unit
        |> S.variant1 Tupled (S.list (node lazyTypeAnnotation))
        |> S.variant1 Record recordDefinition
        |> S.variant2 GenericRecord (node S.string) (node recordDefinition)
        |> S.variant2 FunctionTypeAnnotation (node lazyTypeAnnotation) (node lazyTypeAnnotation)
        |> S.finishCustomType


lazyTypeAnnotation : Codec e TypeAnnotation
lazyTypeAnnotation =
    S.lazy (\() -> typeAnnotation)


recordDefinition : Codec e RecordDefinition
recordDefinition =
    S.list (node (S.tuple (node S.string) (node lazyTypeAnnotation)))


functionImplementation : Codec DecodeError FunctionImplementation
functionImplementation =
    S.record FunctionImplementation
        |> S.field .name (node S.string)
        |> S.field .arguments (S.list (node pattern))
        |> S.field .expression (node lazyExpression)
        |> S.finishRecord


pattern : Codec DecodeError Pattern
pattern =
    S.customType
        (\e0 e1 e2 e3 e4 e5 e6 e7 e8 e9 e10 e11 e12 e13 e14 value ->
            case value of
                AllPattern ->
                    e0

                UnitPattern ->
                    e1

                CharPattern a ->
                    e2 a

                StringPattern a ->
                    e3 a

                IntPattern a ->
                    e4 a

                HexPattern a ->
                    e5 a

                FloatPattern a ->
                    e6 a

                TuplePattern a ->
                    e7 a

                RecordPattern a ->
                    e8 a

                UnConsPattern a b ->
                    e9 a b

                ListPattern a ->
                    e10 a

                VarPattern a ->
                    e11 a

                NamedPattern a b ->
                    e12 a b

                AsPattern a b ->
                    e13 a b

                ParenthesizedPattern a ->
                    e14 a
        )
        |> S.variant0 AllPattern
        |> S.variant0 UnitPattern
        |> S.variant1 CharPattern char
        |> S.variant1 StringPattern S.string
        |> S.variant1 IntPattern S.int
        |> S.variant1 HexPattern S.int
        |> S.variant1 FloatPattern S.float
        |> S.variant1 TuplePattern (S.list (node lazyPattern))
        |> S.variant1 RecordPattern (S.list (node S.string))
        |> S.variant2 UnConsPattern (node lazyPattern) (node lazyPattern)
        |> S.variant1 ListPattern (S.list (node lazyPattern))
        |> S.variant1 VarPattern S.string
        |> S.variant2 NamedPattern qualifiedNameRef (S.list (node lazyPattern))
        |> S.variant2 AsPattern (node lazyPattern) (node S.string)
        |> S.variant1 ParenthesizedPattern (node lazyPattern)
        |> S.finishCustomType


lazyPattern : Codec DecodeError Pattern
lazyPattern =
    S.lazy (\() -> pattern)


qualifiedNameRef : Codec e QualifiedNameRef
qualifiedNameRef =
    S.record QualifiedNameRef
        |> S.field .moduleName (S.list S.string)
        |> S.field .name S.string
        |> S.finishRecord


lazyExpression : Codec DecodeError Expression
lazyExpression =
    S.lazy (\() -> expression)


file : Codec DecodeError File
file =
    S.record File
        |> S.field .moduleDefinition (node module_)
        |> S.field .imports (S.list (node import_))
        |> S.field .declarations (S.list (node declaration))
        |> S.field .comments (S.list (node S.string))
        |> S.finishRecord


import_ : Codec e Import
import_ =
    S.record Import
        |> S.field .moduleName (node (S.list S.string))
        |> S.field .moduleAlias (S.maybe (node (S.list S.string)))
        |> S.field .exposingList (S.maybe (node exposing_))
        |> S.finishRecord


module_ : Codec e Module
module_ =
    S.customType
        (\e0 e1 e2 value ->
            case value of
                NormalModule a ->
                    e0 a

                PortModule a ->
                    e1 a

                EffectModule a ->
                    e2 a
        )
        |> S.variant1 NormalModule defaultModuleData
        |> S.variant1 PortModule defaultModuleData
        |> S.variant1 EffectModule effectModuleData
        |> S.finishCustomType


effectModuleData : Codec e EffectModuleData
effectModuleData =
    S.record EffectModuleData
        |> S.field .moduleName (node (S.list S.string))
        |> S.field .exposingList (node exposing_)
        |> S.field .command (S.maybe (node S.string))
        |> S.field .subscription (S.maybe (node S.string))
        |> S.finishRecord


defaultModuleData : Codec e DefaultModuleData
defaultModuleData =
    S.record DefaultModuleData
        |> S.field .moduleName (node (S.list S.string))
        |> S.field .exposingList (node exposing_)
        |> S.finishRecord


exposing_ : Codec e Exposing
exposing_ =
    S.customType
        (\e0 e1 value ->
            case value of
                All a ->
                    e0 a

                Explicit a ->
                    e1 a
        )
        |> S.variant1 All range
        |> S.variant1 Explicit (S.list (node topLevelExpose))
        |> S.finishCustomType


topLevelExpose : Codec e TopLevelExpose
topLevelExpose =
    S.customType
        (\e0 e1 e2 e3 value ->
            case value of
                InfixExpose a ->
                    e0 a

                FunctionExpose a ->
                    e1 a

                TypeOrAliasExpose a ->
                    e2 a

                TypeExpose a ->
                    e3 a
        )
        |> S.variant1 InfixExpose S.string
        |> S.variant1 FunctionExpose S.string
        |> S.variant1 TypeOrAliasExpose S.string
        |> S.variant1 TypeExpose exposedType
        |> S.finishCustomType


exposedType : Codec e ExposedType
exposedType =
    S.record ExposedType
        |> S.field .name S.string
        |> S.field .open (S.maybe range)
        |> S.finishRecord


declaration : Codec DecodeError Declaration
declaration =
    S.customType
        (\e0 e1 e2 e3 e4 e5 value ->
            case value of
                FunctionDeclaration a ->
                    e0 a

                AliasDeclaration a ->
                    e1 a

                CustomTypeDeclaration a ->
                    e2 a

                PortDeclaration a ->
                    e3 a

                InfixDeclaration a ->
                    e4 a

                Destructuring a b ->
                    e5 a b
        )
        |> S.variant1 FunctionDeclaration function
        |> S.variant1 AliasDeclaration typeAlias
        |> S.variant1 CustomTypeDeclaration type_
        |> S.variant1 PortDeclaration signature
        |> S.variant1 InfixDeclaration infix_
        |> S.variant2 Destructuring (node pattern) (node expression)
        |> S.finishCustomType


infix_ : Codec e Infix
infix_ =
    S.record Infix
        |> S.field .direction (node infixDirection)
        |> S.field .precedence (node S.int)
        |> S.field .operator (node S.string)
        |> S.field .function (node S.string)
        |> S.finishRecord


typeAlias : Codec e TypeAlias
typeAlias =
    S.record TypeAlias
        |> S.field .documentation (S.maybe (node S.string))
        |> S.field .name (node S.string)
        |> S.field .generics (S.list (node S.string))
        |> S.field .typeAnnotation (node typeAnnotation)
        |> S.finishRecord


type_ : Codec e Type
type_ =
    S.record Type
        |> S.field .documentation (S.maybe (node S.string))
        |> S.field .name (node S.string)
        |> S.field .generics (S.list (node S.string))
        |> S.field .constructors (S.list (node valueConstructor))
        |> S.finishRecord


valueConstructor : Codec e ValueConstructor
valueConstructor =
    S.record ValueConstructor
        |> S.field .name (node S.string)
        |> S.field .arguments (S.list (node typeAnnotation))
        |> S.finishRecord
