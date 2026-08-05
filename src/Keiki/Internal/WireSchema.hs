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
    InCtorSchema,
    InCtorFieldSchema,
    WireCtorPath,
    AppendWireFields,
    AppendInCtorFields,
    WireSchemaAvailability (..),
    InCtorSchemaAvailability (..),
    WireHeadRelation (..),
    InputHeadRelation (..),
    WireFieldAlignment (..),
    WireSchemaComparison (..),
    InCtorFieldAlignment (..),
    InCtorSchemaComparison (..),
    InWireFieldAlignment (..),
    InWireSchemaComparison (..),
    wireSchemaUnavailable,
    wireSchemaAvailability,
    inCtorSchemaUnavailable,
    inCtorSchemaAvailability,
    trustedWireSchema,
    trustedInCtorSchema,
    compositionOnlyWireSchema,
    compositionOnlyInCtorSchema,
    wireFieldsNil,
    wireFieldsCons,
    inCtorFieldsNil,
    inCtorFieldsCons,
    appendWireFieldSchema,
    appendInCtorFieldSchema,
    wireCtorPathRoot,
    prefixWireCtorPathLeft,
    prefixWireCtorPathRight,
    genericPrefixWireCtorPathLeft,
    genericPrefixWireCtorPathRight,
    prefixWireSchemaLeft,
    prefixWireSchemaRight,
    prefixInCtorSchemaLeft,
    prefixInCtorSchemaRight,
    compareWireSchemas,
    compareInCtorSchemas,
    compareInCtorWireSchemas,
    inCtorSchemaPath,
    wireSchemaPrefixRelationForTesting,
    inCtorSchemaPrefixRelationForTesting,
  )
where

import Data.Kind (Type)
import Data.Typeable (Typeable)
import GHC.TypeLits (Symbol)
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

-- | A typed, ordered description of an input constructor's slots. Slot
-- labels remain diagnostic; the spine position and 'Typeable' dictionary
-- are the proof evidence used to align an input read with an output field.
data InCtorFieldSchema (fields :: [(Symbol, Type)]) where
  InCtorFieldsNil :: InCtorFieldSchema '[]
  InCtorFieldsCons ::
    (Typeable field) =>
    Maybe String ->
    InCtorFieldSchema rest ->
    InCtorFieldSchema ('(name, field) ': rest)

type role InCtorFieldSchema nominal

-- | Typed path from an outer composition carrier back to the one payload type
-- introduced by the polymorphic identity boundary. The root pins payload and
-- carrier to the same type; each prefix records which 'Either' arm preserved
-- that payload. Lockstep comparison can therefore recover payload equality
-- from equal spines without a cast or a 'Typeable' dictionary.
data CompositionOnlySpine carrier payload where
  CompositionOnlyRoot :: CompositionOnlySpine carrier carrier
  CompositionOnlyLeft ::
    CompositionOnlySpine carrier payload ->
    CompositionOnlySpine (Either carrier other) payload
  CompositionOnlyRight ::
    CompositionOnlySpine carrier payload ->
    CompositionOnlySpine (Either other carrier) payload

type role CompositionOnlySpine nominal nominal

-- | Type-level append for the nested-pair field encoding.
type family AppendWireFields (left :: Type) (right :: Type) :: Type where
  AppendWireFields () right = right
  AppendWireFields (field, rest) right =
    (field, AppendWireFields rest right)

-- | Type-level append for input slot lists. Kept private so the schema
-- builder can combine Generic product spines without depending on
-- "Keiki.Core" and creating an import cycle.
type family
  AppendInCtorFields
    (left :: [(Symbol, Type)])
    (right :: [(Symbol, Type)]) ::
    [(Symbol, Type)]
  where
  AppendInCtorFields '[] right = right
  AppendInCtorFields (field ': rest) right =
    field ': AppendInCtorFields rest right

-- | Structural evidence carried by one output wire constructor.
data WireSchema co fields where
  UnavailableWireSchema :: WireSchema co fields
  CompositionOnlyWireSchema ::
    CompositionOnlySpine co field ->
    WireSchema co (field, ())
  TrustedWireSchema ::
    WireCtorPath co ->
    WireFieldSchema fields ->
    WireSchema co fields

type role WireSchema nominal nominal

-- | Structural evidence carried by one input constructor.
data InCtorSchema ci (fields :: [(Symbol, Type)]) where
  UnavailableInCtorSchema :: InCtorSchema ci fields
  CompositionOnlyInCtorSchema ::
    CompositionOnlySpine ci field ->
    InCtorSchema ci '[ '("payload", field)]
  TrustedInCtorSchema ::
    WireCtorPath ci ->
    InCtorFieldSchema fields ->
    InCtorSchema ci fields

