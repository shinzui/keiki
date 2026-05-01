{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}

-- | The pure core of keiki: the symbolic-register transducer.
--
-- This module is the v1 prototype of the design pinned by
-- @docs/research/dsl-shape-for-symbolic-register.md@ (the DSL note),
-- @docs/research/effects-boundary.md@ (the boundary note), and
-- @docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md@
-- (the working baseline). See those notes for the rationale behind every
-- shape declared here.
--
-- v1 limitations recorded in the DSL note's \"Ergonomic verdict\" and
-- \"v1-only surfaces\" sections:
--
--   * 'TInpField' carries an opaque @ci -> r@; v2 replaces with structural
--     input projection.
--   * 'OFn' carries an opaque @RegFile rs -> ci -> co@; v2 replaces with
--     structural 'OPack'.
--   * 'PMatchC' carries an opaque @ci -> Bool@; v2 replaces with a
--     pattern AST.
--   * 'unsafeCombine' bypasses the distinct-targets check that 'combine'
--     enforces; v2 makes the check static.
module Keiki.Core
  ( -- * Slots and the register file
    Slot
  , RegFile (..)
  , Index (..)
  , (!)
    -- * Index resolution from labels
  , HasIndex (..)
    -- * Term language
  , Term (..)
    -- * Update language
  , Update (..)
  , combine
  , unsafeCombine
    -- * Output term language
  , WireCtor (..)
  , OutFields (..)
  , OutTerm (..)
    -- * Predicate carrier (v1 first-class AST)
  , HsPred (..)
    -- * Effective Boolean algebra
  , BoolAlg (..)
    -- * Edges and the transducer
  , Edge (..)
  , SymTransducer (..)
    -- * Helpers (the user-facing DSL surface)
  , matchCmd
  , mkOut
  , proj
  , inp
  , lit
  , (.==)
  , pack
    -- * Evaluators
  , evalTerm
  , evalOut
  , evalPred
  , runUpdate
  , delta
  , omega
    -- * Pure-layer entry points (effects-boundary note)
  , step
  , reconstitute
    -- * Build-time analyses
  , solveOutput
  , HiddenInputWarning (..)
  , checkHiddenInputs
  ) where

import Data.Kind (Type)
import Data.Proxy (Proxy (..))
import GHC.OverloadedLabels (IsLabel (..))
import GHC.TypeLits (KnownSymbol, Symbol)


-- | A register slot is a label paired with the type of its value.
type Slot = (Symbol, Type)


-- * Register file -----------------------------------------------------------

-- | A typed heterogeneous register tuple indexed by a list of 'Slot's.
data RegFile (rs :: [Slot]) where
  RNil  :: RegFile '[]
  RCons :: KnownSymbol s
        => Proxy s -> r -> RegFile rs -> RegFile ('(s, r) ': rs)


-- | A type-safe pointer into a 'RegFile'. 'ZIdx' picks the head;
-- 'SIdx' skips one slot.
data Index (rs :: [Slot]) (r :: Type) where
  ZIdx :: KnownSymbol s => Index ('(s, r) ': rs) r
  SIdx :: Index rs r    -> Index ('(s', r') ': rs) r


-- | Runtime register lookup. Matching on 'Index' first lets GHC's GADT
-- pattern checker see that 'RNil' is unreachable — 'ZIdx' and 'SIdx'
-- both refine @rs@ to @'(_,_) ': _@.
(!) :: RegFile rs -> Index rs r -> r
regs ! ZIdx     = case regs of RCons _ x _    -> x
regs ! SIdx i   = case regs of RCons _ _ rest -> rest ! i
infixl 9 !


-- * IsLabel / HasIndex -----------------------------------------------------

-- | Resolve a label @s@ against a slot list @rs@ to an 'Index' for the
-- value at that slot. The functional dependency @s rs -> r@ ensures that
-- a label uniquely determines the slot's type.
class HasIndex (s :: Symbol) (rs :: [Slot]) (r :: Type)
               | s rs -> r where
  indexOf :: Index rs r

