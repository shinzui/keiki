{-# LANGUAGE TypeAbstractions #-}
{-# LANGUAGE TypeFamilies #-}

-- | SBV-backed symbolic surface for 'Keiki.Core' predicates.
--
-- This module is the v2 symbolic upgrade of the v1 best-effort
-- @BoolAlg HsPred@ instance pinned by EP-4 of MasterPlan 1's
-- Outcomes & Retrospective. After EP-2 of MasterPlan 2, asking
-- "are these two edge guards mutually exclusive?" is a mechanical
-- question with a precise answer; the synthesis-§7 invariant that
-- edge guards form an /effective/ Boolean algebra is honored at v2.
--
-- The module re-exports everything from "Keiki.Core" so a single
-- import is sufficient for callers that need both the pure and the
-- symbolic surfaces. See @docs/research/sbv-boolalg-design.md@ for
-- the design rationale.
--
-- Milestones implemented in this revision (through M5 of EP-2):
--
--   * The 'Sym' typeclass and instances for 'Bool', 'Int', 'Integer',
--     'Text', 'UTCTime', and the fixed-width integers 'Word8' \/
--     'Word16' \/ 'Word32' \/ 'Word64' \/ 'Int32' \/ 'Int64' (the
--     last group added by EP-41 so money and count registers are
--     solver-visible).
--   * 'SymEnv' carrying the shared symbolic input-constructor tag and
--     (since EP-42 of MasterPlan 12) an 'IORef' memo cache that shares
--     one SBV variable per register slot / input field across repeated
--     reads, so @proj #x .== proj #x@ is valid, not merely satisfiable.
--   * 'translateTermSym' / 'translatePred' walking 'Term' / 'HsPred'
--     into SBV expressions.
--   * 'discoverSym' — runtime dispatch from 'Typeable' to 'Sym'
--     evidence over the curated registry of supported types.
--   * 'SymPred' newtype wrapper plus its 'BoolAlg' instance with
--     structural 'top' / 'bot' / 'conj' / 'disj' / 'neg', a 'models'
--     that re-uses the v1 'evalPred' (concrete evaluation, no solver
--     call), and an 'isBot' backed by z3.
--   * 'symIsBot' — pure-API wrapper around SBV's solver call (via
--     'unsafePerformIO' + NOINLINE) that 'SymPred''s 'isBot' routes
--     through, so the v1 syntactic over-approximation is replaced with a
--     precise symbolic answer.
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

    -- * Translation
    SymEnv (..),
    mkSymEnv,
    translateTermSym,
    translatePred,

    -- * Symbolic predicate wrapper
    SymPred (..),
    SymGuarded,

    -- * Solver-backed analyses
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
    checkTransitionDeterminismSym,
    checkDeadEdgesSym,

    -- * Re-exports
    module Keiki.Core,
  )
where

import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Int (Int32, Int64)
import Data.Kind (Type)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Proxy (Proxy (..))
import Data.SBV qualified as SBV
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime, utcTimeToPOSIXSeconds)
import Data.Typeable (Typeable)
import Data.Word (Word16, Word32, Word64, Word8)
import GHC.TypeLits (KnownSymbol, symbolVal)
import Keiki.Core
import System.IO.Unsafe (unsafePerformIO)
import Type.Reflection (eqTypeRep, typeRep, type (:~~:) (HRefl))

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

-- | Encoded as 'Integer'. SBV does not provide an 'SInt'-of-arbitrary-
-- size; using 'Integer' avoids overflow surprises during translation.
instance Sym Int where
  type SymRep Int = Integer
  toSym = fromIntegral
  fromSym = fromIntegral
  symDefault = 0

-- The fixed-width integer instances below all encode as the unbounded
-- mathematical 'Integer', exactly like 'Sym Int'. This is an
-- /over-approximation/: the modular wraparound of the Haskell @Word*@ /
-- @Int*@ type is not modeled. The consequence is sound for
-- satisfiability (every concrete model the solver finds is a real
-- witness once decoded through 'fromSym') but may miss an
-- unsatisfiability that depends on overflow (e.g. @x + 1 == 0@ over
-- 'Word64' is satisfiable at the type's wrap point but the 'Integer'
-- encoding reports it unsat). keiki's money and count guards are
-- equality and ordering checks against in-range literals, where the
-- over-approximation never bites. The motivating money type is
-- @Jitsurei.OrderCart@'s @Money = Word64@ (fixed-point minor units).

