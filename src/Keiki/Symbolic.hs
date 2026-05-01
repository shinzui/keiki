{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
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
-- Milestones implemented in this revision (through M4 of EP-2):
--
--   * The 'Sym' typeclass and instances for 'Bool', 'Int', 'Integer',
--     'Text', and 'UTCTime'.
--   * 'SymEnv' carrying the shared symbolic input-constructor tag.
--   * 'translateTermSym' / 'translatePred' walking 'Term' / 'HsPred'
--     into SBV expressions.
--   * 'discoverSym' — runtime dispatch from 'Typeable' to 'Sym'
--     evidence over the curated registry of supported types.
--   * 'SymPred' newtype wrapper plus its 'BoolAlg' instance with
--     structural 'top' / 'bot' / 'conj' / 'disj' / 'neg' and a 'models'
--     that re-uses the v1 'evalPred' (concrete evaluation, no solver
--     call). 'sat' and 'isBot' remain stubbed at the v1 level pending
--     M5 of EP-2.
module Keiki.Symbolic
  ( -- * Symbolic representation
    Sym (..)
  , SymDict (..)
  , symLit
  , symFree
  , discoverSym
    -- * Translation
  , SymEnv (..)
  , mkSymEnv
  , translateTermSym
  , translatePred
    -- * Symbolic predicate wrapper
  , SymPred (..)
    -- * Re-exports
  , module Keiki.Core
  ) where

import Data.Kind (Type)
import qualified Data.SBV as SBV
import qualified Data.Text as T
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime, utcTimeToPOSIXSeconds)
import Data.Typeable (Typeable)
import Type.Reflection (eqTypeRep, typeRep, type (:~~:) (HRefl))

import Keiki.Core


-- * Symbolic representation -------------------------------------------------

-- | A type that has a curated representation in the SBV symbolic
-- universe. The associated type 'SymRep' pins the SBV-friendly
-- representation; the 'toSym' / 'fromSym' round-trip lets us push
-- concrete Haskell values into the solver and pull concrete witnesses
-- out of a model.
--
-- The 'SBV.SymVal' superclass on 'SymRep' gives us 'SBV.literal',
-- 'SBV.free', and 'SBV.unliteral' for free.
class (SBV.SymVal (SymRep a), Typeable a) => Sym a where
  type SymRep a :: Type
  toSym   :: a         -> SymRep a
  fromSym :: SymRep a  -> a


instance Sym Bool where
  type SymRep Bool = Bool
  toSym   = id
  fromSym = id

instance Sym Integer where
  type SymRep Integer = Integer
  toSym   = id
  fromSym = id

-- | Encoded as 'Integer'. SBV does not provide an 'SInt'-of-arbitrary-
-- size; using 'Integer' avoids overflow surprises during translation.
instance Sym Int where
  type SymRep Int = Integer
  toSym   = fromIntegral
  fromSym = fromIntegral

-- | 'Text' is encoded as Haskell 'String' for SBV's 'SString' theory.
instance Sym Text where
  type SymRep Text = String
  toSym   = T.unpack
  fromSym = T.pack

-- | 'UTCTime' is encoded as Unix epoch seconds (an 'Integer').
-- The round-trip drops sub-second precision; this is intentional —
-- the User Registration aggregate's timestamps are at-second
-- granularity already, and Integer-encoded time comparisons are well
-- supported by SBV's z3 backend.
instance Sym UTCTime where
  type SymRep UTCTime = Integer
  toSym   = round . utcTimeToPOSIXSeconds
  fromSym = posixSecondsToUTCTime . fromIntegral


-- | Reify a 'Sym' instance so it can be passed around as a
-- first-class value. Useful for runtime dispatch on 'Typeable'
-- evidence.
data SymDict r where
  SymDict :: Sym r => SymDict r


-- | Try to discover a 'Sym' instance for @r@ at runtime. Returns
-- @Just SymDict@ for any of the curated supported types
-- ('Bool', 'Int', 'Integer', 'Text', 'UTCTime'); 'Nothing'
-- otherwise. The translator uses this to route 'PEq' over arbitrary
-- types: a 'Sym' hit translates to '(.==)' on SBV terms; a miss
-- falls back to a fresh 'SBool' (loses precision but stays sound).
discoverSym :: forall r. Typeable r => Maybe (SymDict r)
discoverSym
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Bool)    = Just SymDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int)     = Just SymDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Integer) = Just SymDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Text)    = Just SymDict
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @UTCTime) = Just SymDict
  | otherwise                                                = Nothing


-- | Lift a concrete value to an SBV literal of its 'SymRep'.
symLit :: forall a. Sym a => a -> SBV.SBV (SymRep a)
symLit = SBV.literal . toSym


-- | Allocate a fresh symbolic variable of the carrier's 'SymRep'.
symFree :: forall a. Sym a => String -> SBV.Symbolic (SBV.SBV (SymRep a))
symFree = SBV.free