instance {-# OVERLAPPING #-} (KnownSymbol s)
      => HasIndex s ('(s, r) ': rs) r where
  indexOf = ZIdx

instance {-# OVERLAPPABLE #-} forall s s' r r' rs.
         (HasIndex s rs r)
      => HasIndex s ('(s', r') ': rs) r where
  indexOf = SIdx (indexOf @s @rs @r)

instance forall s rs r.
         HasIndex s rs r
      => IsLabel s (Index rs r) where
  fromLabel = indexOf @s @rs @r


-- * Term language ----------------------------------------------------------

-- | A pure expression over the register file and the input symbol,
-- yielding a value of type @r@.
data Term (rs :: [Slot]) (ci :: Type) (r :: Type) where
  TLit      :: r -> Term rs ci r
  TReg      :: Index rs r -> Term rs ci r
  -- | v1 escape hatch: opaque function over the input symbol. v2
  -- replaces with structural input projection so the hidden-input check
  -- can see through it.
  TInpField :: (ci -> r) -> Term rs ci r
  TApp1     :: (a -> r)
            -> Term rs ci a
            -> Term rs ci r
  TApp2     :: (a -> b -> r)
            -> Term rs ci a
            -> Term rs ci b
            -> Term rs ci r


-- * Update language --------------------------------------------------------

-- | The copyless update language. Each register is written at most once
-- per 'UCombine'-tree on a single edge — enforced at construction time
-- by 'combine'.
data Update (rs :: [Slot]) (ci :: Type) where
  UKeep    :: Update rs ci
  USet     :: Index rs r -> Term rs ci r -> Update rs ci
  UCombine :: Update rs ci -> Update rs ci -> Update rs ci


-- | Smart constructor for 'UCombine' that rejects updates writing to the
-- same slot twice.
combine :: Update rs ci -> Update rs ci -> Either String (Update rs ci)
combine a b
  | null overlap = Right (UCombine a b)
  | otherwise    = Left ("combine: overlapping targets at indices "
                          ++ show overlap)
  where
    overlap = [t | t <- targets a, t `elem` targets b]


-- | Unchecked 'UCombine'. Use only when you have proven distinct targets
-- by hand. v2 retires this in favour of the static check.
unsafeCombine :: Update rs ci -> Update rs ci -> Update rs ci
unsafeCombine = UCombine


targets :: Update rs ci -> [Int]
targets UKeep          = []
targets (USet ix _)    = [indexInt ix]
targets (UCombine a b) = targets a ++ targets b


indexInt :: Index rs r -> Int
indexInt ZIdx     = 0
indexInt (SIdx i) = 1 + indexInt i


-- * Output term language ---------------------------------------------------

-- | A wire-type tag for one constructor of the user's output sum @co@.
-- The functions let 'solveOutput' pattern-match an observed @co@ and
-- 'evalOut' rebuild a @co@ from its fields.
data WireCtor co fields = WireCtor
  { wcName  :: String
  , wcMatch :: co -> Maybe fields
  , wcBuild :: fields -> co
  }


-- | An HList of 'Term's, one per field of the wire constructor. The
-- field-tuple type @fs@ is built up nested-pair style so that
-- 'solveOutput' can walk the HList structurally.
data OutFields rs ci fs where
  OFNil  :: OutFields rs ci ()
  OFCons :: Term rs ci f
         -> OutFields rs ci fs
         -> OutFields rs ci (f, fs)


-- | A pure expression yielding an output value @co@.
data OutTerm (rs :: [Slot]) (ci :: Type) (co :: Type) where
  -- | Structural pack: tagged by a wire constructor, with one 'Term'
  -- per field of that constructor.
  OPack :: WireCtor co fields
        -> OutFields rs ci fields
        -> OutTerm rs ci co
  -- | v1 escape hatch: opaque function. 'solveOutput' returns 'Nothing'
  -- and 'checkHiddenInputs' flags the edge.
  OFn   :: (RegFile rs -> ci -> co)
        -> OutTerm rs ci co


-- * Predicate carrier ------------------------------------------------------

-- | The v1 predicate AST. Carries enough structure to evaluate guards
-- and (eventually) be translated to SMT in v2.
data HsPred (rs :: [Slot]) (ci :: Type) where
  PTop    :: HsPred rs ci
  PBot    :: HsPred rs ci
  PAnd    :: HsPred rs ci -> HsPred rs ci -> HsPred rs ci
  POr     :: HsPred rs ci -> HsPred rs ci -> HsPred rs ci
  PNot    :: HsPred rs ci -> HsPred rs ci
  PEq     :: Eq r
          => Term rs ci r -> Term rs ci r -> HsPred rs ci
  -- | v1 escape hatch: opaque predicate over the input symbol.
  PMatchC :: (ci -> Bool) -> HsPred rs ci


-- * Effective Boolean algebra ----------------------------------------------

-- | An effective Boolean algebra over @a@-typed witnesses, used as the
-- guard carrier of edges.
class BoolAlg phi a | phi -> a where
  top    :: phi
  bot    :: phi
  conj   :: phi -> phi -> phi
  disj   :: phi -> phi -> phi
  neg    :: phi -> phi
  models :: phi -> a -> Bool
  -- | v1 returns 'Nothing'; v2's SBV-backed instance produces witnesses.
  sat    :: phi -> Maybe a
  isBot  :: phi -> Bool


instance BoolAlg (HsPred rs ci) (RegFile rs, ci) where
  top                 = PTop
  bot                 = PBot
  conj p q            = PAnd p q
  disj p q            = POr p q
  neg p               = PNot p
  models p (regs, ci) = evalPred p regs ci
  sat _               = Nothing
  isBot PBot          = True
  isBot _             = False


-- * Edges and the transducer -----------------------------------------------

-- | A single transition. 'Nothing' on 'output' is the ε-edge.
data Edge phi rs ci co s = Edge
  { guard  :: phi
  , update :: Update rs ci
  , output :: Maybe (OutTerm rs ci co)
  , target :: s
  }


-- | The single source of truth: a finite control graph plus a register
-- file evolved by edges' 'update' terms.
data SymTransducer phi rs s ci co = SymTransducer
  { edgesOut    :: s -> [Edge phi rs ci co s]
  , initial     :: s
  , initialRegs :: RegFile rs
  , isFinal     :: s -> Bool
  }


-- * Helpers (DSL surface) --------------------------------------------------

-- | v1 escape-hatch guard. v2 retires in favour of structural pattern AST.
matchCmd :: (ci -> Bool) -> HsPred rs ci
matchCmd = PMatchC


-- | v1 escape-hatch output. v2 retires in favour of structural 'OPack'.
mkOut :: (RegFile rs -> ci -> co) -> OutTerm rs ci co
mkOut = OFn


-- | Read a register slot into a 'Term'.
proj :: Index rs r -> Term rs ci r
proj = TReg


-- | Read an input field into a 'Term' (opaque function in v1).
inp :: (ci -> r) -> Term rs ci r
inp = TInpField


-- | A constant 'Term'.
lit :: r -> Term rs ci r
lit = TLit


-- | Equality predicate sugar.
(.==) :: Eq r => Term rs ci r -> Term rs ci r -> HsPred rs ci
(.==) = PEq
infix 4 .==


-- | Structural-output construction.
pack :: WireCtor co fields
     -> OutFields rs ci fields
     -> OutTerm rs ci co
pack = OPack


-- * Evaluators -------------------------------------------------------------

-- | Evaluate a 'Term' against a register file and an input symbol.
evalTerm :: Term rs ci r -> RegFile rs -> ci -> r
evalTerm (TLit r)        _    _  = r
evalTerm (TReg ix)       regs _  = regs ! ix
evalTerm (TInpField f)   _    ci = f ci
evalTerm (TApp1 f t)     regs ci = f (evalTerm t regs ci)
evalTerm (TApp2 f a b)   regs ci = f (evalTerm a regs ci) (evalTerm b regs ci)


-- | Evaluate an 'OutTerm' against a register file and an input symbol.
evalOut :: OutTerm rs ci co -> RegFile rs -> ci -> co
evalOut (OPack ctor fields) regs ci = wcBuild ctor (evalOutFields fields regs ci)
evalOut (OFn f)             regs ci = f regs ci


evalOutFields :: OutFields rs ci fs -> RegFile rs -> ci -> fs
evalOutFields OFNil           _    _  = ()
evalOutFields (OFCons t rest) regs ci =
  (evalTerm t regs ci, evalOutFields rest regs ci)


-- | Evaluate a predicate to a 'Bool' on the current state.
evalPred :: HsPred rs ci -> RegFile rs -> ci -> Bool
evalPred PTop          _    _  = True
evalPred PBot          _    _  = False
evalPred (PAnd p q)    r    c  = evalPred p r c && evalPred q r c
evalPred (POr p q)     r    c  = evalPred p r c || evalPred q r c
evalPred (PNot p)      r    c  = not (evalPred p r c)
evalPred (PEq a b)     r    c  = evalTerm a r c == evalTerm b r c
evalPred (PMatchC f)   _    c  = f c


-- | Apply an 'Update' to the register file. 'UCombine' applies left
-- then right; the user's 'combine' smart constructor (or hand-checked
-- 'unsafeCombine' use) is responsible for distinct targets so that the
-- order does not matter.
runUpdate :: Update rs ci -> RegFile rs -> ci -> RegFile rs
runUpdate UKeep          regs _  = regs
runUpdate (USet ix t)    regs ci = setSlot ix (evalTerm t regs ci) regs
runUpdate (UCombine a b) regs ci = runUpdate b (runUpdate a regs ci) ci


-- | Pure register-file slot update at the index.
setSlot :: Index rs r -> r -> RegFile rs -> RegFile rs
setSlot ZIdx     v regs = case regs of RCons p _ rest -> RCons p v rest
setSlot (SIdx i) v regs = case regs of RCons p x rest -> RCons p x (setSlot i v rest)


-- | Single-step transition. Returns 'Just (s', regs')' iff exactly one
-- outgoing edge has a satisfied guard.
delta
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> s -> RegFile rs -> ci -> Maybe (s, RegFile rs)
delta t s regs ci =
  case [ (target e, runUpdate (update e) regs ci)
       | e <- edgesOut t s
       , models (guard e) (regs, ci)
       ] of
    [single] -> Just single
    _        -> Nothing


-- | Single-step output. Returns 'Just co' for the unique active edge
-- whose 'output' is non-ε; 'Nothing' otherwise (including the case where
-- the unique active edge is an ε-edge).
omega
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> s -> RegFile rs -> ci -> Maybe co
omega t s regs ci =
  case [ evalOut o regs ci
       | e <- edgesOut t s
       , models (guard e) (regs, ci)
       , Just o <- [output e]
       ] of
    [o] -> Just o
    _   -> Nothing


-- * Pure-layer entry points ------------------------------------------------

-- | One full step of the transducer combining 'delta' and 'omega'.
-- Returns 'Nothing' if no edge from the current vertex has a satisfied
-- guard. The inner 'Maybe co' is 'Nothing' for an ε-edge.
step
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> (s, RegFile rs)
  -> ci
  -> Maybe (s, RegFile rs, Maybe co)
step t (s, regs) ci = case delta t s regs ci of
  Nothing          -> Nothing
  Just (s', regs') -> Just (s', regs', omega t s regs ci)


-- | Apply one observed output to the state by walking outgoing edges,
-- inverting each edge's @output@ via 'solveOutput', verifying the
-- guard on the recovered input, and applying the edge's @update@.
-- Internal helper for 'reconstitute'.
applyEvent
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> s -> RegFile rs -> co -> Maybe (s, RegFile rs)
applyEvent t s regs co =
  case [ (target e, runUpdate (update e) regs ci)
       | e <- edgesOut t s
       , Just o  <- [output e]
       , Just ci <- [solveOutput o regs co]
       , models (guard e) (regs, ci)
       ] of
    [single] -> Just single
    _        -> Nothing


-- | Reconstitute @(state, registers)@ from a log of outputs by
-- replaying each event through 'applyEvent', which inverts the
-- producing edge's @output@ via 'solveOutput'.
reconstitute
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> [co]
  -> Maybe (s, RegFile rs)
reconstitute t = go (initial t, initialRegs t)
  where
    go acc []         = Just acc
    go (s, regs) (co : rest) = do
      next <- applyEvent t s regs co
      go next rest


-- * Build-time analyses ----------------------------------------------------

-- | Recover the input that produced a given output, if the output term
-- is invertible in the input fields. Returns 'Nothing' for opaque 'OFn'
-- and for structural mismatches.
solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci
solveOutput = error "TODO: M4"


-- | A diagnostic produced by 'checkHiddenInputs'.
data HiddenInputWarning = HiddenInputWarning
  { hiwEdgeSource :: String
    -- ^ Identifier or description of the edge's source vertex.
  , hiwReason     :: String
    -- ^ Human-readable description of what's hidden.
  } deriving (Eq, Show)


-- | For every edge in the transducer, check whether the @update@ or
-- @guard@ reads input fields that the @output@ does not recover.
checkHiddenInputs
  :: SymTransducer phi rs s ci co
  -> [HiddenInputWarning]
checkHiddenInputs = error "TODO: M4"