type role InCtorSchema nominal nominal

-- | Public observation of whether structural proof evidence is present.
data WireSchemaAvailability
  = WireSchemaTrusted
  | WireSchemaUnavailable
  deriving stock (Eq, Show)

-- | Public observation of whether input-constructor proof evidence exists.
data InCtorSchemaAvailability
  = InCtorSchemaTrusted
  | InCtorSchemaUnavailable
  deriving stock (Eq, Show)

-- | Public, proof-safe classification of two output heads.
data WireHeadRelation
  = WireHeadsStructurallyEqual
  | WireHeadsStructurallyDifferent
  | WireHeadsUnwitnessed
  deriving stock (Eq, Show)

-- | Public, proof-safe classification of two input constructors.
data InputHeadRelation
  = InputHeadsStructurallyEqual
  | InputHeadsStructurallyDifferent
  | InputHeadsUnwitnessed
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

-- | Position-by-position alignment between two input slot spines.
data InCtorFieldAlignment left right where
  InCtorFieldsAlignedNil :: InCtorFieldAlignment '[] '[]
  InCtorFieldsAlignedCons ::
    (Typeable field) =>
    InCtorFieldAlignment left right ->
    InCtorFieldAlignment ('(leftName, field) ': left) ('(rightName, field) ': right)

-- | Internal comparison retaining the input-field alignment witness.
data InCtorSchemaComparison left right where
  InCtorSchemasEqual ::
    InCtorFieldAlignment left right ->
    InCtorSchemaComparison left right
  InCtorSchemasDifferent :: InCtorSchemaComparison left right
  InCtorSchemasUnwitnessed :: InCtorSchemaComparison left right

-- | Position-by-position alignment from input slots to an output wire's
-- nested-pair fields. This is the typed bridge used by composition.
data InWireFieldAlignment inputFields wireFields where
  InWireFieldsAlignedNil :: InWireFieldAlignment '[] ()
  InWireFieldsAlignedCons ::
    InWireFieldAlignment inputRest wireRest ->
    InWireFieldAlignment ('(name, field) ': inputRest) (field, wireRest)

-- | Checked structural relationship between an input constructor and an
-- output wire constructor over the same carrier.
data InWireSchemaComparison inputFields wireFields where
  InWireSchemasEqual ::
    InWireFieldAlignment inputFields wireFields ->
    InWireSchemaComparison inputFields wireFields
  InWireSchemasDifferent :: InWireSchemaComparison inputFields wireFields
  InWireSchemasUnwitnessed :: InWireSchemaComparison inputFields wireFields

-- | Explicitly mark a wire as lacking structural proof evidence.
wireSchemaUnavailable :: WireSchema co fields
wireSchemaUnavailable = UnavailableWireSchema

-- | Observe whether a schema is trusted without exposing its evidence.
wireSchemaAvailability :: WireSchema co fields -> WireSchemaAvailability
wireSchemaAvailability UnavailableWireSchema = WireSchemaUnavailable
wireSchemaAvailability CompositionOnlyWireSchema {} = WireSchemaUnavailable
wireSchemaAvailability TrustedWireSchema {} = WireSchemaTrusted

-- | Explicitly mark an input constructor as lacking structural evidence.
inCtorSchemaUnavailable :: InCtorSchema ci fields
inCtorSchemaUnavailable = UnavailableInCtorSchema

-- | Observe whether an input schema is trusted without exposing evidence.
inCtorSchemaAvailability ::
  InCtorSchema ci fields ->
  InCtorSchemaAvailability
inCtorSchemaAvailability UnavailableInCtorSchema = InCtorSchemaUnavailable
inCtorSchemaAvailability CompositionOnlyInCtorSchema {} = InCtorSchemaUnavailable
inCtorSchemaAvailability TrustedInCtorSchema {} = InCtorSchemaTrusted

