{-# LANGUAGE TypeAbstractions #-}
{-# LANGUAGE TypeFamilies #-}

-- | SBV-backed symbolic surface for 'Keiki.Core' predicates.
--
-- This module is the v2 symbolic upgrade of the v1 best-effort
-- @BoolAlg HsPred@ instance pinned by EP-4 of MasterPlan 1's
-- Outcomes & Retrospective. After EP-2 of MasterPlan 2, asking
-- "are these two edge guards mutually exclusive?" is a mechanical
-- question with a precise answer for exact translations. Conservative
-- translations remain one-sided and carry explicit strength evidence.
--
-- The module re-exports everything from "Keiki.Core" so a single
-- import is sufficient for callers that need both the pure and the
-- symbolic surfaces. See @docs/research/sbv-boolalg-design.md@ for
-- the design rationale.
--
-- Milestones implemented in this revision (through M5 of EP-2):
--
--   * The 'Sym' typeclass and instances for 'Bool', 'Int', 'Integer',
--     'Natural', 'Text', 'UTCTime', and the fixed-width integers 'Word8' \/
--     'Word16' \/ 'Word32' \/ 'Word64' \/ 'Int32' \/ 'Int64' (the
--     last group added by EP-41 so money and count registers are
--     solver-visible).
--   * 'SymEnv' carrying the shared symbolic input-constructor tag and
--     (since EP-42 of MasterPlan 12) an 'IORef' memo cache that shares
--     one SBV variable per register slot, input field, or nominal typed field
--     projection across repeated reads, so @proj #x .== proj #x@ and repeated
--     projected reads are valid, not merely satisfiable.
--   * 'translateTermSym' / 'translatePred' walking 'Term' / 'HsPred'
--     into SBV expressions.
--   * 'discoverSym' — runtime dispatch from 'Typeable' to 'Sym'
--     evidence over the curated registry of supported types.
--   * 'SymPred' newtype wrapper plus its 'BoolAlg' instance with
--     structural 'top' / 'bot' / 'conj' / 'disj' / 'neg', a 'models'
--     that re-uses the v1 'evalPred' (concrete evaluation, no solver
--     call), and an 'isBot' backed by z3.
--   * 'symIsBot' — conservative pure-API wrapper around SBV's solver call
--     (via 'unsafePerformIO' + NOINLINE) that 'SymPred''s 'isBot' routes
--     through. Solver failures and non-UNSAT statuses return 'False'.
--   * 'symSatExt' — full witness extraction. Since EP-44 (MasterPlan 12)
--     the 'Keiki.Core.Sat' method 'sat' on 'SymPred' /is/
--     'symSatExt' (via the @Sat (SymPred …)@ instance, which carries the
--     'ExtractRegFile' / 'KnownInCtors' evidence witness reconstruction
--     needs); the old crashing placeholder is gone.
module Keiki.Symbolic
  ( -- * Symbolic representation
    Sym (..),
    SymDict (..),
    symLit,
    symFree,
    discoverSym,
    SymOrdDict (..),
    discoverSymOrd,
    SymNumDict (..),
    discoverSymNum,
    symbolicWholeCarrierExact,

    -- * Translation
    SymEnv (..),
    mkSymEnv,
    translateTermSym,
    translatePred,
    constrainFieldProjection,
    ProjectionBaseKind (..),
    ProjectionBaseDescriptor (..),
    ProjectionDescriptor (..),
    TranslationStrength (..),
    TranslationIssue (..),
    PredicateVerification (..),
    ProjectionModel (..),
    projectionModelKeyAs,
    projectionModelOwnerAs,
    PredicateVerificationDetail (..),
    predicateTranslationReport,
    predicateTranslationExact,
    verifyPredicateDetailed,
    verifyPredicate,

    -- * Symbolic predicate wrapper
    SymPred (..),
    SymGuarded,

    -- * Solver-backed analyses
    satResultIsProvablyUnsat,
    symIsBot,
    symSatExt,

    -- * Witness extraction
    ExtractRegFile (..),
    SomeInCtor (..),
    KnownInCtors (..),

    -- * Single-valuedness
    isSingleValuedSym,
    withSymPred,

    -- * Solver-backed validation diagnostics (EP-56)
    DeterminismAnalysisDetail (..),
    checkTransitionDeterminismSymDetailed,
    checkTransitionDeterminismSym,
    DeadEdgeAnalysisDetail (..),
    checkDeadEdgesSymDetailed,
    checkDeadEdgesSym,

    -- * Re-exports
    module Keiki.Core,
    module Keiki.ProjectionDomain,
  )
where

import Control.Exception (ErrorCall, SomeException, displayException, evaluate, try)
import Control.Monad (forM, when)
import Control.Monad.IO.Class (liftIO)
import Data.Dynamic (Dynamic, fromDynamic, toDyn)
import Data.Fixed (Fixed (MkFixed))
import Data.Foldable (toList)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.Int (Int32, Int64)
import Data.Kind (Type)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe)
import Data.Proxy (Proxy (..))
import Data.SBV qualified as SBV
import Data.SBV.RegExp qualified as SBV.RegExp
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime, nominalDiffTimeToSeconds, secondsToNominalDiffTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime, utcTimeToPOSIXSeconds)
import Data.Typeable (Typeable)
import Data.Word (Word16, Word32, Word64, Word8)
import GHC.TypeLits (KnownSymbol, symbolVal)
import Keiki.Core
import Keiki.Internal.ProjectionDomain
  ( ProjectionDomain (..),
    TextPattern (..),
  )
import Keiki.Internal.SymbolicTypes
  ( SymbolicType (..),
    discoverSymbolicType,
    symbolicTypeWholeCarrierExact,
  )
import Keiki.ProjectionDomain
import Numeric.Natural (Natural)
import System.IO.Unsafe (unsafePerformIO)
import Type.Reflection (SomeTypeRep (..), eqTypeRep, typeRep, type (:~~:) (HRefl))

-- * Symbolic representation -------------------------------------------------

-- | A type that has a curated representation in the SBV symbolic
-- universe. The associated type 'SymRep' pins the SBV-friendly
-- representation; the 'toSym' / 'fromSym' round-trip lets us push
-- concrete Haskell values into the solver and pull concrete witnesses
-- out of a model.
--
-- The 'SBV.SymVal' superclass on 'SymRep' gives us 'SBV.literal',
-- 'SBV.free', and 'SBV.unliteral' for free.
--
-- 'symDefault' is consumed by 'symSatExt': when the solver's model
-- has no value for a slot or input field that the predicate did not
-- reference, the witness extractor falls back to 'symDefault'. Sound
-- because such slots are unconstrained — any value satisfies the
-- predicate.
class (SBV.SymVal (SymRep a), Typeable a) => Sym a where
  type SymRep a :: Type
  toSym :: a -> SymRep a
  fromSym :: SymRep a -> a
  symDefault :: a

  -- | Restrict a symbolic representation to values that denote a real @a@.
  -- Most carriers use their whole SBV domain. Refined carriers such as
  -- 'Natural' add constraints whenever Keiki allocates a symbolic variable.
  constrainSymDomain :: SBV.SBV (SymRep a) -> SBV.Symbolic ()
  constrainSymDomain _ = pure ()

instance Sym Bool where
  type SymRep Bool = Bool
  toSym = id
  fromSym = id
  symDefault = False

instance Sym Integer where
  type SymRep Integer = Integer
  toSym = id
  fromSym = id
  symDefault = 0

-- | Arbitrary-precision non-negative integers. The representation stays an
-- unbounded SMT integer, while every allocated variable is constrained to the
-- actual 'Natural' domain. Numeric arithmetic is deliberately not registered:
-- Haskell 'Natural' subtraction throws @Underflow@ when its mathematical result
-- would be negative, while ordinary SMT integer subtraction returns that negative
-- integer. Treating the operations as identical would not preserve concrete behavior.
instance Sym Natural where
  type SymRep Natural = Integer
  toSym = fromIntegral
  fromSym = fromInteger
  symDefault = 0
  constrainSymDomain value = SBV.constrain (value SBV..>= 0)

-- | Encoded as 'Integer'. SBV does not provide an 'SInt'-of-arbitrary-
-- size; using 'Integer' means machine-width 'Int' wraparound is not modeled.
-- Guards whose truth depends on 'Int' overflow should use an explicit
-- fixed-width type instead.
instance Sym Int where
  type SymRep Int = Integer
  toSym = fromIntegral
  fromSym = fromIntegral
  symDefault = 0

-- The fixed-width instances use SBV's matching bit-vector representations, so
-- their arithmetic has exactly the same modular wraparound as Haskell.

-- | Money and large counts, modeled as an exact 64-bit unsigned value.
instance Sym Word64 where
  type SymRep Word64 = Word64
  toSym = id
  fromSym = id
  symDefault = 0

-- | Item counts and similar 32-bit unsigned registers, modeled exactly.
instance Sym Word32 where
  type SymRep Word32 = Word32
  toSym = id
  fromSym = id
  symDefault = 0

-- | Quantities, basis points, and similar 16-bit unsigned registers, modeled
-- exactly.
instance Sym Word16 where
  type SymRep Word16 = Word16
  toSym = id
  fromSym = id
  symDefault = 0

-- | An exact 8-bit unsigned value.
instance Sym Word8 where
  type SymRep Word8 = Word8
  toSym = id
  fromSym = id
  symDefault = 0

-- | An exact 64-bit signed value.
instance Sym Int64 where
  type SymRep Int64 = Int64
  toSym = id
  fromSym = id
  symDefault = 0

-- | An exact 32-bit signed value.
instance Sym Int32 where
  type SymRep Int32 = Int32
  toSym = id
  fromSym = id
  symDefault = 0

-- | 'Text' is encoded as Haskell 'String' for SBV's 'SString' theory.
instance Sym Text where
  type SymRep Text = String
  toSym = T.unpack
  fromSym = T.pack
  symDefault = T.empty

-- | 'UTCTime' is encoded as picoseconds since the Unix epoch. The time
-- library's 'NominalDiffTime' uses a fixed-point picosecond representation, so
-- this 'Integer' encoding is lossless while remaining well supported by z3.
instance Sym UTCTime where
  type SymRep UTCTime = Integer
  toSym t =
    let MkFixed picoseconds =
          nominalDiffTimeToSeconds (utcTimeToPOSIXSeconds t)
     in picoseconds
  fromSym picoseconds =
    posixSecondsToUTCTime
      (secondsToNominalDiffTime (MkFixed picoseconds))
  symDefault = posixSecondsToUTCTime 0