-- * Translation environment -------------------------------------------------

-- | Translation context: shared symbolic state that must be threaded
-- through a single predicate's walk so that, for example, two
-- 'PInCtor' atoms over distinct constructors agree they cannot both
-- be true.
--
-- Currently only the input constructor tag is shared. Per-slot
-- register variables and per-(InCtor, field) input variables are
-- allocated fresh on each occurrence; this loses the precision of
-- recognizing two reads of the same slot as the same value, but is
-- sound (sat/unsat answers are still correct conservatively) and
-- sufficient for the User Registration smoke test.
newtype SymEnv = SymEnv
  { seInputCtor :: SBV.SBV String
    -- ^ The shared symbolic input constructor tag. 'PInCtor' atoms
    -- assert @seInputCtor .== literal (icName ic)@; the solver
    -- recognizes that two such constraints with distinct names are
    -- mutually unsatisfiable.
  }


-- | Allocate a fresh 'SymEnv'. Lives in 'SBV.Symbolic' because
-- 'seInputCtor' is a free symbolic variable.
mkSymEnv :: SBV.Symbolic SymEnv
mkSymEnv = do
  ctor <- SBV.free "inputCtor"
  pure (SymEnv ctor)


-- * Translation -------------------------------------------------------------

-- | Translate a 'Term rs ci r' to an SBV expression of the carrier's
-- representation type. Requires 'Sym' evidence for @r@.
--
-- The translation is /structural/ for 'TLit', 'TReg', and
-- 'TInpCtorField'. 'TApp1' and 'TApp2' wrap opaque Haskell functions
-- and translate to fresh SBV variables of the result type — sound
-- but imprecise. The User Registration aggregate uses none of these
-- escape hatches, so the loss of precision is purely aspirational
-- for v2's scope.
translateTermSym
  :: forall rs ci r. Sym r
  => SymEnv
  -> Term rs ci r
  -> SBV.Symbolic (SBV.SBV (SymRep r))
translateTermSym _env  (TLit r)              = pure (symLit r)
translateTermSym _env  (TReg _ix)            = SBV.free "reg"
translateTermSym _env  (TInpCtorField ic _ix) = SBV.free ("inp/" <> icName ic)
translateTermSym _env  (TApp1 _f _t)         = SBV.free "app1"
translateTermSym _env  (TApp2 _f _a _b)      = SBV.free "app2"


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
--   * 'PMatchC' (the v1 escape hatch) emits a fresh 'SBool': the
--     opaque Haskell function is unanalyzable.
translatePred
  :: forall rs ci. SymEnv -> HsPred rs ci -> SBV.Symbolic SBV.SBool
translatePred env = go
  where
    go :: HsPred rs ci -> SBV.Symbolic SBV.SBool
    go PTop         = pure SBV.sTrue
    go PBot         = pure SBV.sFalse
    go (PAnd p q)   = (SBV..&&) <$> go p <*> go q
    go (POr p q)    = (SBV..||) <$> go p <*> go q
    go (PNot p)     = SBV.sNot  <$> go p
    go (PEq a b)    = goEq a b
    go (PInCtor ic) = pure (seInputCtor env SBV..== SBV.literal (icName ic))
    go (PMatchC _)  = SBV.free "pmatchc"

    goEq :: forall r. Typeable r
         => Term rs ci r -> Term rs ci r -> SBV.Symbolic SBV.SBool
    goEq a b = case discoverSym @r of
      Nothing      -> SBV.free "neq"
      Just SymDict -> do
        sa <- translateTermSym env a
        sb <- translateTermSym env b
        pure (sa SBV..== sb)


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
newtype SymPred (rs :: [Slot]) (ci :: Type) = SymPred { unSymPred :: HsPred rs ci }


-- | The v2 'BoolAlg' instance. Five of the eight methods are
-- structural (M4): they compose 'HsPred' constructors. 'models'
-- delegates to the v1 'evalPred' (concrete evaluation, no solver
-- call). The remaining two — 'sat' and 'isBot' — are stubbed at
-- the v1 level until M5 lands the SBV-backed bodies. The instance
-- header therefore matches v1's contract for now; callers see no
-- behavioural change yet.
instance BoolAlg (SymPred rs ci) (RegFile rs, ci) where
  top                                = SymPred PTop
  bot                                = SymPred PBot
  conj (SymPred p) (SymPred q)       = SymPred (PAnd p q)
  disj (SymPred p) (SymPred q)       = SymPred (POr  p q)
  neg  (SymPred p)                   = SymPred (PNot p)
  models (SymPred p) (regs, ci)      = evalPred p regs ci
  sat _                              = Nothing  -- upgraded in EP-2 M5
  isBot (SymPred PBot)               = True
  isBot _                            = False    -- upgraded in EP-2 M5