-- | Money and large counts. Encoded as 'Integer'; see the note above
-- on the unbounded-'Integer' over-approximation.
instance Sym Word64 where
  type SymRep Word64 = Integer
  toSym = fromIntegral
  fromSym = fromIntegral
  symDefault = 0

-- | Item counts and similar 32-bit unsigned registers. Encoded as
-- 'Integer'; see the over-approximation note above.
instance Sym Word32 where
  type SymRep Word32 = Integer
  toSym = fromIntegral
  fromSym = fromIntegral
  symDefault = 0

-- | Quantities, basis points, and similar 16-bit unsigned registers.
-- Encoded as 'Integer'; see the over-approximation note above.
instance Sym Word16 where
  type SymRep Word16 = Integer
  toSym = fromIntegral
  fromSym = fromIntegral
  symDefault = 0

-- | 8-bit unsigned (completeness). Encoded as 'Integer'; see the
-- over-approximation note above.
instance Sym Word8 where
  type SymRep Word8 = Integer
  toSym = fromIntegral
  fromSym = fromIntegral
  symDefault = 0

-- | 64-bit signed (completeness). Encoded as 'Integer'; see the
-- over-approximation note above.
instance Sym Int64 where
  type SymRep Int64 = Integer
  toSym = fromIntegral
  fromSym = fromIntegral
  symDefault = 0

-- | 32-bit signed (completeness). Encoded as 'Integer'; see the
-- over-approximation note above.
instance Sym Int32 where
  type SymRep Int32 = Integer
  toSym = fromIntegral
  fromSym = fromIntegral
  symDefault = 0

-- | 'Text' is encoded as Haskell 'String' for SBV's 'SString' theory.
instance Sym Text where
  type SymRep Text = String
  toSym = T.unpack
  fromSym = T.pack
  symDefault = T.empty

-- | 'UTCTime' is encoded as Unix epoch seconds (an 'Integer').
-- The round-trip drops sub-second precision; this is intentional —
-- the User Registration aggregate's timestamps are at-second
-- granularity already, and Integer-encoded time comparisons are well
-- supported by SBV's z3 backend.
instance Sym UTCTime where
  type SymRep UTCTime = Integer
  toSym = round . utcTimeToPOSIXSeconds
  fromSym = posixSecondsToUTCTime . fromIntegral
  symDefault = posixSecondsToUTCTime 0

-- | Reify a 'Sym' instance so it can be passed around as a
-- first-class value. Useful for runtime dispatch on 'Typeable'
-- evidence.
data SymDict r where
  SymDict :: (Sym r) => SymDict r

-- | Try to discover a 'Sym' instance for @r@ at runtime. Returns
-- @Just SymDict@ for any of the curated supported types
-- ('Bool', 'Int', 'Integer', 'Text', 'UTCTime', and the fixed-width
-- integers 'Word8' \/ 'Word16' \/ 'Word32' \/ 'Word64' \/ 'Int32' \/
-- 'Int64'); 'Nothing' otherwise. The translator uses this to route
-- 'PEq' over arbitrary types: a 'Sym' hit translates to '(.==)' on
-- SBV terms; a miss falls back to a fresh 'SBool' (loses precision but
-- stays sound).
discoverSym :: forall r. (Typeable r) => Maybe (SymDict r)
discoverSym
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Bool) = Just SymDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int) = Just SymDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Integer) = Just SymDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Text) = Just SymDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @UTCTime) = Just SymDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word64) = Just SymDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word32) = Just SymDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word16) = Just SymDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word8) = Just SymDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int64) = Just SymDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int32) = Just SymDict
  | otherwise = Nothing

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
-- 'Integer', the fixed-width integers 'Word8' \/ 'Word16' \/ 'Word32'
-- \/ 'Word64' \/ 'Int32' \/ 'Int64', and 'UTCTime' encoded as epoch
-- seconds); 'Nothing' otherwise. 'Bool' and 'Text' are deliberately
-- omitted: ordering a 'Bool' guard is not meaningful, and 'SString'
-- ordering is out of scope here. A 'Nothing' makes the 'PCmp'
-- translator fall back to a fresh opaque 'SBool', exactly as 'goEq'
-- does for non-'Sym' operands — sound, just imprecise.
discoverSymOrd :: forall r. (Typeable r) => Maybe (SymOrdDict r)
discoverSymOrd
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int) = Just SymOrdDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Integer) = Just SymOrdDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word64) = Just SymOrdDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word32) = Just SymOrdDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word16) = Just SymOrdDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word8) = Just SymOrdDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int64) = Just SymOrdDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int32) = Just SymOrdDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @UTCTime) = Just SymOrdDict
  | otherwise = Nothing

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
-- 'Int32' \/ 'Int64'); 'Nothing' otherwise. 'Bool', 'Text', and
-- 'UTCTime' are omitted — not meaningfully arithmetic here. A 'Nothing'
-- makes the 'TArith' translator fall back to a fresh opaque variable,
-- exactly as 'goEq' \/ 'goCmp' fall back for non-'Sym' operands —
-- sound, just imprecise. (The 'Num' constraint on the 'TArith'
-- constructor already prevents arithmetic at non-numeric types, so this
-- fallback is only reachable for a numeric type intentionally left out
-- of the registry.)
discoverSymNum :: forall r. (Typeable r) => Maybe (SymNumDict r)
discoverSymNum
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int) = Just SymNumDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Integer) = Just SymNumDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word64) = Just SymNumDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word32) = Just SymNumDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word16) = Just SymNumDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word8) = Just SymNumDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int64) = Just SymNumDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int32) = Just SymNumDict
  | otherwise = Nothing