-- | Internal trusted-schema constructor used only by Generic derivation.
trustedWireSchema ::
  WireCtorPath co ->
  WireFieldSchema fields ->
  WireSchema co fields
trustedWireSchema = TrustedWireSchema

-- | Internal trusted input-schema constructor used only by Generic
-- derivation and checked sum lifting.
trustedInCtorSchema ::
  WireCtorPath ci ->
  InCtorFieldSchema fields ->
  InCtorSchema ci fields
trustedInCtorSchema = TrustedInCtorSchema

-- | Hidden composition-only evidence for the polymorphic identity boundary.
-- It aligns the one payload slot with the one wire field but deliberately
-- remains unavailable to symbolic constructor-identity proofs.
compositionOnlyInCtorSchema ::
  InCtorSchema carrier '[ '("payload", carrier)]
compositionOnlyInCtorSchema = CompositionOnlyInCtorSchema CompositionOnlyRoot

-- | Output-side half of 'compositionOnlyInCtorSchema'.
compositionOnlyWireSchema :: WireSchema carrier (carrier, ())
compositionOnlyWireSchema = CompositionOnlyWireSchema CompositionOnlyRoot

wireFieldsNil :: WireFieldSchema ()
wireFieldsNil = WireFieldsNil

wireFieldsCons ::
  (Typeable field) =>
  Maybe String ->
  WireFieldSchema rest ->
  WireFieldSchema (field, rest)
wireFieldsCons = WireFieldsCons

inCtorFieldsNil :: InCtorFieldSchema '[]
inCtorFieldsNil = InCtorFieldsNil

inCtorFieldsCons ::
  (Typeable field) =>
  Maybe String ->
  InCtorFieldSchema rest ->
  InCtorFieldSchema ('(name, field) ': rest)
inCtorFieldsCons = InCtorFieldsCons

appendWireFieldSchema ::
  WireFieldSchema left ->
  WireFieldSchema right ->
  WireFieldSchema (AppendWireFields left right)
appendWireFieldSchema WireFieldsNil right = right
appendWireFieldSchema (WireFieldsCons label rest) right =
  WireFieldsCons label (appendWireFieldSchema rest right)

appendInCtorFieldSchema ::
  InCtorFieldSchema left ->
  InCtorFieldSchema right ->
  InCtorFieldSchema (AppendInCtorFields left right)
appendInCtorFieldSchema InCtorFieldsNil right = right
appendInCtorFieldSchema (InCtorFieldsCons label rest) right =
  InCtorFieldsCons label (appendInCtorFieldSchema rest right)

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
prefixWireSchemaLeft (CompositionOnlyWireSchema spine) =
  CompositionOnlyWireSchema (CompositionOnlyLeft spine)
prefixWireSchemaLeft (TrustedWireSchema path fields) =
  TrustedWireSchema (prefixWireCtorPathLeft path) fields

-- | Preserve a trusted schema while crossing a checked sum boundary.
prefixWireSchemaRight ::
  WireSchema co2 fields ->
  WireSchema (Either co1 co2) fields
prefixWireSchemaRight UnavailableWireSchema = UnavailableWireSchema
prefixWireSchemaRight (CompositionOnlyWireSchema spine) =
  CompositionOnlyWireSchema (CompositionOnlyRight spine)
prefixWireSchemaRight (TrustedWireSchema path fields) =
  TrustedWireSchema (prefixWireCtorPathRight path) fields

-- | Preserve trusted input evidence through a checked left sum boundary.
prefixInCtorSchemaLeft ::
  InCtorSchema ci1 fields ->
  InCtorSchema (Either ci1 ci2) fields
prefixInCtorSchemaLeft UnavailableInCtorSchema = UnavailableInCtorSchema
prefixInCtorSchemaLeft (CompositionOnlyInCtorSchema spine) =
  CompositionOnlyInCtorSchema (CompositionOnlyLeft spine)
prefixInCtorSchemaLeft (TrustedInCtorSchema path fields) =
  TrustedInCtorSchema (prefixWireCtorPathLeft path) fields