-- | Reify a 'Sym' instance so it can be passed around as a
-- first-class value. Useful for runtime dispatch on 'Typeable'
-- evidence.
data SymDict r where
  SymDict :: (Sym r) => SymDict r

-- | Try to discover a 'Sym' instance for @r@ at runtime. Returns
-- @Just SymDict@ for any of the curated supported types
-- ('Bool', 'Int', 'Integer', 'Natural', 'Text', 'UTCTime', and the fixed-width
-- integers 'Word8' \/ 'Word16' \/ 'Word32' \/ 'Word64' \/ 'Int32' \/
-- 'Int64'); 'Nothing' otherwise. The translator uses this to route
-- 'PEq' over arbitrary types: a 'Sym' hit translates to '(.==)' on
-- SBV terms; a miss falls back to a fresh 'SBool' (loses precision but
-- stays sound).
discoverSym :: forall r. (Typeable r) => Maybe (SymDict r)
discoverSym = case discoverSymbolicType @r of
  Just SymbolicBool -> Just SymDict
  Just SymbolicInt -> Just SymDict
  Just SymbolicInteger -> Just SymDict
  Just SymbolicNatural -> Just SymDict
  Just SymbolicText -> Just SymDict
  Just SymbolicUTCTime -> Just SymDict
  Just SymbolicWord64 -> Just SymDict
  Just SymbolicWord32 -> Just SymDict
  Just SymbolicWord16 -> Just SymDict
  Just SymbolicWord8 -> Just SymDict
  Just SymbolicInt64 -> Just SymDict
  Just SymbolicInt32 -> Just SymDict
  Nothing -> Nothing

-- | Reify both a 'Sym' instance for @r@ and evidence that its
-- 'SymRep' is symbolically orderable (an 'SBV.OrdSymbolic' instance on
-- @'SBV.SBV' ('SymRep' r)@). This is exactly what 'PCmp' translation
-- needs: 'Sym' to push the operands into SBV, 'OrdSymbolic' to emit a
-- real @.<@ \/ @.<=@ \/ @.>@ \/ @.>=@ comparison.
data SymOrdDict r where
  SymOrdDict :: (Sym r, SBV.OrdSymbolic (SBV.SBV (SymRep r))) => SymOrdDict r

-- | Try to discover ordering evidence for @r@ at runtime, companion to
-- 'discoverSym'. Returns @Just SymOrdDict@ for the numeric and time
-- types whose 'SymRep' is an 'SBV.OrdSymbolic' 'Integer' ('Int',
-- 'Integer', 'Natural', the fixed-width integers 'Word8' \/ 'Word16' \/ 'Word32'
-- \/ 'Word64' \/ 'Int32' \/ 'Int64', and 'UTCTime' encoded as epoch
-- seconds); 'Nothing' otherwise. 'Bool' and 'Text' are deliberately
-- omitted: ordering a 'Bool' guard is not meaningful, and 'SString'
-- ordering is out of scope here. A 'Nothing' makes the 'PCmp'
-- translator fall back to a fresh opaque 'SBool', exactly as 'goEq'
-- does for non-'Sym' operands — sound, just imprecise.
discoverSymOrd :: forall r. (Typeable r) => Maybe (SymOrdDict r)
discoverSymOrd = case discoverSymbolicType @r of
  Just SymbolicInt -> Just SymOrdDict
  Just SymbolicInteger -> Just SymOrdDict
  Just SymbolicNatural -> Just SymOrdDict
  Just SymbolicUTCTime -> Just SymOrdDict
  Just SymbolicWord64 -> Just SymOrdDict
  Just SymbolicWord32 -> Just SymOrdDict
  Just SymbolicWord16 -> Just SymOrdDict
  Just SymbolicWord8 -> Just SymOrdDict
  Just SymbolicInt64 -> Just SymOrdDict
  Just SymbolicInt32 -> Just SymOrdDict
  Just SymbolicBool -> Nothing
  Just SymbolicText -> Nothing
  Nothing -> Nothing

-- | Reify both a 'Sym' instance for @r@ and evidence that its 'SymRep'
-- is symbolically /numeric/ (a 'Num' instance on @'SBV.SBV' ('SymRep'
-- r)@). This is what 'TArith' translation needs: 'Sym' to push the
-- operands into SBV, 'Num' to emit a real @+@ \/ @-@ \/ @*@ over the
-- translated terms. Companion to 'discoverSym' \/ 'discoverSymOrd'
-- (EP-43).
data SymNumDict r where
  SymNumDict :: (Sym r, Num (SBV.SBV (SymRep r))) => SymNumDict r

-- | Try to discover numeric evidence for @r@ at runtime, companion to
-- 'discoverSymOrd'. Returns @Just SymNumDict@ for the numeric types
-- whose 'SymRep' is the SBV-'Num' 'Integer' ('Int', 'Integer', and the
-- fixed-width integers 'Word8' \/ 'Word16' \/ 'Word32' \/ 'Word64' \/
-- 'Int32' \/ 'Int64'), plus 'Natural'. Natural subtraction has the explicit
-- total monus meaning shared with concrete 'evalTerm'; it is translated as
-- @ite (a >= b) (a - b) 0@ rather than ordinary integer subtraction.
-- 'Bool', 'Text', and 'UTCTime' are omitted. A 'Nothing'
-- makes the 'TArith' translator fall back to a fresh opaque variable,
-- exactly as 'goEq' \/ 'goCmp' fall back for non-'Sym' operands —
-- sound, just imprecise. (The 'Num' constraint on the 'TArith'
-- constructor already prevents arithmetic at non-numeric types, so this
-- fallback is only reachable for a numeric type intentionally left out
-- of the registry.)
discoverSymNum :: forall r. (Typeable r) => Maybe (SymNumDict r)
discoverSymNum = case discoverSymbolicType @r of
  Just SymbolicInt -> Just SymNumDict
  Just SymbolicInteger -> Just SymNumDict
  Just SymbolicNatural -> Just SymNumDict
  Just SymbolicWord64 -> Just SymNumDict
  Just SymbolicWord32 -> Just SymNumDict
  Just SymbolicWord16 -> Just SymNumDict
  Just SymbolicWord8 -> Just SymNumDict
  Just SymbolicInt64 -> Just SymNumDict
  Just SymbolicInt32 -> Just SymNumDict
  Just SymbolicBool -> Nothing
  Just SymbolicText -> Nothing
  Just SymbolicUTCTime -> Nothing
  Nothing -> Nothing

-- | Whether the curated representation covers the complete concrete carrier
-- bijectively. This is the gate for 'wholeProjectionDomain': supporting
-- symbolic equality alone is not sufficient.
symbolicWholeCarrierExact :: forall (r :: Type). (Typeable r) => Bool
symbolicWholeCarrierExact =
  maybe False symbolicTypeWholeCarrierExact (discoverSymbolicType @r)

-- | Lift a concrete value to an SBV literal of its 'SymRep'.
symLit :: forall a. (Sym a) => a -> SBV.SBV (SymRep a)
symLit = SBV.literal . toSym

-- | Allocate a fresh symbolic variable of the carrier's 'SymRep'.
symFree :: forall a. (Sym a) => String -> SBV.Symbolic (SBV.SBV (SymRep a))
symFree label = do
  value <- SBV.free label
  constrainSymDomain @a value
  pure value

-- * Translation environment -------------------------------------------------

-- | Translation context: shared symbolic state that must be threaded
-- through a single predicate's walk so that, for example, two
-- 'PInCtor' atoms over distinct constructors agree they cannot both
-- be true, and two reads of the same register (or input field) share
-- one solver variable.
--
-- Three pieces of state are shared:
--
--   * 'seInputCtor' — the symbolic input-constructor tag, so 'PInCtor'
--     atoms over distinct constructors are recognized as mutually
--     unsatisfiable.
--   * 'seInputArm' — an independent discriminator for 'PLeftArm' and
--     'PRightArm'. It is separate from constructor names so both facts can
--     be asserted by the same guard.
--   * 'seVarCache' — a per-translation memo cache (EP-42) keyed by a
--     structured 'SymVarKey'. Ordinary register and input reads preserve their
--     historical labels; field projections use base position and nominal
--     'TypeRep' identity, never caller-controlled diagnostic strings alone.
--     The first read allocates one 'SBV.free' variable and stores it; every
--     later read of the same key returns the cached variable.
--     This makes the solver see two reads of @#x@ as the /same/ value,
--     so @proj #x .== proj #x@ is valid (not merely satisfiable). The
--     'TApp1' \/ 'TApp2' escape hatches are deliberately /not/ cached:
--     they wrap opaque Haskell functions with no 'Eq', so two
--     applications cannot be recognized as equal and each stays a fresh
--     per-occurrence variable.
data ProjectionBaseKey
  = ProjectionReg String Int
  | ProjectionInp String String Int
  deriving stock (Eq, Ord, Show)

-- | Which structural carrier owns a projection base.
data ProjectionBaseKind
  = ProjectionRegisterOwner
  | ProjectionInputOwner
  deriving stock (Eq, Ord, Show)

-- | Stable structural identity for the concrete owner read beneath a field
-- projection. Display names are diagnostic; kind, optional input constructor,
-- and zero-based position keep identity structural.
data ProjectionBaseDescriptor = ProjectionBaseDescriptor
  { projectionBaseKind :: ProjectionBaseKind,
    projectionBaseConstructorName :: Maybe String,
    projectionBaseSlotName :: String,
    projectionBasePosition :: Int,
    projectionBaseOwnerType :: SomeTypeRep
  }
  deriving stock (Eq, Ord, Show)

-- | Public, function-free metadata for one nominal projection occurrence.
data ProjectionDescriptor = ProjectionDescriptor
  { projectionDescriptorBase :: ProjectionBaseDescriptor,
    projectionDescriptorPath :: String,
    projectionDescriptorShape :: String,
    projectionDescriptorTagType :: SomeTypeRep,
    projectionDescriptorOwnerType :: SomeTypeRep,
    projectionDescriptorResultType :: SomeTypeRep
  }
  deriving stock (Eq, Ord, Show)