-- | Lift a concrete value to an SBV literal of its 'SymRep'.
symLit :: forall a. (Sym a) => a -> SBV.SBV (SymRep a)
symLit = SBV.literal . toSym

-- | Allocate a fresh symbolic variable of the carrier's 'SymRep'.
symFree :: forall a. (Sym a) => String -> SBV.Symbolic (SBV.SBV (SymRep a))
symFree = SBV.free

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
--   * 'seVarCache' — a per-translation memo cache (EP-42) keyed by the
--     deterministic variable name ('TReg' allocates @"reg/\<slot\>"@,
--     'TInpCtorField' allocates @"inp/\<ctor\>/\<field\>"@). The first
--     read of a name allocates one 'SBV.free' variable and stores it;
--     every later read of the same name returns the cached variable.
--     This makes the solver see two reads of @#x@ as the /same/ value,
--     so @proj #x .== proj #x@ is valid (not merely satisfiable). The
--     'TApp1' \/ 'TApp2' escape hatches are deliberately /not/ cached:
--     they wrap opaque Haskell functions with no 'Eq', so two
--     applications cannot be recognized as equal and each stays a fresh
--     per-occurrence variable.
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
    seVarCache :: IORef (Map String SomeSBV)
  }

-- | An SBV variable of some representation type, packed so the memo
-- cache in 'SymEnv' can hold variables of different representation
-- types under one map. 'SBV.SymVal' has a 'Typeable' superclass, so
-- pattern-matching @SomeSBV (v :: SBV.SBV a)@ brings @Typeable a@ into
-- scope — exactly what 'memoFree' needs to check the recovered type
-- matches the requested one on a cache hit.
data SomeSBV where
  SomeSBV :: (SBV.SymVal a) => SBV.SBV a -> SomeSBV

-- | Allocate a fresh 'SymEnv'. Lives in 'SBV.Symbolic' because
-- 'seInputCtor' is a free symbolic variable and the memo cache is an
-- 'IORef' created in the underlying 'IO' ('SBV.Symbolic' is
-- @SymbolicT IO@, hence 'MonadIO').
mkSymEnv :: SBV.Symbolic SymEnv
mkSymEnv = do
  ctor <- SBV.free "inputCtor"
  arm <- SBV.free "inputArm"
  cache <- liftIO (newIORef Map.empty)
  pure (SymEnv ctor arm cache)

-- * Translation -------------------------------------------------------------

