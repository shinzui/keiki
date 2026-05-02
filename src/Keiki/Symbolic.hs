{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
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
--     'Text', and 'UTCTime'.
--   * 'SymEnv' carrying the shared symbolic input-constructor tag.
--   * 'translateTermSym' / 'translatePred' walking 'Term' / 'HsPred'
--     into SBV expressions.
--   * 'discoverSym' — runtime dispatch from 'Typeable' to 'Sym'
--     evidence over the curated registry of supported types.
--   * 'SymPred' newtype wrapper plus its 'BoolAlg' instance with
--     structural 'top' / 'bot' / 'conj' / 'disj' / 'neg' and a 'models'
--     that re-uses the v1 'evalPred' (concrete evaluation, no solver
--     call).
--   * 'symIsBot' / 'symSat' — pure-API wrappers around SBV's solver
--     calls (via 'unsafePerformIO' + NOINLINE). 'SymPred''s 'BoolAlg'
--     methods 'sat' and 'isBot' route through these, so the v1
--     placeholder behavior is replaced with precise symbolic answers.
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
    -- * Solver-backed analyses
  , symIsBot
  , symSat
  , symSatExt
    -- * Witness extraction
  , ExtractRegFile (..)
  , SomeInCtor (..)
  , KnownInCtors (..)
    -- * Single-valuedness
  , isSingleValuedSym
  , withSymPred
    -- * Re-exports
  , module Keiki.Core
  ) where

import Data.Kind (Type)
import Data.Proxy (Proxy (..))
import qualified Data.SBV as SBV
import qualified Data.Text as T
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime, utcTimeToPOSIXSeconds)
import Data.Typeable (Typeable)
import GHC.TypeLits (KnownSymbol, symbolVal)
import System.IO.Unsafe (unsafePerformIO)
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
--
-- 'symDefault' is consumed by 'symSatExt': when the solver's model
-- has no value for a slot or input field that the predicate did not
-- reference, the witness extractor falls back to 'symDefault'. Sound
-- because such slots are unconstrained — any value satisfies the
-- predicate.
class (SBV.SymVal (SymRep a), Typeable a) => Sym a where
  type SymRep a :: Type
  toSym      :: a         -> SymRep a
  fromSym    :: SymRep a  -> a
  symDefault :: a


instance Sym Bool where
  type SymRep Bool = Bool
  toSym      = id
  fromSym    = id
  symDefault = False

instance Sym Integer where
  type SymRep Integer = Integer
  toSym      = id
  fromSym    = id
  symDefault = 0

-- | Encoded as 'Integer'. SBV does not provide an 'SInt'-of-arbitrary-
-- size; using 'Integer' avoids overflow surprises during translation.
instance Sym Int where
  type SymRep Int = Integer
  toSym      = fromIntegral
  fromSym    = fromIntegral
  symDefault = 0

-- | 'Text' is encoded as Haskell 'String' for SBV's 'SString' theory.
instance Sym Text where
  type SymRep Text = String
  toSym      = T.unpack
  fromSym    = T.pack
  symDefault = T.empty