-- | Whether every symbolic valuation of a predicate corresponds to its
-- concrete semantics, or the translation is only a sound over-approximation.
data TranslationStrength
  = ExactTranslation
  | ConservativeOverApproximation (NonEmpty TranslationIssue)
  deriving stock (Eq, Show)

-- | A deterministic explanation for lost translation exactness.
data TranslationIssue
  = OpaqueApplication
  | UnsupportedEquality SomeTypeRep
  | UnsupportedOrdering SomeTypeRep
  | UnsupportedArithmetic SomeTypeRep
  | UnconstrainedProjection ProjectionDescriptor
  | UnsupportedProjectionDomain ProjectionDescriptor String
  | ProjectionUsedOutsideEquality ProjectionDescriptor
  | ConflictingProjectionViews ProjectionBaseDescriptor
  | DirectAndProjectedOwnerRead ProjectionBaseDescriptor
  | UnguardedProjectionInputRead ProjectionDescriptor
  deriving stock (Eq, Show)

data SymVarKey
  = RegVar String
  | InpVar String String
  | ProjectionVar
      ProjectionBaseKey
      SomeTypeRep
      SomeTypeRep
      SomeTypeRep
  deriving stock (Eq, Ord, Show)

data SymEnv = SymEnv
  { -- | The shared symbolic input constructor tag. 'PInCtor' atoms
    --     assert @seInputCtor .== literal (icName ic)@; the solver
    --     recognizes that two such constraints with distinct names are
    --     mutually unsatisfiable.
    seInputCtor :: SBV.SBV String,
    -- | @True@ denotes the outer 'Left' arm; @False@ denotes 'Right'.
    seInputArm :: SBV.SBool,
    -- | Memo cache: maps a deterministic variable name ("reg/\<slot\>"
    --     or "inp/\<ctor\>/\<field\>") to the single SBV variable allocated
    --     for it during this predicate translation. Lazily populated on
    --     first read so unread slots stay unconstrained (and 'symSatExt'
    --     falls back to 'symDefault' for them). Scoped to one
    --     'translatePred' walk (one 'mkSymEnv'), so variables are shared
    --     /within/ a query but never leak across independent queries.
    seVarCache :: IORef (Map SymVarKey SomeSBV),
    -- | Stable model label for every memoized structural variable.
    seVarLabels :: IORef (Map SymVarKey String),
    -- | Projection keys in allocation/first-occurrence order.
    seProjectionKeyOrder :: IORef [SymVarKey],
    -- | Keys whose complete exact-domain constraint was emitted.
    seConstrainedProjectionKeys :: IORef (Set SymVarKey),
    -- | Exact evidence used to decode and reconstruct satisfiable models.
    seProjectionBindings :: IORef (Map SymVarKey SomeProjectionBinding),
    -- | Next internal projection label. Projection labels are intentionally
    --     generated by Keiki so arbitrary schema names never reach SBV's
    --     restricted label namespace.
    seProjectionOrdinal :: IORef Int
  }

-- | An SBV variable of some representation type, packed so the memo
-- cache in 'SymEnv' can hold variables of different representation
-- types under one map. 'SBV.SymVal' has a 'Typeable' superclass, so
-- pattern-matching @SomeSBV (v :: SBV.SBV a)@ brings @Typeable a@ into
-- scope — exactly what 'memoFree' needs to check the recovered type
-- matches the requested one on a cache hit.
data SomeSBV where
  SomeSBV :: (SBV.SymVal a) => SBV.SBV a -> SomeSBV

data SomeProjectionBinding where
  SomeProjectionBinding ::
    ( FieldProjection projection,
      Typeable projection,
      Typeable (FieldOwner projection),
      Typeable (FieldResult projection),
      Sym (FieldResult projection)
    ) =>
    ProjectionDescriptor ->
    String ->
    FieldWitness projection ->
    SomeProjectionBinding

-- | Allocate a fresh 'SymEnv'. Lives in 'SBV.Symbolic' because
-- 'seInputCtor' is a free symbolic variable and the memo cache is an
-- 'IORef' created in the underlying 'IO' ('SBV.Symbolic' is
-- @SymbolicT IO@, hence 'MonadIO').
mkSymEnv :: SBV.Symbolic SymEnv
mkSymEnv = do
  ctor <- SBV.free "inputCtor"
  arm <- SBV.free "inputArm"
  cache <- liftIO (newIORef Map.empty)
  labels <- liftIO (newIORef Map.empty)
  projectionOrder <- liftIO (newIORef [])
  constrainedProjectionKeys <- liftIO (newIORef Set.empty)
  projectionBindings <- liftIO (newIORef Map.empty)
  projectionOrdinal <- liftIO (newIORef 0)
  pure
    ( SymEnv
        ctor
        arm
        cache
        labels
        projectionOrder
        constrainedProjectionKeys
        projectionBindings
        projectionOrdinal
    )

-- * Translation -------------------------------------------------------------