-- | Preserve trusted input evidence through a checked right sum boundary.
prefixInCtorSchemaRight ::
  InCtorSchema ci2 fields ->
  InCtorSchema (Either ci1 ci2) fields
prefixInCtorSchemaRight UnavailableInCtorSchema = UnavailableInCtorSchema
prefixInCtorSchemaRight (CompositionOnlyInCtorSchema spine) =
  CompositionOnlyInCtorSchema (CompositionOnlyRight spine)
prefixInCtorSchemaRight (TrustedInCtorSchema path fields) =
  TrustedInCtorSchema (prefixWireCtorPathRight path) fields

-- | Compare two trusted schemas. Paths count as different only when they
-- diverge at a common position. A proper-prefix relation remains
-- unwitnessed because the corresponding match sets can overlap.
compareWireSchemas ::
  WireSchema co left ->
  WireSchema co right ->
  WireSchemaComparison left right
compareWireSchemas UnavailableWireSchema _ = WireSchemasUnwitnessed
compareWireSchemas _ UnavailableWireSchema = WireSchemasUnwitnessed
compareWireSchemas CompositionOnlyWireSchema {} _ = WireSchemasUnwitnessed
compareWireSchemas _ CompositionOnlyWireSchema {} = WireSchemasUnwitnessed
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

-- | Compare two input constructors using path and slot-type evidence.
compareInCtorSchemas ::
  InCtorSchema ci left ->
  InCtorSchema ci right ->
  InCtorSchemaComparison left right
compareInCtorSchemas UnavailableInCtorSchema _ = InCtorSchemasUnwitnessed
compareInCtorSchemas _ UnavailableInCtorSchema = InCtorSchemasUnwitnessed
compareInCtorSchemas CompositionOnlyInCtorSchema {} _ = InCtorSchemasUnwitnessed
compareInCtorSchemas _ CompositionOnlyInCtorSchema {} = InCtorSchemasUnwitnessed
compareInCtorSchemas
  (TrustedInCtorSchema (WireCtorPath leftPath) leftFields)
  (TrustedInCtorSchema (WireCtorPath rightPath) rightFields) =
    case comparePaths leftPath rightPath of
      PathsEqual ->
        maybe
          InCtorSchemasUnwitnessed
          InCtorSchemasEqual
          (alignInCtorFields leftFields rightFields)
      PathsDiverge -> InCtorSchemasDifferent
      PathsPrefixRelated -> InCtorSchemasUnwitnessed

-- | Compare one input constructor with one output wire constructor.
compareInCtorWireSchemas ::
  InCtorSchema carrier inputFields ->
  WireSchema carrier wireFields ->
  InWireSchemaComparison inputFields wireFields
compareInCtorWireSchemas UnavailableInCtorSchema _ = InWireSchemasUnwitnessed
compareInCtorWireSchemas _ UnavailableWireSchema = InWireSchemasUnwitnessed
compareInCtorWireSchemas
  (CompositionOnlyInCtorSchema inputSpine)
  (CompositionOnlyWireSchema wireSpine) =
    compareCompositionOnlySpines inputSpine wireSpine
compareInCtorWireSchemas CompositionOnlyInCtorSchema {} _ = InWireSchemasUnwitnessed
compareInCtorWireSchemas _ CompositionOnlyWireSchema {} = InWireSchemasUnwitnessed
compareInCtorWireSchemas
  (TrustedInCtorSchema (WireCtorPath inputPath) inputFields)
  (TrustedWireSchema (WireCtorPath wirePath) wireFields) =
    case comparePaths inputPath wirePath of
      PathsEqual ->
        maybe
          InWireSchemasUnwitnessed
          InWireSchemasEqual
          (alignInWireFields inputFields wireFields)
      PathsDiverge -> InWireSchemasDifferent
      PathsPrefixRelated -> InWireSchemasUnwitnessed

compareCompositionOnlySpines ::
  CompositionOnlySpine carrier inputField ->
  CompositionOnlySpine carrier wireField ->
  InWireSchemaComparison '[ '("payload", inputField)] (wireField, ())
compareCompositionOnlySpines CompositionOnlyRoot CompositionOnlyRoot =
  InWireSchemasEqual (InWireFieldsAlignedCons InWireFieldsAlignedNil)