-- | Translate a 'Term rs ci r' to an SBV expression of the carrier's
-- representation type. Requires 'Sym' evidence for @r@.
--
-- The translation is /structural/ for 'TLit', 'TReg',
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
--   * 'TApp1' / 'TApp2' keep their anonymous names; their values are
--     not extracted as part of the witness.
--
-- Note on repeated reads (EP-42): 'TReg' and 'TInpCtorField' reads are
-- memoized through the env's 'seVarCache'. The first read of a given
-- slot\/field allocates one 'SBV.free' variable and caches it under its
-- deterministic name; every later read of the same name returns the
-- cached variable. So two reads of the same slot (e.g.
-- @proj #x .== proj #x@) share /one/ SBV variable: the solver knows
-- they are equal, @x \/= x@ is unsat, and 'symSatExt''s by-name witness
-- extraction is correct for repeated reads. The 'TApp1' \/ 'TApp2'
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
translateTermSym env (TReg ix) =
  memoFree env ("reg/" <> indexName ix)
translateTermSym env (TInpCtorField ic ix) =
  memoFree env ("inp/" <> icName ic <> "/" <> indexName ix)
translateTermSym _env (TApp1 _f _t) = SBV.free "app1"
translateTermSym _env (TApp2 _f _a _b) = SBV.free "app2"
translateTermSym env (TArith op a b) = case discoverSymNum @r of
  Nothing -> SBV.free "arith" -- sound opaque fallback
  Just SymNumDict -> do
    sa <- translateTermSym env a
    sb <- translateTermSym env b
    let apply = case op of
          OpAdd -> (+)
          OpSub -> (-)
          OpMul -> (*)
    pure (apply sa sb)

-- | Memoized symbolic-variable allocator (EP-42). Looks @name@ up in
-- the env's 'seVarCache'. On a hit, recover the cached SBV variable —
-- checking its representation type matches the requested one, which it
-- always does because a deterministic name maps to exactly one type.
-- On a miss, allocate a fresh 'SBV.free', store it under @name@, and
-- return it. This is what makes repeated reads of the same register or
-- input field share a single solver variable.
memoFree ::
  forall a.
  (SBV.SymVal a) =>
  SymEnv -> String -> SBV.Symbolic (SBV.SBV a)
memoFree env name = do
  m <- liftIO (readIORef (seVarCache env))
  case Map.lookup name m of
    Just (SomeSBV (v :: SBV.SBV b)) ->
      case eqTypeRep (typeRep @a) (typeRep @b) of
        Just HRefl -> pure v
        Nothing ->
          -- Unreachable: a name maps to exactly one representation type.
          error ("memoFree: type mismatch for cached variable " <> name)
    Nothing -> do
      v <- SBV.free name
      liftIO (modifyIORef' (seVarCache env) (Map.insert name (SomeSBV v)))
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
-- 'symIsBot', which dispatches to z3 via SBV. Witness extraction
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

-- | Symbolic emptiness check. Translates the predicate to an SBV
-- expression and asks z3 whether any model exists; @True@ when none
-- does (the predicate is bot), @False@ otherwise (including the
-- conservative 'Unknown' fallback). The 'unsafePerformIO' wrapper is
-- justified because every SBV query is deterministic for a given
-- predicate and side-effect-free outside the solver process.
{-# NOINLINE symIsBot #-}
symIsBot :: HsPred rs ci -> Bool
symIsBot p = unsafePerformIO $ do
  res <- SBV.sat $ do
    env <- mkSymEnv
    translatePred env p
  pure (not (SBV.modelExists res))

-- * Single-valuedness ------------------------------------------------------

-- | A transducer is /single-valued/ when, at every reachable
-- vertex, at most one outgoing edge's guard is satisfied for any
-- given input. The check decomposes into "for every vertex @s@, for
-- every distinct pair @(e1, e2)@ of outgoing edges, is the
-- conjunction of their guards 'isBot'?". The function is
-- 'BoolAlg'-polymorphic; precision depends on the chosen 'isBot'
-- implementation. With 'SymPred', this is the v2 SBV-backed
-- decision; with the v1 'HsPred' instance the answer is the v1
-- syntactic over-approximation.
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
          pairs =
            [ (e1, e2)
            | (i, e1) <- ies,
              (j, e2) <- ies,
              i < j
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
          target = target e
        }

-- * Solver-backed validation diagnostics (EP-56) ---------------------------

-- | Solver-backed determinism diagnostic. Lifts the transducer with
-- 'withSymPred' and runs the 'BoolAlg'-polymorphic 'checkTransitionDeterminism'
-- at the 'SymPred' carrier, whose 'isBot' is the exact z3 decision. Unlike the
-- pure path in 'validateTransducer', this catches register-value-dependent and
-- other non-syntactic overlaps. Requires z3 on @PATH@.
checkTransitionDeterminismSym ::
  (Bounded s, Enum s, Show s) =>
  SymTransducer (HsPred rs ci) rs s ci co ->
  [DeterminismWarning s]
checkTransitionDeterminismSym = checkTransitionDeterminism . withSymPred

-- | Symbolic dead-edge sketch. Flags edges whose guard is unsatisfiable
-- /in isolation/ (via 'symIsBot'), which the structural 'checkDeadEdges'
-- misses unless the guard is literally 'PBot' (e.g. @amount > 0 && amount < 0@).
-- It does NOT compute the register configurations reachable at each vertex, so
-- it still cannot catch the FieldResource case (a guard satisfiable in
-- isolation but never under the registers reachable there); that needs a full
-- reachable-state fixpoint and is left as future work. Requires z3 on @PATH@.
checkDeadEdgesSym ::
  (Bounded s, Enum s, Show s) =>
  SymTransducer (HsPred rs ci) rs s ci co ->
  [DeadEdgeWarning s]
checkDeadEdgesSym t =
  [ DeadEdgeWarning
      (EdgeRef {edgeSource = s, edgeIndex = i})
      "guard is unsatisfiable in isolation (symbolic)"
  | s <- [minBound .. maxBound],
    (i, e) <- zip [(0 :: Int) ..] (edgesOut t s),
    symIsBot (guard e)
  ]

-- * Witness extraction -----------------------------------------------------

-- | Materialize a 'RegFile' from a name-keyed reader. The reader's
-- input is a slot name (the same string 'translateTermSym' allocates
-- under @"reg/" <> slotName@); the reader's output is the slot's
-- value, of any 'Sym'-supported type. The reader is total: callers
-- (notably 'symSatExt') fall back to 'symDefault' for slots whose
-- names the SBV model did not bind.
--
-- Two instances cover the slot list:
--
--   * @ExtractRegFile \'[]@ — return 'RNil' regardless of the reader.
--   * @ExtractRegFile (\'(s, t) ': rs)@ — read the head slot's name
--     via the reader, recurse on the tail, build an 'RCons'.
--
-- The instance constraints @KnownSymbol s@ and @Sym t@ make this
-- automatic for any concrete slot list whose value types are in the
-- curated 'Sym' registry ('Bool', 'Int', 'Integer', 'Text',
-- 'UTCTime'). User Registration's 'UserRegRegs' shape qualifies
-- without further user code.
class ExtractRegFile (rs :: [Slot]) where
  extractRegFile :: (forall r. (Sym r) => String -> r) -> RegFile rs

instance ExtractRegFile '[] where
  extractRegFile _ = RNil

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

-- | Symbolic satisfiability with full witness extraction. On a
-- satisfiable predicate, returns @Just (regs, cmd)@ where @regs@
-- and @cmd@ are concrete values reconstructed from the SBV model.
-- @models p (regs, cmd) == True@ holds for the returned witness,
-- modulo one known limitation:
--
--   * /Escape-hatch terms/ ('TApp1', 'TApp2', and 'PEq' over a
--     non-'Sym' operand type, the @neq@ fallback in 'goEq').
--     These translate to fresh anonymous SBV variables; their values
--     are not extracted, and two occurrences of the same opaque
--     application do not share a variable (opaque functions have no
--     'Eq'). The witness reflects only the slots and input-fields the
--     predicate references through 'TReg' and 'TInpCtorField'.
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
-- 'KnownInCtors' evidence the witness-free 'BoolAlg' class cannot).
{-# NOINLINE symSatExt #-}
symSatExt ::
  forall rs ci.
  ( ExtractRegFile rs,
    KnownInCtors ci
  ) =>
  HsPred rs ci -> Maybe (RegFile rs, ci)
symSatExt p = unsafePerformIO $ do
  res <- SBV.sat $ do
    env <- mkSymEnv
    b <- translatePred env p
    -- Constrain the shared input-constructor tag to the known
    -- constructor domain so the solver cannot pick a string matching no
    -- constructor. Predicates without a 'PInCtor' atom leave the tag
    -- free, so without this the solver could choose an unknown tag,
    -- 'pickCi' would find no match, and a satisfiable predicate would
    -- (wrongly) yield no witness. Confining the tag to the real finite
    -- domain keeps the reconstructed witness sound (it always satisfies
    -- 'models') and improves completeness on @PNot (PInCtor …)@ guards.
    let ctorNames = [icName ic | SomeInCtor ic <- allInCtors @ci]
    when (not (null ctorNames)) $
      SBV.constrain $
        SBV.sOr [seInputCtor env SBV..== SBV.literal n | n <- ctorNames]
    pure b
  pure $
    if SBV.modelExists res
      then do
        ctorTag <- SBV.getModelValue "inputCtor" res
        let regReader :: forall r. (Sym r) => String -> r
            regReader name = readModel res ("reg/" <> name)
        let regs = extractRegFile @rs regReader
        ci <-
          pickCi @ci
            ctorTag
            ( \icN fieldName ->
                readModel
                  res
                  ("inp/" <> icN <> "/" <> fieldName)
            )
        pure (regs, ci)
      else Nothing

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
  (forall r. (Sym r) => String -> String -> r) ->
  Maybe ci
pickCi tag readField = go (allInCtors @ci)
  where
    go [] = Nothing
    go (SomeInCtor ic@InCtor {} : rest)
      | icName ic == tag =
          let regs = extractRegFile (readField (icName ic))
           in Just (icBuild ic regs)
      | otherwise = go rest