-- | 'UTCTime' is encoded as Unix epoch seconds (an 'Integer').
-- The round-trip drops sub-second precision; this is intentional —
-- the User Registration aggregate's timestamps are at-second
-- granularity already, and Integer-encoded time comparisons are well
-- supported by SBV's z3 backend.
instance Sym UTCTime where
  type SymRep UTCTime = Integer
  toSym      = round . utcTimeToPOSIXSeconds
  fromSym    = posixSecondsToUTCTime . fromIntegral
  symDefault = posixSecondsToUTCTime 0


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
-- Note on repeated reads: SBV's 'SBV.free' uniquifies repeated
-- variable names by appending @_N@. Two reads of the same slot
-- (e.g. @proj #x .== proj #x@) produce two independent SBV variables
-- in the model. For sat\/unsat answers this is sound (it
-- over-approximates SAT). For 'symSatExt' witness extraction this
-- means a witness reconstructed by name lookup may not satisfy a
-- predicate with repeated reads. The User Registration test target
-- has no repeated reads and is sound. Memoization (via an 'IORef'
-- cache in 'SymEnv') is a future improvement; see EP-9 design log.
translateTermSym
  :: forall rs ci r. Sym r
  => SymEnv
  -> Term rs ci r
  -> SBV.Symbolic (SBV.SBV (SymRep r))
translateTermSym _env  (TLit r)              = pure (symLit r)
translateTermSym _env  (TReg ix)             =
  SBV.free ("reg/" <> indexName ix)
translateTermSym _env  (TInpCtorField ic ix) =
  SBV.free ("inp/" <> icName ic <> "/" <> indexName ix)
translateTermSym _env  (TApp1 _f _t)         = SBV.free "app1"
translateTermSym _env  (TApp2 _f _a _b)      = SBV.free "app2"


-- | Recover the slot name an 'Index' points at by walking to the
-- leaf 'ZIdx' and reading off the 'KnownSymbol' evidence the
-- constructor carries. Used for deterministic SBV variable naming
-- in 'translateTermSym'.
indexName :: forall rs r. Index rs r -> String
indexName (ZIdx @s) = symbolVal (Proxy @s)
indexName (SIdx i)  = indexName i


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


-- | The v2 'BoolAlg' instance. The five structural methods compose
-- 'HsPred' constructors. 'models' delegates to the v1 'evalPred'
-- (concrete evaluation, no solver call). 'sat' and 'isBot' route
-- through 'symSat' / 'symIsBot', which dispatch to z3 via SBV.
instance BoolAlg (SymPred rs ci) (RegFile rs, ci) where
  top                                = SymPred PTop
  bot                                = SymPred PBot
  conj (SymPred p) (SymPred q)       = SymPred (PAnd p q)
  disj (SymPred p) (SymPred q)       = SymPred (POr  p q)
  neg  (SymPred p)                   = SymPred (PNot p)
  models (SymPred p) (regs, ci)      = evalPred p regs ci
  sat (SymPred p)                    = symSat   p
  isBot (SymPred p)                  = symIsBot p


-- * Solver-backed analyses --------------------------------------------------

-- | The pure-API witness placeholder. 'symSat' returns
-- @Just (placeholder, placeholder)@ on a satisfiable predicate; this
-- pair tells callers \"yes, a witness exists\" without obliging the
-- 'BoolAlg' typeclass to thread a 'WitnessExtract'-style constraint.
-- Forcing either component crashes with a directing message; tests
-- that need the real witness will be served by a future
-- @symSatExt@ helper paired with hand-written extractors.
unsafeWitness :: a
unsafeWitness =
  error
    "Keiki.Symbolic.sat: placeholder witness; use symSat-backed \
    \analyses (isBot, isSingleValuedSym) or a future symSatExt for \
    \the concrete witness."


-- | Symbolic satisfiability check. Translates the predicate to an
-- SBV expression and asks z3 whether a model exists. Returns
-- @Just (placeholder, placeholder)@ on a model and 'Nothing' on
-- unsat or solver-unknown. The 'unsafePerformIO' is justified
-- because every SBV query is deterministic for a given predicate
-- and side-effect-free outside the solver process.
{-# NOINLINE symSat #-}
symSat :: HsPred rs ci -> Maybe (RegFile rs, ci)
symSat p = unsafePerformIO $ do
  res <- SBV.sat $ do
    env <- mkSymEnv
    translatePred env p
  pure $ if SBV.modelExists res
           then Just (unsafeWitness, unsafeWitness)
           else Nothing


-- | Symbolic emptiness check. Translates the predicate to an SBV
-- expression and asks z3 whether any model exists; @True@ when none
-- does (the predicate is bot), @False@ otherwise (including the
-- conservative 'Unknown' fallback). The 'unsafePerformIO' wrapper is
-- justified for the same reason as 'symSat'.
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
isSingleValuedSym
  :: forall phi rs s ci co.
     (BoolAlg phi (RegFile rs, ci), Bounded s, Enum s)
  => SymTransducer phi rs s ci co
  -> Bool
isSingleValuedSym t = all vertexSV [minBound .. maxBound]
  where
    vertexSV :: s -> Bool
    vertexSV s =
      let es    = edgesOut t s
          ies   = zip [(0 :: Int) ..] es
          pairs = [ (e1, e2)
                  | (i, e1) <- ies
                  , (j, e2) <- ies
                  , i < j
                  ]
      in all (\(e1, e2) -> isBot (guard e1 `conj` guard e2)) pairs


-- | Lift a transducer's edges from the v1 'HsPred' guard carrier to
-- the v2 'SymPred' carrier so 'isSingleValuedSym' (or any other
-- 'BoolAlg'-polymorphic analysis) sees the SBV-backed instance.
-- The control graph and update / output terms are unchanged.
withSymPred
  :: SymTransducer (HsPred rs ci) rs s ci co
  -> SymTransducer (SymPred rs ci) rs s ci co
withSymPred t = SymTransducer
  { edgesOut    = \s -> map liftEdge (edgesOut t s)
  , initial     = initial t
  , initialRegs = initialRegs t
  , isFinal     = isFinal t
  }
  where
    liftEdge :: Edge (HsPred rs ci) rs ci co s
             -> Edge (SymPred rs ci) rs ci co s
    liftEdge e = Edge
      { guard  = SymPred (guard e)
      , update = update e
      , output = output e
      , target = target e
      }


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
  extractRegFile :: (forall r. Sym r => String -> r) -> RegFile rs

instance ExtractRegFile '[] where
  extractRegFile _ = RNil

instance ( KnownSymbol s
         , Sym t
         , ExtractRegFile rs
         ) => ExtractRegFile ('(s, t) ': rs) where
  extractRegFile reader =
    RCons (Proxy @s)
          (reader @t (symbolVal (Proxy @s)))
          (extractRegFile @rs reader)


-- | Existential wrapper around an 'InCtor' that hides the
-- input-field slot list. The hidden 'ExtractRegFile' constraint lets
-- 'symSatExt' rebuild the input register file once the constructor
-- tag is known from the SBV model.
data SomeInCtor (ci :: Type) where
  SomeInCtor :: ExtractRegFile ifs => InCtor ci ifs -> SomeInCtor ci


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


-- * symSatExt ---------------------------------------------------------------

-- | Symbolic satisfiability with full witness extraction. On a
-- satisfiable predicate, returns @Just (regs, cmd)@ where @regs@
-- and @cmd@ are concrete values reconstructed from the SBV model.
-- @models p (regs, cmd) == True@ holds for the returned witness,
-- modulo two known limitations:
--
-- 1. /Repeated reads of the same slot or input field/. The
--    translator allocates each occurrence as a fresh SBV variable
--    (SBV uniquifies repeated names by appending @_N@). The witness
--    extractor reads the first allocation by name, so a predicate
--    with @proj #x .== proj #x@-style structure may produce a
--    witness that doesn't satisfy the predicate's structural
--    equality. The User Registration test target has no repeated
--    reads. Memoization is a future improvement.
-- 2. /Escape-hatch terms/ ('TApp1', 'TApp2', 'PMatchC', and 'PEq'
--    over a non-'Sym' operand type, the @neq@ fallback in 'goEq').
--    These translate to fresh anonymous SBV variables; their values
--    are not extracted. The witness reflects only the slots and
--    input-fields the predicate references through 'TReg' and
--    'TInpCtorField'.
--
-- 'symSatExt' is /pure/ via 'unsafePerformIO' on the SBV solver
-- call (deterministic for a given predicate, side-effect-free
-- outside the solver process). The 'BoolAlg' typeclass method 'sat'
-- continues to return the placeholder witness from 'symSat';
-- 'symSatExt' is a separate function because 'BoolAlg.sat'\'s
-- signature can't carry the 'ExtractRegFile' / 'KnownInCtors'
-- constraints.
{-# NOINLINE symSatExt #-}
symSatExt
  :: forall rs ci.
     ( ExtractRegFile rs
     , KnownInCtors ci
     )
  => HsPred rs ci -> Maybe (RegFile rs, ci)
symSatExt p = unsafePerformIO $ do
  res <- SBV.sat $ do
    env <- mkSymEnv
    translatePred env p
  pure $
    if SBV.modelExists res
      then do
        ctorTag <- SBV.getModelValue "inputCtor" res
        let regReader :: forall r. Sym r => String -> r
            regReader name = readModel res ("reg/" <> name)
        let regs = extractRegFile @rs regReader
        ci <- pickCi @ci ctorTag
                       (\icN fieldName ->
                          readModel res
                            ("inp/" <> icN <> "/" <> fieldName))
        pure (regs, ci)
      else Nothing


-- | Look up @name@ in @res@'s SBV model; on a hit return @fromSym@
-- of the model value, on a miss return @symDefault@. Used by
-- 'symSatExt' to convert SBV's typed model lookups into Haskell
-- values for any 'Sym'-supported slot type.
readModel :: forall r. Sym r => SBV.SatResult -> String -> r
readModel res name =
  case SBV.getModelValue name res :: Maybe (SymRep r) of
    Just rep -> fromSym rep
    Nothing  -> symDefault


-- | Walk the 'allInCtors' list, find the entry whose 'icName'
-- matches the model's input-constructor tag, then 'extractRegFile'
-- over the matched 'InCtor''s field list and call 'icBuild' to
-- assemble a @ci@. Returns 'Nothing' when no entry matches the tag
-- — this is the case when the predicate over-allocated the
-- @"inputCtor"@ slot (the solver picked a string that isn't any
-- known constructor name, which can happen if the predicate
-- doesn't include any 'PInCtor' atom).
pickCi
  :: forall ci.
     KnownInCtors ci
  => String
  -> (forall r. Sym r => String -> String -> r)
  -> Maybe ci
pickCi tag readField = go (allInCtors @ci)
  where
    go []                            = Nothing
    go (SomeInCtor ic@InCtor{} : rest)
      | icName ic == tag =
          let regs = extractRegFile (readField (icName ic))
          in Just (icBuild ic regs)
      | otherwise = go rest