-- | Translate a 'Term rs ci r' to an SBV expression of the carrier's
-- representation type. Requires 'Sym' evidence for @r@.
--
-- The translation is /structural/ for 'TLit', 'TOpaqueLit', 'TReg',
-- 'TInpCtorField', and (since EP-43) 'TArith': a 'TArith' over a type
-- whose 'SymRep' is SBV-numeric (a 'discoverSymNum' hit) emits a real
-- @+@ \/ @-@ \/ @*@ over the translated operands, so a guard over a
-- /computed/ value is visible to the solver. 'TApp1' and 'TApp2' wrap
-- opaque Haskell functions and translate to fresh SBV variables of the
-- result type — sound but imprecise; 'TArith' falls back to the same
-- fresh variable only if its (numeric) operand type is absent from the
-- 'discoverSymNum' registry.
--
-- Variable naming (consumed by 'symSatExt' for witness extraction):
--
--   * 'TReg' allocates @"reg/<slotName>"@ where @slotName@ is the
--     slot's label recovered from the 'Index'\'s 'KnownSymbol'
--     evidence on its leaf 'ZIdx'.
--   * 'TInpCtorField' allocates
--     @"inp/<icName>/<slotName>"@ — the 'InCtor''s name plus the
--     field's slot label.
--   * 'TFieldProj' uses a structured cache key containing the base position,
--     nominal projection tag, owner type, and result type. Its actual SBV
--     label is an internal @"proj/<ordinal>"@, so arbitrary schema strings
--     cannot collide with or violate SBV's label syntax.
--   * 'TApp1' / 'TApp2' keep their anonymous names; their values are
--     not extracted as part of the witness.
--
-- Note on repeated reads (EP-42): 'TReg', 'TInpCtorField', and
-- 'TFieldProj' reads are memoized through the env's 'seVarCache'. This is
-- /path-exact/: the first
-- read of a given structural key allocates one 'SBV.free' variable and caches
-- it; every later read of the same key returns the cached variable. So two
-- reads of the same slot (e.g.
-- @proj #x .== proj #x@) share /one/ SBV variable: the solver knows
-- they are equal, @x \/= x@ is unsat, and 'symSatExt''s by-name witness
-- extraction is correct for ordinary repeated reads. Exact projection
-- variables carry a declared image and inverse, so detailed verification can
-- decode model values and reconstruct path-local owner witnesses. Legacy
-- one-way projections remain over-approximate and are not reconstructed. The
-- 'TApp1' \/ 'TApp2'
-- escape hatches stay per-occurrence fresh (their opaque functions
-- have no 'Eq', so two applications cannot be recognized as equal);
-- their values are not part of the extracted witness.
translateTermSym ::
  forall rs ci ifs r.
  (Sym r) =>
  SymEnv ->
  Term rs ci ifs r ->
  SBV.Symbolic (SBV.SBV (SymRep r))
translateTermSym _env (TLit r) = pure (symLit r)
translateTermSym _env (TOpaqueLit r) = pure (symLit r)
translateTermSym env (TReg ix) =
  memoFree @r env (RegVar (indexName ix))
translateTermSym env (TInpCtorField ic ix) =
  memoFree @r env (InpVar (icName ic) (indexName ix))
translateTermSym _env (TApp1 _f _t) = symFree @r "app1"
translateTermSym _env (TApp2 _f _a _b) = symFree @r "app2"
translateTermSym env (TArith op a b) = case discoverSymNum @r of
  Nothing -> symFree @r "arith" -- sound opaque fallback within the carrier domain
  Just SymNumDict -> do
    sa <- translateTermSym env a
    sb <- translateTermSym env b
    case (discoverSymbolicType @r, op) of
      (Just SymbolicNatural, OpSub) ->
        pure (SBV.ite (sa SBV..>= sb) (sa - sb) 0)
      _ -> do
        let apply = case op of
              OpAdd -> (+)
              OpSub -> (-)
              OpMul -> (*)
        pure (apply sa sb)
translateTermSym env (TFieldProj (witness :: FieldWitness projection) base) =
  do
    let key = projectionVarKey witness base
    symbolic <- memoFree @r env key
    case fieldWitnessDomain witness of
      Nothing -> pure ()
      Just domain -> case compileProjectionDomain @r domain symbolic of
        Left _unsupported -> pure ()
        Right domainConstraint -> do
          constrained <- liftIO (readIORef (seConstrainedProjectionKeys env))
          when (key `Set.notMember` constrained) $ do
            SBV.constrain domainConstraint
            liftIO
              ( modifyIORef'
                  (seConstrainedProjectionKeys env)
                  (Set.insert key)
              )
          labels <- liftIO (readIORef (seVarLabels env))
          case Map.lookup key labels of
            Nothing -> error "translateTermSym: projection variable has no model label"
            Just label ->
              liftIO
                ( modifyIORef'
                    (seProjectionBindings env)
                    ( Map.insertWith
                        (\_existing original -> original)
                        key
                        ( SomeProjectionBinding
                            (projectionDescriptor witness base)
                            label
                            witness
                        )
                    )
                )
    pure symbolic

-- | Why a declared projection domain could not be compiled exactly for its
-- active symbolic carrier. The translator must omit the entire constraint on
-- failure; emitting a stronger subset could manufacture false UNSAT.
data ProjectionDomainCompileError
  = UnsupportedWholeProjectionCarrier SomeTypeRep
  | UnsupportedFiniteProjectionLiteral SomeTypeRep
  deriving stock (Eq, Show)

compileProjectionDomain ::
  forall r.
  (Sym r) =>
  ProjectionDomain r ->
  SBV.SBV (SymRep r) ->
  Either ProjectionDomainCompileError SBV.SBool
compileProjectionDomain ProjectionWhole _symbolic
  | symbolicWholeCarrierExact @r = Right SBV.sTrue
  | otherwise = Left (UnsupportedWholeProjectionCarrier (SomeTypeRep (typeRep @r)))
compileProjectionDomain (ProjectionFinite values) symbolic
  | all projectionLiteralExact values =
      Right (SBV.sOr [symbolic SBV..== symLit value | value <- toList values])
  | otherwise =
      Left (UnsupportedFiniteProjectionLiteral (SomeTypeRep (typeRep @r)))
compileProjectionDomain (ProjectionText textPattern) symbolic =
  Right (symbolic `SBV.RegExp.match` compileTextPattern textPattern)

-- | A finite domain can be exact on a carrier whose whole representation is
-- not: machine 'Int', ordinary 'UTCTime', and bounded 'Text' literals are
-- examples. Each literal must nevertheless round-trip through 'SymRep', and a
-- 'Text' literal must stay within SMT-LIB's code-point ceiling.
projectionLiteralExact :: forall r. (Sym r, Eq r) => r -> Bool
projectionLiteralExact value =
  fromSym (toSym value) == value
    && case discoverSymbolicType @r of
      Just SymbolicText -> T.all (<= maximumSmtCodePoint) value
      _ -> True

compileTextPattern :: TextPattern -> SBV.RegExp.RegExp
compileTextPattern (TextLiteral literal) =
  SBV.RegExp.Literal (T.unpack literal)
compileTextPattern (TextRanges ranges) =
  SBV.RegExp.Union
    [ SBV.RegExp.Range lower upper
    | (lower, upper) <- toList ranges
    ]
compileTextPattern (TextConcat patterns) =
  SBV.RegExp.Conc (compileTextPattern <$> toList patterns)
compileTextPattern (TextAlternation patterns) =
  SBV.RegExp.Union (compileTextPattern <$> toList patterns)
compileTextPattern (TextRepeatBetween lower upper textPattern) =
  SBV.RegExp.Loop
    (fromIntegral lower)
    (fromIntegral upper)
    (compileTextPattern textPattern)

projectionVarKey ::
  forall projection rs ci ifs.
  ( Typeable projection,
    Typeable (FieldOwner projection),
    Typeable (FieldResult projection)
  ) =>
  FieldWitness projection ->
  ProjBase rs ci ifs (FieldOwner projection) ->
  SymVarKey
projectionVarKey _ base =
  ProjectionVar
    ( case base of
        PBReg ix -> ProjectionReg (indexName ix) (indexPosition ix)
        PBInp ic ix ->
          ProjectionInp (icName ic) (indexName ix) (indexPosition ix)
    )
    (SomeTypeRep (typeRep @projection))
    (SomeTypeRep (typeRep @(FieldOwner projection)))
    (SomeTypeRep (typeRep @(FieldResult projection)))

-- | Bind one memoized projection variable to the concrete getter result for
-- a known owner. Pass @fieldWitnessGet witness owner@ as the concrete result.
-- This supplies the concrete-to-symbolic simulation used by agreement
-- properties: every concrete evaluation has a matching symbolic valuation.
-- The converse requires an 'ExactFieldProjection' witness; legacy witnesses
-- remain over-approximate and are not reconstructed by 'symSatExt'.
constrainFieldProjection ::
  forall projection rs ci ifs.
  ( Typeable projection,
    Typeable (FieldOwner projection),
    Sym (FieldResult projection)
  ) =>
  SymEnv ->
  FieldWitness projection ->
  ProjBase rs ci ifs (FieldOwner projection) ->
  FieldResult projection ->
  SBV.Symbolic ()
constrainFieldProjection env witness base concrete = do
  symbolic <- memoFree @(FieldResult projection) env (projectionVarKey witness base)
  SBV.constrain (symbolic SBV..== symLit concrete)

-- | Memoized symbolic-variable allocator (EP-42). Looks @name@ up in
-- the env's 'seVarCache'. On a hit, recover the cached SBV variable —
-- checking its representation type matches the requested one, which it
-- always does because a deterministic name maps to exactly one type.
-- On a miss, allocate a fresh 'SBV.free', store it under @name@, and
-- return it. This is what makes repeated reads of the same register or
-- input field share a single solver variable.
memoFree ::
  forall r.
  (Sym r) =>
  SymEnv -> SymVarKey -> SBV.Symbolic (SBV.SBV (SymRep r))
memoFree env key = do
  m <- liftIO (readIORef (seVarCache env))
  case Map.lookup key m of
    Just (SomeSBV (v :: SBV.SBV b)) ->
      case eqTypeRep (typeRep @(SymRep r)) (typeRep @b) of
        Just HRefl -> pure v
        Nothing ->
          -- Unreachable: a name maps to exactly one representation type.
          error ("memoFree: type mismatch for cached variable " <> show key)
    Nothing -> do
      label <- case key of
        RegVar name -> pure ("reg/" <> name)
        InpVar ctorName fieldName ->
          pure ("inp/" <> ctorName <> "/" <> fieldName)
        ProjectionVar {} -> liftIO $ do
          ordinal <- readIORef (seProjectionOrdinal env)
          modifyIORef' (seProjectionOrdinal env) (+ 1)
          pure ("proj/" <> show ordinal)
      v <- symFree @r label
      liftIO $ do
        modifyIORef' (seVarCache env) (Map.insert key (SomeSBV v))
        modifyIORef' (seVarLabels env) (Map.insert key label)
        case key of
          ProjectionVar {} ->
            modifyIORef' (seProjectionKeyOrder env) (++ [key])
          _ -> pure ()
      pure v

-- | Recover the slot name an 'Index' points at by walking to the
-- leaf 'ZIdx' and reading off the 'KnownSymbol' evidence the
-- constructor carries. Used for deterministic SBV variable naming
-- in 'translateTermSym'.
indexName :: forall rs r. Index rs r -> String
indexName (ZIdx @s) = symbolVal (Proxy @s)
indexName (SIdx i) = indexName i

-- | Translate an 'HsPred' to an SBV 'SBool'. The translation is
-- structural for every constructor:
--
--   * 'PTop' / 'PBot' map to @sTrue@ / @sFalse@.
--   * 'PAnd' / 'POr' / 'PNot' map to '(SBV..&&)' / '(SBV..||)' /
--     'SBV.sNot' on the recursive translations.
--   * 'PEq' tries 'discoverSym' on its operand type; on a hit it
--     emits '(.==)' between the two translated terms; on a miss it
--     emits a fresh 'SBool' (the equality is opaque to the solver).
--   * 'PInCtor' emits @seInputCtor .== literal (icName ic)@; the
--     shared 'seInputCtor' makes constructor-mutual-exclusion
--     decidable.
--   * 'PLeftArm' / 'PRightArm' assert the independent 'seInputArm'
--     discriminator.
--   * 'PCmp' tries 'discoverSymOrd' on its operand type; on a hit it
--     emits the matching SBV comparison ('SBV..<' \/ '.<=' \/ '.>' \/
--     '.>=') between the two translated terms; on a miss it emits a
--     fresh 'SBool' (the comparison is opaque to the solver).
translatePred ::
  forall rs ci. SymEnv -> HsPred rs ci -> SBV.Symbolic SBV.SBool
translatePred env = go
  where
    go :: HsPred rs ci -> SBV.Symbolic SBV.SBool
    go PTop = pure SBV.sTrue
    go PBot = pure SBV.sFalse
    go (PAnd p q) = (SBV..&&) <$> go p <*> go q
    go (POr p q) = (SBV..||) <$> go p <*> go q
    go (PNot p) = SBV.sNot <$> go p
    go (PEq a b) = goEq a b
    go (PInCtor ic) = pure (seInputCtor env SBV..== SBV.literal (icName ic))
    go PLeftArm = pure (seInputArm env)
    go PRightArm = pure (SBV.sNot (seInputArm env))
    go (PCmp op a b) = goCmp op a b

    goEq ::
      forall r ifs1 ifs2.
      (Typeable r) =>
      Term rs ci ifs1 r -> Term rs ci ifs2 r -> SBV.Symbolic SBV.SBool
    goEq a b = case discoverSym @r of
      Nothing -> SBV.free "neq"
      Just SymDict -> do
        sa <- translateTermSym env a
        sb <- translateTermSym env b
        pure (sa SBV..== sb)

    goCmp ::
      forall r ifs1 ifs2.
      (Typeable r) =>
      Cmp -> Term rs ci ifs1 r -> Term rs ci ifs2 r -> SBV.Symbolic SBV.SBool
    goCmp op a b = case discoverSymOrd @r of
      Nothing -> SBV.free "cmp" -- sound opaque fallback
      Just SymOrdDict -> do
        sa <- translateTermSym env a
        sb <- translateTermSym env b
        let apply = case op of
              CmpLt -> (SBV..<)
              CmpLe -> (SBV..<=)
              CmpGt -> (SBV..>)
              CmpGe -> (SBV..>=)
        pure (apply sa sb)

-- | A conservative answer from 'verifyPredicate'. The two @Verified@
-- constructors mean every predicate node translated structurally and the
-- solver returned a definite result. Opaque Haskell applications, unsupported
-- carrier dictionaries, solver timeouts or @Unknown@, and solver failures are
-- represented explicitly and must not be treated as successful verification.
data PredicateVerification
  = VerifiedSatisfiable
  | VerifiedUnsatisfiable
  | UnverifiedOpaque
  | UnverifiedSolverUnknown String
  | UnverifiedSolverFailure String
  deriving stock (Eq, Show)

-- | One solver-origin projection key and its checked reconstructed owner.
-- Values stay dynamically typed because one predicate can mention unrelated
-- projection carriers. Use the typed eliminators, never display names, to cast.
data ProjectionModel = ProjectionModel
  { projectionModelDescriptor :: ProjectionDescriptor,
    projectionModelKey :: Dynamic,
    projectionModelOwner :: Dynamic
  }
  deriving stock (Show)

-- | Cast a projection model key using its runtime type evidence.
projectionModelKeyAs :: (Typeable a) => ProjectionModel -> Maybe a
projectionModelKeyAs = fromDynamic . projectionModelKey

-- | Cast a reconstructed projection owner using its runtime type evidence.
projectionModelOwnerAs :: (Typeable a) => ProjectionModel -> Maybe a
projectionModelOwnerAs = fromDynamic . projectionModelOwner

-- | Solver status, translation strength, and checked projection-origin models
-- without changing the compatibility 'PredicateVerification' constructor set.
data PredicateVerificationDetail
  = -- | A satisfying symbolic valuation. Projection models are checked,
    -- path-local key/owner pairs, not complete register/input witnesses.
    PredicateSatisfiable TranslationStrength [ProjectionModel]
  | -- | A definite solver proof of emptiness. For exact projections this proof
    -- is conditional on the consumer's owner-to-domain declaration law.
    PredicateUnsatisfiable TranslationStrength
  | -- | The solver returned an inconclusive status.
    PredicateSolverUnknown TranslationStrength String
  | -- | Translation, solver startup, solver execution, or model decoding failed.
    PredicateSolverFailure TranslationStrength String
  | -- | An admitted model key was rejected by the declared inverse or failed
    -- its getter round trip.
    PredicateProjectionContractViolation
      TranslationStrength
      ProjectionDescriptor
      String
  deriving stock (Show)

data ProjectionUseContext
  = ProjectionEqualityOperand
  | ProjectionOutsideEquality

data TranslationReportEvent
  = TranslationIssueEvent TranslationIssue
  | DirectOwnerReadEvent ProjectionBaseDescriptor
  | ProjectionReadEvent ProjectionDescriptor Bool

data ProjectionBaseUsage = ProjectionBaseUsage
  { projectionUsageDirect :: Bool,
    projectionUsageViews :: [(SomeTypeRep, Bool)]
  }

-- | Explain the complete predicate translation. Per-node support is combined
-- with predicate-wide owner-path analysis so individually exact projections
-- are not promoted when the solver lacks their joint relation.
predicateTranslationReport :: forall rs ci. HsPred rs ci -> TranslationStrength
predicateTranslationReport predicate =
  case reportIssues of
    [] -> ExactTranslation
    firstIssue : remainingIssues ->
      ConservativeOverApproximation (firstIssue :| remainingIssues)
  where
    events = predicateReportEvents predicate predicate
    (reportIssues, _) = foldl consumeEvent ([], Map.empty) events

    consumeEvent ::
      ([TranslationIssue], Map ProjectionBaseDescriptor ProjectionBaseUsage) ->
      TranslationReportEvent ->
      ([TranslationIssue], Map ProjectionBaseDescriptor ProjectionBaseUsage)
    consumeEvent (issues, usages) event = case event of
      TranslationIssueEvent issue -> (appendIssue issue issues, usages)
      DirectOwnerReadEvent base ->
        let usage = Map.findWithDefault (ProjectionBaseUsage False []) base usages
            issues' =
              if null (projectionUsageViews usage)
                then issues
                else appendIssue (DirectAndProjectedOwnerRead base) issues
            usage' = usage {projectionUsageDirect = True}
         in (issues', Map.insert base usage' usages)
      ProjectionReadEvent descriptor exactEvidence ->
        let base = projectionDescriptorBase descriptor
            tag = projectionDescriptorTagType descriptor
            usage = Map.findWithDefault (ProjectionBaseUsage False []) base usages
            conflicts =
              any
                (\(seenTag, seenExact) -> seenTag /= tag || seenExact /= exactEvidence)
                (projectionUsageViews usage)
            issuesWithDirect =
              if projectionUsageDirect usage
                then appendIssue (DirectAndProjectedOwnerRead base) issues
                else issues
            issues' =
              if conflicts
                then appendIssue (ConflictingProjectionViews base) issuesWithDirect
                else issuesWithDirect
            views =
              if (tag, exactEvidence) `elem` projectionUsageViews usage
                then projectionUsageViews usage
                else projectionUsageViews usage ++ [(tag, exactEvidence)]
            usage' = usage {projectionUsageViews = views}
         in (issues', Map.insert base usage' usages)

    appendIssue issue issues
      | issue `elem` issues = issues
      | otherwise = issues ++ [issue]

predicateReportEvents ::
  forall rs ci.
  HsPred rs ci ->
  HsPred rs ci ->
  [TranslationReportEvent]
predicateReportEvents root = go
  where
    go PTop = []
    go PBot = []
    go (PAnd p q) = go p ++ go q
    go (POr p q) = go p ++ go q
    go (PNot p) = go p
    go (PEq (a :: Term rs ci ifs1 r) b) =
      equalitySupport @r
        ++ termReportEvents root ProjectionEqualityOperand a
        ++ termReportEvents root ProjectionEqualityOperand b
    go (PInCtor _) = []
    go PLeftArm = []
    go PRightArm = []
    go (PCmp _ (a :: Term rs ci ifs1 r) b) =
      orderingSupport @r
        ++ termReportEvents root ProjectionOutsideEquality a
        ++ termReportEvents root ProjectionOutsideEquality b

    equalitySupport :: forall (r :: Type). (Typeable r) => [TranslationReportEvent]
    equalitySupport = case discoverSym @r of
      Nothing -> [TranslationIssueEvent (UnsupportedEquality (SomeTypeRep (typeRep @r)))]
      Just SymDict -> []

    orderingSupport :: forall (r :: Type). (Typeable r) => [TranslationReportEvent]
    orderingSupport = case discoverSymOrd @r of
      Nothing -> [TranslationIssueEvent (UnsupportedOrdering (SomeTypeRep (typeRep @r)))]
      Just SymOrdDict -> []

termReportEvents ::
  forall rs ci ifs r.
  (Typeable r) =>
  HsPred rs ci ->
  ProjectionUseContext ->
  Term rs ci ifs r ->
  [TranslationReportEvent]
termReportEvents _root _context (TLit _) = []
termReportEvents _root _context (TOpaqueLit _) = []
termReportEvents _root _context (TReg ix) =
  [DirectOwnerReadEvent (registerBaseDescriptor @r ix)]
termReportEvents _root _context (TInpCtorField ic ix) =
  [DirectOwnerReadEvent (inputBaseDescriptor @r ic ix)]
termReportEvents _root _context (TApp1 _ _) =
  [TranslationIssueEvent OpaqueApplication]
termReportEvents _root _context (TApp2 _ _ _) =
  [TranslationIssueEvent OpaqueApplication]
termReportEvents root _context (TArith _ a b) =
  arithmeticSupport @r
    ++ termReportEvents root ProjectionOutsideEquality a
    ++ termReportEvents root ProjectionOutsideEquality b
  where
    arithmeticSupport :: forall (a :: Type). (Typeable a) => [TranslationReportEvent]
    arithmeticSupport = case discoverSymNum @a of
      Nothing -> [TranslationIssueEvent (UnsupportedArithmetic (SomeTypeRep (typeRep @a)))]
      Just SymNumDict -> []
termReportEvents
  root
  context
  (TFieldProj (witness :: FieldWitness projection) base) =
    relationIssue
      ++ evidenceIssues
      ++ inputGuardIssue
      ++ [ProjectionReadEvent descriptor exactEvidence]
    where
      descriptor = projectionDescriptor witness base
      relationIssue = case context of
        ProjectionEqualityOperand -> []
        ProjectionOutsideEquality ->
          [TranslationIssueEvent (ProjectionUsedOutsideEquality descriptor)]
      (evidenceIssues, exactEvidence) = case fieldWitnessDomain witness of
        Nothing ->
          ([TranslationIssueEvent (UnconstrainedProjection descriptor)], False)
        Just domain -> case discoverSym @(FieldResult projection) of
          Nothing -> ([], False)
          Just SymDict -> case projectionDomainSupport domain of
            Nothing -> ([], True)
            Just reason ->
              ( [TranslationIssueEvent (UnsupportedProjectionDomain descriptor reason)],
                False
              )
      inputGuardIssue = case projectionDescriptorBase descriptor of
        ProjectionBaseDescriptor {projectionBaseKind = ProjectionRegisterOwner} -> []
        ProjectionBaseDescriptor
          { projectionBaseKind = ProjectionInputOwner,
            projectionBaseConstructorName = Just ctorName
          }
            | predicateImpliesInCtor ctorName root -> []
            | otherwise ->
                [TranslationIssueEvent (UnguardedProjectionInputRead descriptor)]
        ProjectionBaseDescriptor {projectionBaseKind = ProjectionInputOwner} ->
          [TranslationIssueEvent (UnguardedProjectionInputRead descriptor)]

projectionDomainSupport ::
  forall r.
  (Sym r) =>
  ProjectionDomain r ->
  Maybe String
projectionDomainSupport ProjectionWhole
  | symbolicWholeCarrierExact @r = Nothing
  | otherwise = Just "whole carrier is not representation-exact"
projectionDomainSupport (ProjectionFinite values)
  | all projectionLiteralExact values = Nothing
  | otherwise = Just "finite domain contains a non-representable symbolic literal"
projectionDomainSupport ProjectionText {} = Nothing

registerBaseDescriptor ::
  forall r rs.
  (Typeable r) =>
  Index rs r ->
  ProjectionBaseDescriptor
registerBaseDescriptor ix =
  ProjectionBaseDescriptor
    { projectionBaseKind = ProjectionRegisterOwner,
      projectionBaseConstructorName = Nothing,
      projectionBaseSlotName = indexName ix,
      projectionBasePosition = indexPosition ix,
      projectionBaseOwnerType = SomeTypeRep (typeRep @r)
    }

inputBaseDescriptor ::
  forall r ci ifs.
  (Typeable r) =>
  InCtor ci ifs ->
  Index ifs r ->
  ProjectionBaseDescriptor
inputBaseDescriptor ic ix =
  ProjectionBaseDescriptor
    { projectionBaseKind = ProjectionInputOwner,
      projectionBaseConstructorName = Just (icName ic),
      projectionBaseSlotName = indexName ix,
      projectionBasePosition = indexPosition ix,
      projectionBaseOwnerType = SomeTypeRep (typeRep @r)
    }

projectionDescriptor ::
  forall projection rs ci ifs.
  ( FieldProjection projection,
    KnownSymbol (FieldName projection),
    Typeable projection,
    Typeable (FieldOwner projection),
    Typeable (FieldResult projection)
  ) =>
  FieldWitness projection ->
  ProjBase rs ci ifs (FieldOwner projection) ->
  ProjectionDescriptor
projectionDescriptor witness base =
  ProjectionDescriptor
    { projectionDescriptorBase = case base of
        PBReg ix -> registerBaseDescriptor @(FieldOwner projection) ix
        PBInp ic ix -> inputBaseDescriptor @(FieldOwner projection) ic ix,
      projectionDescriptorPath = fieldProjectionPath witness base,
      projectionDescriptorShape = fieldShapeId (Proxy @projection),
      projectionDescriptorTagType = SomeTypeRep (typeRep @projection),
      projectionDescriptorOwnerType = SomeTypeRep (typeRep @(FieldOwner projection)),
      projectionDescriptorResultType = SomeTypeRep (typeRep @(FieldResult projection))
    }

-- | Whether the predicate-wide report contains no translation issue.
predicateTranslationExact :: HsPred rs ci -> Bool
predicateTranslationExact predicate = case predicateTranslationReport predicate of
  ExactTranslation -> True
  ConservativeOverApproximation _ -> False

data PredicateSolve = PredicateSolve
  { predicateSolveStrength :: TranslationStrength,
    predicateSolveEnvironment :: SymEnv,
    predicateSolveResult :: SBV.SatResult
  }

runPredicateSolver ::
  HsPred rs ci ->
  (SymEnv -> SBV.Symbolic ()) ->
  IO (Either String PredicateSolve)
runPredicateSolver predicate addConstraints = do
  environmentRef <- newIORef Nothing
  attempt <- try @SomeException $ SBV.sat $ do
    environment <- mkSymEnv
    liftIO (writeIORef environmentRef (Just environment))
    translated <- translatePred environment predicate
    addConstraints environment
    pure translated
  case attempt of
    Left failure -> pure (Left (displayException failure))
    Right result -> do
      maybeEnvironment <- readIORef environmentRef
      pure $ case maybeEnvironment of
        Nothing -> Left "solver translation did not publish its environment"
        Just environment ->
          Right
            PredicateSolve
              { predicateSolveStrength = predicateTranslationReport predicate,
                predicateSolveEnvironment = environment,
                predicateSolveResult = result
              }

-- | Solve once and preserve status, predicate-global translation strength,
-- and checked exact projection models. This can report definite results for a
-- conservative translation without promoting them through 'verifyPredicate'.
verifyPredicateDetailed :: HsPred rs ci -> IO PredicateVerificationDetail
verifyPredicateDetailed predicate = do
  solved <- runPredicateSolver predicate (const (pure ()))
  case solved of
    Left failure ->
      pure (PredicateSolverFailure (predicateTranslationReport predicate) failure)
    Right PredicateSolve {predicateSolveStrength = strength, predicateSolveEnvironment = environment, predicateSolveResult = result} ->
      decodeDetailedResult strength environment result

decodeDetailedResult ::
  TranslationStrength ->
  SymEnv ->
  SBV.SatResult ->
  IO PredicateVerificationDetail
decodeDetailedResult strength environment result@(SBV.SatResult status) =
  case status of
    SBV.Satisfiable {} -> do
      extracted <- extractProjectionModels environment result
      pure $ case extracted of
        Left (descriptor, failure) ->
          PredicateProjectionContractViolation strength descriptor failure
        Right projectionModels -> PredicateSatisfiable strength projectionModels
    SBV.Unsatisfiable {} -> pure (PredicateUnsatisfiable strength)
    SBV.Unknown {} -> pure (PredicateSolverUnknown strength "solver returned Unknown")
    SBV.ProofError {} -> pure (PredicateSolverFailure strength "solver returned ProofError")
    SBV.DeltaSat {} -> pure (PredicateSolverUnknown strength "solver returned DeltaSat")
    SBV.SatExtField {} -> pure (PredicateSolverUnknown strength "solver returned SatExtField")

extractProjectionModels ::
  SymEnv ->
  SBV.SatResult ->
  IO (Either (ProjectionDescriptor, String) [ProjectionModel])
extractProjectionModels environment result = do
  orderedKeys <- readIORef (seProjectionKeyOrder environment)
  bindings <- readIORef (seProjectionBindings environment)
  pure $ do
    projectionModels <- forM orderedKeys $ \key -> case Map.lookup key bindings of
      Nothing -> Right Nothing
      Just (SomeProjectionBinding descriptor label witness) ->
        case SBV.getModelValue label result of
          Nothing -> Left (descriptor, "solver model omitted the projection value")
          Just symbolicRepresentation ->
            let concreteKey = fromSym symbolicRepresentation
             in case checkFieldProjectionKey witness concreteKey of
                  Left lawFailure -> Left (descriptor, show lawFailure)
                  Right owner ->
                    Right
                      ( Just
                          ProjectionModel
                            { projectionModelDescriptor = descriptor,
                              projectionModelKey = toDyn concreteKey,
                              projectionModelOwner = toDyn owner
                            }
                      )
    pure [model | Just model <- projectionModels]

-- | Conservative compatibility projection of 'verifyPredicateDetailed'.
verifyPredicate :: HsPred rs ci -> IO PredicateVerification
verifyPredicate predicate = do
  detail <- verifyPredicateDetailed predicate
  pure $ case detail of
    PredicateSatisfiable ExactTranslation _ -> VerifiedSatisfiable
    PredicateUnsatisfiable ExactTranslation -> VerifiedUnsatisfiable
    PredicateSatisfiable ConservativeOverApproximation {} _ -> UnverifiedOpaque
    PredicateUnsatisfiable ConservativeOverApproximation {} -> UnverifiedOpaque
    PredicateSolverUnknown _ message -> UnverifiedSolverUnknown message
    PredicateSolverFailure _ message -> UnverifiedSolverFailure message
    PredicateProjectionContractViolation _ _ message ->
      UnverifiedSolverFailure ("projection contract violation: " <> message)

-- * Symbolic predicate wrapper ----------------------------------------------

-- | A newtype wrapper over 'HsPred' that selects the v2 'BoolAlg'
-- instance (with SBV-backed analyses) instead of the v1 syntactic
-- one. The v1 'BoolAlg HsPred' instance in "Keiki.Core" stays
-- unchanged for back-compat; consumers that want symbolic answers
-- wrap with 'SymPred'.
--
-- The 'SymPred' constructor is exported so callers can lift
-- @userReg@-style transducers via 'fmap'-like adapters; M6 of EP-2
-- ships 'withSymPred' which re-tags every edge guard.
newtype SymPred (rs :: [Slot]) (ci :: Type) = SymPred {unSymPred :: HsPred rs ci}

-- | A 'SymTransducer' whose guard carrier is the SBV-backed 'SymPred'.
-- The symbolic analogue of 'Keiki.Core.Guarded'.
type SymGuarded rs s ci co = SymTransducer (SymPred rs ci) rs s ci co

-- | The v2 'BoolAlg' instance. The five structural methods compose
-- 'HsPred' constructors. 'models' delegates to the v1 'evalPred'
-- (concrete evaluation, no solver call). 'isBot' routes through
-- 'symIsBot', which dispatches to an external z3 process via SBV and
-- 'unsafePerformIO'. Solver failures are caught and conservatively mean "not
-- proved empty". Witness extraction
-- ('Keiki.Core.sat') lives in the separate 'Sat' instance below, which
-- carries the 'ExtractRegFile' / 'KnownInCtors' evidence it needs; this
-- instance is deliberately /unconstrained/ so the witness-free analyses
-- ('isSingleValuedSym') keep type-checking on register-file-existential
-- carriers and on @ci@ types with no 'KnownInCtors'.
instance BoolAlg (SymPred rs ci) (RegFile rs, ci) where
  top = SymPred PTop
  bot = SymPred PBot
  conj (SymPred p) (SymPred q) = SymPred (PAnd p q)
  disj (SymPred p) (SymPred q) = SymPred (POr p q)
  neg (SymPred p) = SymPred (PNot p)
  models (SymPred p) (regs, ci) = evalPred p regs ci
  isBot (SymPred p) = symIsBot p

-- | Witness extraction for the SBV-backed carrier (EP-44, MasterPlan
-- 12). @'sat' (SymPred p)@ returns the same real, forceable witness as
-- 'symSatExt' — a concrete @(RegFile rs, ci)@ reconstructed from the
-- solver model. The constraints @ExtractRegFile rs@ / @KnownInCtors ci@
-- live here (not on 'BoolAlg') so only witness extraction pays for them.
instance
  (ExtractRegFile rs, KnownInCtors ci) =>
  Sat (SymPred rs ci) (RegFile rs, ci)
  where
  sat (SymPred p) = symSatExt p

-- * Solver-backed analyses --------------------------------------------------

-- | Interpret a solver result for emptiness ('Keiki.Core.isBot') purposes.
-- Returns 'True' only for a definite 'SBV.Unsatisfiable' result. Every other
-- result means "not provably empty": that includes 'SBV.Satisfiable',
-- 'SBV.Unknown' (for example, a timeout or an incomplete string-theory query),
-- 'SBV.ProofError', 'SBV.DeltaSat', and 'SBV.SatExtField'. This is the
-- conservative direction for callers that use emptiness to bless two guards as
-- disjoint or to diagnose an edge as dead.
satResultIsProvablyUnsat :: SBV.SatResult -> Bool
satResultIsProvablyUnsat (SBV.SatResult result) = case result of
  SBV.Unsatisfiable {} -> True
  SBV.Satisfiable {} -> False
  SBV.DeltaSat {} -> False
  SBV.SatExtField {} -> False
  SBV.Unknown {} -> False
  SBV.ProofError {} -> False

-- | Symbolic emptiness check. Translates the predicate to an SBV expression and
-- asks z3 whether it is definitely unsatisfiable. A 'True' result proves the
-- predicate is bot; 'False' means either satisfiable or that the solver gave up.
-- The latter can occur for 'Text' guards translated through z3's string theory.
-- This conservative failure direction may surface an overlap warning but never
-- blesses an uncertain pair as disjoint. Solver startup and execution failures
-- are caught and conservatively return 'False'. The wrapper is justified
-- because each query is deterministic for a given predicate and side-effect-free
-- outside the solver process. When @p@ contains 'exactFieldWitness', a 'True'
-- result is conditional on the declaration laws documented by
-- 'ExactFieldProjection'; an under-declared image can otherwise create false
-- UNSAT without producing a model that Keiki could check.
{-# NOINLINE symIsBot #-}
symIsBot :: HsPred rs ci -> Bool
symIsBot p = unsafePerformIO $ do
  solved <- runPredicateSolver p (const (pure ()))
  pure $ case solved of
    Left _ -> False
    Right result -> satResultIsProvablyUnsat (predicateSolveResult result)

-- * Single-valuedness ------------------------------------------------------

-- | A transducer is /single-valued/ when, at every reachable
-- vertex, at most one outgoing edge's guard is satisfied for any
-- given input. The check decomposes into "for every vertex @s@, for
-- every distinct pair @(e1, e2)@ of outgoing edges, is the
-- conjunction of their guards 'isBot'?". The function is
-- 'BoolAlg'-polymorphic; precision depends on the chosen 'isBot'
-- implementation. With 'SymPred', this is the v2 SBV-backed
-- decision; with the v1 'HsPred' instance the answer is the v1
-- syntactic over-approximation. A solver 'SBV.Unknown' is conservatively treated
-- as a possibly overlapping pair, so this function returns 'False'.
isSingleValuedSym ::
  forall phi rs s ci co.
  (BoolAlg phi (RegFile rs, ci), Bounded s, Enum s) =>
  SymTransducer phi rs s ci co ->
  Bool
isSingleValuedSym t = all vertexSV [minBound .. maxBound]
  where
    vertexSV :: s -> Bool
    vertexSV s =
      let es = edgesOut t s
          ies = zip [(0 :: Int) ..] es
          -- Only 'Live' edges compete in forward dispatch; guard
          -- overlap with or between 'ReplayOnly' edges cannot cause
          -- forward ambiguity.
          pairs =
            [ (e1, e2)
            | (i, e1) <- ies,
              (j, e2) <- ies,
              i < j,
              mode e1 == Live,
              mode e2 == Live
            ]
       in all (\(e1, e2) -> isBot (guard e1 `conj` guard e2)) pairs

-- | Lift a transducer's edges from the v1 'HsPred' guard carrier to
-- the v2 'SymPred' carrier so 'isSingleValuedSym' (or any other
-- 'BoolAlg'-polymorphic analysis) sees the SBV-backed instance.
-- The control graph and update / output terms are unchanged.
withSymPred ::
  SymTransducer (HsPred rs ci) rs s ci co ->
  SymTransducer (SymPred rs ci) rs s ci co
withSymPred t =
  SymTransducer
    { edgesOut = \s -> map liftEdge (edgesOut t s),
      initial = initial t,
      initialRegs = initialRegs t,
      isFinal = isFinal t
    }
  where
    liftEdge ::
      Edge (HsPred rs ci) rs ci co s ->
      Edge (SymPred rs ci) rs ci co s
    liftEdge e@Edge {update = u} =
      Edge
        { guard = SymPred (guard e),
          update = u,
          output = output e,
          target = target e,
          mode = mode e
        }

-- * Solver-backed validation diagnostics (EP-56) ---------------------------

-- | One live outgoing-edge pair and the single detailed solver result used to
-- decide its compatibility warning.
data DeterminismAnalysisDetail s = DeterminismAnalysisDetail
  { determinismDetailEdgeA :: EdgeRef s,
    determinismDetailEdgeB :: EdgeRef s,
    determinismDetailVerification :: PredicateVerificationDetail
  }

-- | Solve every live pair once, retaining edge attribution and full status.
checkTransitionDeterminismSymDetailed ::
  (Bounded s, Enum s) =>
  SymTransducer (HsPred rs ci) rs s ci co ->
  IO [DeterminismAnalysisDetail s]
checkTransitionDeterminismSymDetailed transducer =
  sequence
    [ DeterminismAnalysisDetail
        (EdgeRef {edgeSource = source, edgeIndex = firstIndex})
        (EdgeRef {edgeSource = source, edgeIndex = secondIndex})
        <$> verifyPredicateDetailed (PAnd (guard firstEdge) (guard secondEdge))
    | source <- [minBound .. maxBound],
      let indexedEdges = zip [(0 :: Int) ..] (edgesOut transducer source),
      (firstIndex, firstEdge) <- indexedEdges,
      (secondIndex, secondEdge) <- indexedEdges,
      firstIndex < secondIndex,
      mode firstEdge == Live,
      mode secondEdge == Live
    ]

-- | Solver-backed determinism diagnostic. Lifts the transducer with
-- 'withSymPred' and runs the 'BoolAlg'-polymorphic 'checkTransitionDeterminism'
-- at the 'SymPred' carrier, whose 'isBot' is the exact z3 decision. Unlike the
-- pure path in 'validateTransducer', this catches register-value-dependent and
-- other non-syntactic overlaps. A solver 'SBV.Unknown' conservatively produces a
-- warning rather than blessing the pair as disjoint. Requires z3 on @PATH@.
checkTransitionDeterminismSym ::
  (Bounded s, Enum s, Show s) =>
  SymTransducer (HsPred rs ci) rs s ci co ->
  [DeterminismWarning s]
checkTransitionDeterminismSym transducer = unsafePerformIO $ do
  details <- checkTransitionDeterminismSymDetailed transducer
  pure
    [ DeterminismWarning
        { dwSource = edgeSource firstRef,
          dwEdgeA = edgeIndex firstRef,
          dwEdgeB = edgeIndex secondRef,
          dwDetail =
            "edges #"
              <> show (edgeIndex firstRef)
              <> " and #"
              <> show (edgeIndex secondRef)
              <> " out of "
              <> show (edgeSource firstRef)
              <> " may overlap (symbolic)"
        }
    | DeterminismAnalysisDetail firstRef secondRef verification <- details,
      not (verificationIsDefinitelyUnsatisfiable verification)
    ]
{-# NOINLINE checkTransitionDeterminismSym #-}

-- | One edge and the detailed result used to decide whether it is dead in
-- isolation.
data DeadEdgeAnalysisDetail s = DeadEdgeAnalysisDetail
  { deadEdgeDetailEdge :: EdgeRef s,
    deadEdgeDetailVerification :: PredicateVerificationDetail
  }

-- | Solve every edge guard once and retain its attribution and full status.
checkDeadEdgesSymDetailed ::
  (Bounded s, Enum s) =>
  SymTransducer (HsPred rs ci) rs s ci co ->
  IO [DeadEdgeAnalysisDetail s]
checkDeadEdgesSymDetailed transducer =
  sequence
    [ DeadEdgeAnalysisDetail
        (EdgeRef {edgeSource = source, edgeIndex = edgeNumber})
        <$> verifyPredicateDetailed (guard edge)
    | source <- [minBound .. maxBound],
      (edgeNumber, edge) <- zip [(0 :: Int) ..] (edgesOut transducer source)
    ]

-- | Symbolic dead-edge sketch. Flags edges whose guard is unsatisfiable
-- /in isolation/ (via 'symIsBot'), which the structural 'checkDeadEdges'
-- misses unless the guard is literally 'PBot' (e.g. @amount > 0 && amount < 0@).
-- It does NOT compute the register configurations reachable at each vertex, so
-- it still cannot catch the FieldResource case (a guard satisfiable in
-- isolation but never under the registers reachable there); that needs a full
-- reachable-state fixpoint and is left as future work. A solver 'SBV.Unknown'
-- does not diagnose an edge as dead, because it is not proof of unsatisfiability.
-- Requires z3 on @PATH@.
checkDeadEdgesSym ::
  (Bounded s, Enum s) =>
  SymTransducer (HsPred rs ci) rs s ci co ->
  [DeadEdgeWarning s]
checkDeadEdgesSym transducer = unsafePerformIO $ do
  details <- checkDeadEdgesSymDetailed transducer
  pure
    [ DeadEdgeWarning
        edgeRef
        "guard is unsatisfiable in isolation (symbolic)"
    | DeadEdgeAnalysisDetail edgeRef verification <- details,
      verificationIsDefinitelyUnsatisfiable verification
    ]
{-# NOINLINE checkDeadEdgesSym #-}

verificationIsDefinitelyUnsatisfiable :: PredicateVerificationDetail -> Bool
verificationIsDefinitelyUnsatisfiable PredicateUnsatisfiable {} = True
verificationIsDefinitelyUnsatisfiable _ = False

-- * Witness extraction -----------------------------------------------------

-- | Materialize a 'RegFile' from a name-keyed reader. The reader's input is a
-- slot name; its output is a value of any 'Sym'-supported type. The reader is
-- total: callers fall back to 'symDefault' for slots absent from the model.
-- 'extractRegFileAt' additionally supplies zero-based structural position so
-- exact projection owners remain distinct even when diagnostic names repeat.
--
-- Two instances cover the slot list:
--
--   * @ExtractRegFile \'[]@ — return 'RNil' regardless of the reader.
--   * @ExtractRegFile (\'(s, t) ': rs)@ — read the head slot's name
--     via the reader, recurse on the tail, build an 'RCons'.
--
-- The instance constraints @KnownSymbol s@ and @Sym t@ make this
-- automatic for any concrete slot list whose value types are in the
-- curated 'Sym' registry ('Bool', 'Int', 'Integer', 'Natural', 'Text',
-- 'UTCTime'). User Registration's 'UserRegRegs' shape qualifies
-- without further user code.
class ExtractRegFile (rs :: [Slot]) where
  extractRegFile :: (forall r. (Sym r) => String -> r) -> RegFile rs

  -- | Position-aware private traversal used to install exact reconstructed
  -- projection owners. The default preserves source compatibility for custom
  -- instances by delegating to their existing name-only implementation.
  extractRegFileAt ::
    Int ->
    (forall r. (Sym r) => Int -> String -> r) ->
    RegFile rs
  extractRegFileAt _ reader = extractRegFile (reader (-1))

instance ExtractRegFile '[] where
  extractRegFile _ = RNil
  extractRegFileAt _ _ = RNil

instance
  ( KnownSymbol s,
    Sym t,
    ExtractRegFile rs
  ) =>
  ExtractRegFile ('(s, t) ': rs)
  where
  extractRegFile reader =
    RCons
      (Proxy @s)
      (reader @t (symbolVal (Proxy @s)))
      (extractRegFile @rs reader)
  extractRegFileAt position reader =
    RCons
      (Proxy @s)
      (reader @t position (symbolVal (Proxy @s)))
      (extractRegFileAt @rs (position + 1) reader)

-- | Existential wrapper around an 'InCtor' that hides the
-- input-field slot list. The hidden 'ExtractRegFile' constraint lets
-- 'symSatExt' rebuild the input register file once the constructor
-- tag is known from the SBV model.
data SomeInCtor (ci :: Type) where
  SomeInCtor :: (ExtractRegFile ifs) => InCtor ci ifs -> SomeInCtor ci

-- | A 'ci' type whose set of 'InCtor's is statically known. Each
-- 'SomeInCtor' bag entry pairs an 'InCtor' value with the
-- 'ExtractRegFile' evidence its field-list shape requires.
--
-- For the User Registration aggregate, the instance is a five-line
-- list pairing the existing @inCtorStart@ … @inCtorContinue@
-- declarations:
--
-- > instance KnownInCtors UserCmd where
-- >   allInCtors =
-- >     [ SomeInCtor inCtorStart
-- >     , SomeInCtor inCtorConfirm
-- >     , SomeInCtor inCtorResend
-- >     , SomeInCtor inCtorGdpr
-- >     , SomeInCtor inCtorContinue
-- >     ]
--
-- Future work: a Generic-derived default via 'GHasCtor' so users
-- get the instance for free with @deriving (Generic)@. Out of scope
-- for EP-9 because the explicit list is already one line per
-- constructor.
class KnownInCtors ci where
  allInCtors :: [SomeInCtor ci]

-- | The single zero-field constructor of @()@ — a transducer whose
-- command alphabet carries no information. Lets 'symSatExt' (and hence
-- 'Keiki.Core.sat') reconstruct a @()@ witness for predicates over
-- @SymPred rs ()@.
inCtorUnit :: InCtor () '[]
inCtorUnit =
  InCtor
    { icName = "()",
      icMatch = \() -> Just RNil,
      icBuild = \RNil -> ()
    }

-- | @()@ has one constructor; its 'allInCtors' is the singleton
-- 'inCtorUnit'. Added by EP-44 so @sat@ over a no-command carrier
-- (@SymPred '[] ()@) yields a real @(RNil, ())@ witness.
instance KnownInCtors () where
  allInCtors = [SomeInCtor inCtorUnit]

-- * symSatExt ---------------------------------------------------------------

-- | Symbolic satisfiability with full witness extraction. On a satisfiable
-- translation, reconstructs a candidate @(regs, cmd)@ from the SBV model and
-- returns it only when concrete 'models' evaluation confirms the predicate.
-- Thus @models p (regs, cmd) == True@ holds unconditionally for every returned
-- witness. Escape-hatch terms ('TApp1', 'TApp2', and 'PEq' over a non-'Sym'
-- operand type) and legacy over-approximate field projections can make the
-- solver's assignment impossible for the reconstructed values; such a
-- candidate is discarded. Exact projections contribute checked, path-local
-- owner overrides when their predicate-wide relation is safe. Every decoded
-- key is validated against its domain, inverse, and getter round-trip before
-- any override is installed.
--
-- /Repeated reads/ of the same register or input field are handled
-- correctly: since EP-42 'translateTermSym' memoizes 'TReg' \/
-- 'TInpCtorField' reads (see 'SymEnv'\'s 'seVarCache'), so two reads of
-- @#x@ share one SBV variable and the by-name witness extraction
-- satisfies @proj #x .== proj #x@-style structural equality.
--
-- The model's input-constructor tag is confined to the known
-- constructor domain (@KnownInCtors ci@), so a predicate without a
-- 'PInCtor' atom still reconstructs a real command (the first/only
-- constructor) rather than failing to match an arbitrary solver string.
--
-- 'symSatExt' is /pure/ via 'unsafePerformIO' on the SBV solver
-- call (deterministic for a given predicate, side-effect-free
-- outside the solver process). Since EP-44 it /is/ the implementation
-- of the 'Keiki.Core.Sat' method 'sat' on 'SymPred' (via the
-- @Sat (SymPred …)@ instance, which carries the 'ExtractRegFile' /
-- 'KnownInCtors' evidence the witness-free 'BoolAlg' class cannot). A 'Nothing'
-- result means only that no concrete witness was recovered: the predicate may
-- be unsatisfiable, the solver may have returned 'SBV.Unknown', or a
-- satisfiable over-approximate or opaque assignment may have failed the
-- concrete recheck. An input-field read used without its constructor guard is
-- also discarded if concrete evaluation raises its guard-violation error.
-- Callers must not treat 'Nothing' as a proof of emptiness; 'symIsBot' returns
-- 'True' only for that proof.
{-# NOINLINE symSatExt #-}
symSatExt ::
  forall rs ci.
  ( ExtractRegFile rs,
    KnownInCtors ci
  ) =>
  HsPred rs ci -> Maybe (RegFile rs, ci)
symSatExt p = unsafePerformIO $ do
  solved <- runPredicateSolver p constrainKnownConstructors
  case solved of
    Left _ -> pure Nothing
    Right PredicateSolve {predicateSolveStrength = strength, predicateSolveEnvironment = environment, predicateSolveResult = result}
      | SBV.modelExists result -> do
          extracted <- extractProjectionModels environment result
          case extracted of
            Left _ -> pure Nothing
            Right projectionModels -> do
              let safeProjectionModels =
                    filter
                      (projectionModelRelationSafe strength)
                      projectionModels
                  candidate = do
                    ctorTag <- SBV.getModelValue "inputCtor" result
                    let regReader :: forall r. (Sym r) => Int -> String -> r
                        regReader position name =
                          maybe
                            (readModel result ("reg/" <> name))
                            id
                            ( projectionOwnerOverride @r
                                safeProjectionModels
                                ProjectionBaseDescriptor
                                  { projectionBaseKind = ProjectionRegisterOwner,
                                    projectionBaseConstructorName = Nothing,
                                    projectionBaseSlotName = name,
                                    projectionBasePosition = position,
                                    projectionBaseOwnerType = SomeTypeRep (typeRep @r)
                                  }
                            )
                        registers = extractRegFileAt @rs 0 regReader
                        inputReader ::
                          forall r.
                          (Sym r) =>
                          String ->
                          Int ->
                          String ->
                          r
                        inputReader ctorName position fieldName =
                          maybe
                            (readModel result ("inp/" <> ctorName <> "/" <> fieldName))
                            id
                            ( projectionOwnerOverride @r
                                safeProjectionModels
                                ProjectionBaseDescriptor
                                  { projectionBaseKind = ProjectionInputOwner,
                                    projectionBaseConstructorName = Just ctorName,
                                    projectionBaseSlotName = fieldName,
                                    projectionBasePosition = position,
                                    projectionBaseOwnerType = SomeTypeRep (typeRep @r)
                                  }
                            )
                    command <-
                      pickCi @ci
                        ctorTag
                        inputReader
                    pure (registers, command)
              case candidate of
                Nothing -> pure Nothing
                Just witness -> do
                  checked <- try @ErrorCall (evaluate (models (SymPred p) witness))
                  pure $ case checked of
                    Right True -> Just witness
                    Right False -> Nothing
                    Left _ -> Nothing
      | otherwise -> pure Nothing
  where
    constrainKnownConstructors environment = do
      let ctorNames = [icName ic | SomeInCtor ic <- allInCtors @ci]
      when (not (null ctorNames)) $
        SBV.constrain $
          SBV.sOr
            [ seInputCtor environment SBV..== SBV.literal name
            | name <- ctorNames
            ]

projectionOwnerOverride ::
  forall r.
  (Typeable r) =>
  [ProjectionModel] ->
  ProjectionBaseDescriptor ->
  Maybe r
projectionOwnerOverride projectionModels base =
  listToMaybe
    [ owner
    | projectionModel <- projectionModels,
      projectionDescriptorBase (projectionModelDescriptor projectionModel) == base,
      Just owner <- [projectionModelOwnerAs projectionModel]
    ]

projectionModelRelationSafe :: TranslationStrength -> ProjectionModel -> Bool
projectionModelRelationSafe strength projectionModel =
  all (not . invalidates base) (translationIssues strength)
  where
    base = projectionDescriptorBase (projectionModelDescriptor projectionModel)
    invalidates expected (ConflictingProjectionViews actual) = expected == actual
    invalidates expected (DirectAndProjectedOwnerRead actual) = expected == actual
    invalidates _ _ = False

translationIssues :: TranslationStrength -> [TranslationIssue]
translationIssues ExactTranslation = []
translationIssues (ConservativeOverApproximation issues) = toList issues

-- | Look up @name@ in @res@'s SBV model; on a hit return @fromSym@
-- of the model value, on a miss return @symDefault@. Used by
-- 'symSatExt' to convert SBV's typed model lookups into Haskell
-- values for any 'Sym'-supported slot type.
readModel :: forall r. (Sym r) => SBV.SatResult -> String -> r
readModel res name =
  case SBV.getModelValue name res :: Maybe (SymRep r) of
    Just rep -> fromSym rep
    Nothing -> symDefault

-- | Walk the 'allInCtors' list, find the entry whose 'icName'
-- matches the model's input-constructor tag, then 'extractRegFile'
-- over the matched 'InCtor''s field list and call 'icBuild' to
-- assemble a @ci@. Returns 'Nothing' when no entry matches the tag
-- — this is the case when the predicate over-allocated the
-- @"inputCtor"@ slot (the solver picked a string that isn't any
-- known constructor name, which can happen if the predicate
-- doesn't include any 'PInCtor' atom).
pickCi ::
  forall ci.
  (KnownInCtors ci) =>
  String ->
  (forall r. (Sym r) => String -> Int -> String -> r) ->
  Maybe ci
pickCi tag readField = go (allInCtors @ci)
  where
    go [] = Nothing
    go (SomeInCtor ic@InCtor {} : rest)
      | icName ic == tag =
          let regs = extractRegFileAt 0 (readField (icName ic))
           in Just (icBuild ic regs)
      | otherwise = go rest