compareCompositionOnlySpines CompositionOnlyRoot CompositionOnlyLeft {} =
  InWireSchemasUnwitnessed
compareCompositionOnlySpines CompositionOnlyRoot CompositionOnlyRight {} =
  InWireSchemasUnwitnessed
compareCompositionOnlySpines CompositionOnlyLeft {} CompositionOnlyRoot =
  InWireSchemasUnwitnessed
compareCompositionOnlySpines CompositionOnlyRight {} CompositionOnlyRoot =
  InWireSchemasUnwitnessed
compareCompositionOnlySpines
  (CompositionOnlyLeft inputRest)
  (CompositionOnlyLeft wireRest) =
    compareCompositionOnlySpines inputRest wireRest
compareCompositionOnlySpines CompositionOnlyLeft {} CompositionOnlyRight {} =
  InWireSchemasDifferent
compareCompositionOnlySpines CompositionOnlyRight {} CompositionOnlyLeft {} =
  InWireSchemasDifferent
compareCompositionOnlySpines
  (CompositionOnlyRight inputRest)
  (CompositionOnlyRight wireRest) =
    compareCompositionOnlySpines inputRest wireRest

-- | Hidden symbolic identity: trusted paths become prefix constraints;
-- unavailable evidence remains on the conservative fallback path.
inCtorSchemaPath :: InCtorSchema ci fields -> Maybe [Bool]
inCtorSchemaPath UnavailableInCtorSchema = Nothing
inCtorSchemaPath CompositionOnlyInCtorSchema {} = Nothing
inCtorSchemaPath (TrustedInCtorSchema (WireCtorPath path) _) =
  Just (map stepIsLeft path)
  where
    stepIsLeft WireCtorPathLeft = True
    stepIsLeft WireCtorPathRight = False

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

-- | Regression observer for the input-side proper-prefix rule.
inCtorSchemaPrefixRelationForTesting :: InputHeadRelation
inCtorSchemaPrefixRelationForTesting =
  let root =
        TrustedInCtorSchema wireCtorPathRoot InCtorFieldsNil ::
          InCtorSchema () '[]
      prefixed =
        TrustedInCtorSchema
          (genericPrefixWireCtorPathLeft wireCtorPathRoot)
          InCtorFieldsNil ::
          InCtorSchema () '[]
   in case compareInCtorSchemas root prefixed of
        InCtorSchemasEqual _ -> InputHeadsStructurallyEqual
        InCtorSchemasDifferent -> InputHeadsStructurallyDifferent
        InCtorSchemasUnwitnessed -> InputHeadsUnwitnessed

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

alignInCtorFields ::
  InCtorFieldSchema left ->
  InCtorFieldSchema right ->
  Maybe (InCtorFieldAlignment left right)
alignInCtorFields InCtorFieldsNil InCtorFieldsNil = Just InCtorFieldsAlignedNil
alignInCtorFields InCtorFieldsNil InCtorFieldsCons {} = Nothing
alignInCtorFields InCtorFieldsCons {} InCtorFieldsNil = Nothing
alignInCtorFields
  (InCtorFieldsCons @fieldLeft _ leftRest)
  (InCtorFieldsCons @fieldRight _ rightRest) =
    case eqTypeRep (typeRep @fieldLeft) (typeRep @fieldRight) of
      Just HRefl -> InCtorFieldsAlignedCons <$> alignInCtorFields leftRest rightRest
      Nothing -> Nothing

alignInWireFields ::
  InCtorFieldSchema inputFields ->
  WireFieldSchema wireFields ->
  Maybe (InWireFieldAlignment inputFields wireFields)
alignInWireFields InCtorFieldsNil WireFieldsNil = Just InWireFieldsAlignedNil
alignInWireFields InCtorFieldsNil WireFieldsCons {} = Nothing
alignInWireFields InCtorFieldsCons {} WireFieldsNil = Nothing
alignInWireFields
  (InCtorFieldsCons @inputField _ inputRest)
  (WireFieldsCons @wireField _ wireRest) =
    case eqTypeRep (typeRep @inputField) (typeRep @wireField) of
      Just HRefl -> InWireFieldsAlignedCons <$> alignInWireFields inputRest wireRest
      Nothing -> Nothing
