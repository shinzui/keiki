{-# LANGUAGE GADTs #-}
{-# LANGUAGE RoleAnnotations #-}
{-# LANGUAGE TypeAbstractions #-}
{-# LANGUAGE TypeFamilies #-}

-- | Internal constructors and operations for structural wire schemas.
--
-- The public surface is re-exported abstractly from "Keiki.Core". Keeping
-- these constructors in a hidden module prevents consumers from turning
-- names or casts into trusted replay evidence.
module Keiki.Internal.WireSchema
  ( WireSchema,
    WireFieldSchema,
    WireCtorPath,
    AppendWireFields,
    WireSchemaAvailability (..),
    WireHeadRelation (..),
    WireFieldAlignment (..),
    WireSchemaComparison (..),
    wireSchemaUnavailable,
    wireSchemaAvailability,
    trustedWireSchema,
    wireFieldsNil,
    wireFieldsCons,
    appendWireFieldSchema,
    wireCtorPathRoot,
    prefixWireCtorPathLeft,
    prefixWireCtorPathRight,
    genericPrefixWireCtorPathLeft,
    genericPrefixWireCtorPathRight,
    prefixWireSchemaLeft,
    prefixWireSchemaRight,
    compareWireSchemas,
    wireSchemaPrefixRelationForTesting,
  )
where

import Data.Kind (Type)
import Data.Typeable (Typeable)
import Type.Reflection (eqTypeRep, typeRep, type (:~~:) (HRefl))

-- | One structural step through either a Generic sum or an explicitly
-- checked 'Either' composition boundary.
data WireCtorPathStep
  = WireCtorPathLeft
  | WireCtorPathRight
  deriving stock (Eq, Show)

-- | A constructor's ordinal path through its carrier's sum tree.
--
-- The carrier is phantom because the type itself supplies the boundary;
-- callers cannot inspect or construct paths outside this hidden module.
newtype WireCtorPath co = WireCtorPath [WireCtorPathStep]

type role WireCtorPath nominal

-- | A typed, ordered description of a constructor's fields. Selector text
-- is diagnostic only; the spine position and 'Typeable' dictionary are the
-- proof evidence.
data WireFieldSchema fields where
  WireFieldsNil :: WireFieldSchema ()
  WireFieldsCons ::
    (Typeable field) =>
    Maybe String ->
    WireFieldSchema rest ->
    WireFieldSchema (field, rest)

type role WireFieldSchema nominal

-- | Type-level append for the nested-pair field encoding.
type family AppendWireFields (left :: Type) (right :: Type) :: Type where
  AppendWireFields () right = right
  AppendWireFields (field, rest) right =
    (field, AppendWireFields rest right)

-- | Structural evidence carried by one output wire constructor.
data WireSchema co fields where
  UnavailableWireSchema :: WireSchema co fields
  TrustedWireSchema ::
    WireCtorPath co ->
    WireFieldSchema fields ->
    WireSchema co fields

type role WireSchema nominal nominal

-- | Public observation of whether structural proof evidence is present.
data WireSchemaAvailability
  = WireSchemaTrusted
  | WireSchemaUnavailable
  deriving stock (Eq, Show)

-- | Public, proof-safe classification of two output heads.
data WireHeadRelation
  = WireHeadsStructurallyEqual
  | WireHeadsStructurallyDifferent
  | WireHeadsUnwitnessed
  deriving stock (Eq, Show)

-- | A position-by-position type alignment between two field spines.
data WireFieldAlignment left right where
  WireFieldsAlignedNil :: WireFieldAlignment () ()
  WireFieldsAlignedCons ::
    (Typeable field) =>
    WireFieldAlignment left right ->
    WireFieldAlignment (field, left) (field, right)

-- | Internal comparison retaining the typed alignment needed by symbolic
-- translation. The public classifier projects this to 'WireHeadRelation'.
data WireSchemaComparison left right where
  WireSchemasEqual ::
    WireFieldAlignment left right ->
    WireSchemaComparison left right
  WireSchemasDifferent :: WireSchemaComparison left right
  WireSchemasUnwitnessed :: WireSchemaComparison left right

-- | Explicitly mark a wire as lacking structural proof evidence.
wireSchemaUnavailable :: WireSchema co fields
wireSchemaUnavailable = UnavailableWireSchema

-- | Observe whether a schema is trusted without exposing its evidence.
wireSchemaAvailability :: WireSchema co fields -> WireSchemaAvailability
wireSchemaAvailability UnavailableWireSchema = WireSchemaUnavailable
wireSchemaAvailability TrustedWireSchema {} = WireSchemaTrusted

-- | Internal trusted-schema constructor used only by Generic derivation.
trustedWireSchema ::
  WireCtorPath co ->
  WireFieldSchema fields ->
  WireSchema co fields
trustedWireSchema = TrustedWireSchema

wireFieldsNil :: WireFieldSchema ()
wireFieldsNil = WireFieldsNil

wireFieldsCons ::
  (Typeable field) =>
  Maybe String ->
  WireFieldSchema rest ->
  WireFieldSchema (field, rest)
wireFieldsCons = WireFieldsCons

appendWireFieldSchema ::
  WireFieldSchema left ->
  WireFieldSchema right ->
  WireFieldSchema (AppendWireFields left right)
appendWireFieldSchema WireFieldsNil right = right
appendWireFieldSchema (WireFieldsCons label rest) right =
  WireFieldsCons label (appendWireFieldSchema rest right)

-- | The path of a constructor in a carrier with no enclosing sum node.
wireCtorPathRoot :: WireCtorPath co
wireCtorPathRoot = WireCtorPath []

prefixWireCtorPathLeft ::
  WireCtorPath co1 ->
  WireCtorPath (Either co1 co2)
prefixWireCtorPathLeft (WireCtorPath path) =
  WireCtorPath (WireCtorPathLeft : path)

prefixWireCtorPathRight ::
  WireCtorPath co2 ->
  WireCtorPath (Either co1 co2)
prefixWireCtorPathRight (WireCtorPath path) =
  WireCtorPath (WireCtorPathRight : path)

-- | Prefix a path while walking a 'GHC.Generics' sum. The result carrier is
-- supplied by the enclosing trusted schema; this less constrained operation
-- stays hidden with the Generic implementation.
genericPrefixWireCtorPathLeft :: WireCtorPath from -> WireCtorPath to
genericPrefixWireCtorPathLeft (WireCtorPath path) =
  WireCtorPath (WireCtorPathLeft : path)

-- | Right-arm counterpart of 'genericPrefixWireCtorPathLeft'.
genericPrefixWireCtorPathRight :: WireCtorPath from -> WireCtorPath to
genericPrefixWireCtorPathRight (WireCtorPath path) =
  WireCtorPath (WireCtorPathRight : path)

-- | Preserve a trusted schema while crossing a checked sum boundary.
prefixWireSchemaLeft ::
  WireSchema co1 fields ->
  WireSchema (Either co1 co2) fields
prefixWireSchemaLeft UnavailableWireSchema = UnavailableWireSchema
prefixWireSchemaLeft (TrustedWireSchema path fields) =
  TrustedWireSchema (prefixWireCtorPathLeft path) fields

-- | Preserve a trusted schema while crossing a checked sum boundary.
prefixWireSchemaRight ::
  WireSchema co2 fields ->
  WireSchema (Either co1 co2) fields
prefixWireSchemaRight UnavailableWireSchema = UnavailableWireSchema
prefixWireSchemaRight (TrustedWireSchema path fields) =
  TrustedWireSchema (prefixWireCtorPathRight path) fields

-- | Compare two trusted schemas. Paths count as different only when they
-- diverge at a common position. A proper-prefix relation remains
-- unwitnessed because the corresponding match sets can overlap.
compareWireSchemas ::
  WireSchema co left ->
  WireSchema co right ->
  WireSchemaComparison left right
compareWireSchemas UnavailableWireSchema _ = WireSchemasUnwitnessed
compareWireSchemas _ UnavailableWireSchema = WireSchemasUnwitnessed
compareWireSchemas
  (TrustedWireSchema (WireCtorPath leftPath) leftFields)
  (TrustedWireSchema (WireCtorPath rightPath) rightFields) =
    case comparePaths leftPath rightPath of
      PathsEqual ->
        maybe
          WireSchemasUnwitnessed
          WireSchemasEqual
          (alignWireFields leftFields rightFields)
      PathsDiverge -> WireSchemasDifferent
      PathsPrefixRelated -> WireSchemasUnwitnessed

-- | Regression observer for the otherwise-unforgeable proper-prefix case.
-- Exported through the testing internals of "Keiki.Core"; it grants no
-- ability to construct trusted evidence.
wireSchemaPrefixRelationForTesting :: WireHeadRelation
wireSchemaPrefixRelationForTesting =
  let root =
        TrustedWireSchema wireCtorPathRoot WireFieldsNil :: WireSchema () ()
      prefixed =
        TrustedWireSchema
          (genericPrefixWireCtorPathLeft wireCtorPathRoot)
          WireFieldsNil ::
          WireSchema () ()
   in case compareWireSchemas root prefixed of
        WireSchemasEqual _ -> WireHeadsStructurallyEqual
        WireSchemasDifferent -> WireHeadsStructurallyDifferent
        WireSchemasUnwitnessed -> WireHeadsUnwitnessed

data PathComparison
  = PathsEqual
  | PathsDiverge
  | PathsPrefixRelated

comparePaths :: [WireCtorPathStep] -> [WireCtorPathStep] -> PathComparison
comparePaths [] [] = PathsEqual
comparePaths [] (_ : _) = PathsPrefixRelated
comparePaths (_ : _) [] = PathsPrefixRelated
comparePaths (left : leftRest) (right : rightRest)
  | left /= right = PathsDiverge
  | otherwise = comparePaths leftRest rightRest

alignWireFields ::
  WireFieldSchema left ->
  WireFieldSchema right ->
  Maybe (WireFieldAlignment left right)
alignWireFields WireFieldsNil WireFieldsNil = Just WireFieldsAlignedNil
alignWireFields WireFieldsNil WireFieldsCons {} = Nothing
alignWireFields WireFieldsCons {} WireFieldsNil = Nothing
alignWireFields
  (WireFieldsCons @fieldLeft _ leftRest)
  (WireFieldsCons @fieldRight _ rightRest) =
    case eqTypeRep (typeRep @fieldLeft) (typeRep @fieldRight) of
      Just HRefl -> WireFieldsAlignedCons <$> alignWireFields leftRest rightRest
      Nothing -> Nothing
