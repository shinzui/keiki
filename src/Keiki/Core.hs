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
    -- * Input-side structural constructor (v2)
  , InCtor (..)
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
  , inpCtor
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
    -- * Internals exposed for testing
  , termReadsInput
  , updateReadsInput
  , outFieldsHaveInpField
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
  -- can see through it. Retired in EP-1 of MasterPlan 2; kept in
  -- parallel with 'TInpCtorField' until every use site is migrated.
  TInpField     :: (ci -> r) -> Term rs ci r
  -- | v2 structural input projection: read field @ix@ of the input
  -- constructor described by @ic@. The 'InCtor' value names the
  -- expected constructor and supplies the round-trip
  -- ('icMatch'/'icBuild') so that 'solveOutput' can mechanically
  -- recover @ci@ from an observed output. See @docs/research/tinpproj-design.md@.
  TInpCtorField :: InCtor ci ifs -> Index ifs r -> Term rs ci r
  TApp1     :: (a -> r)
            -> Term rs ci a
            -> Term rs ci r
  TApp2     :: (a -> b -> r)
            -> Term rs ci a
            -> Term rs ci b
            -> Term rs ci r


-- | Per-constructor input projection. An 'InCtor' value names one
-- constructor of the input symbol type @ci@ and pins the round-trip
-- between that constructor's payload and a typed register file
-- @'RegFile' ifs@. The slot list @ifs@ is the field schema for the
-- constructor; together with 'Index' it lets call sites read fields
-- via 'OverloadedLabels' (for example @inpStart #email@).
--
-- 'icMatch' must return 'Just' iff @ci@ is the named constructor.
-- 'icBuild' is its left inverse: @icMatch (icBuild rf) == Just rf@ for
-- every well-formed @rf@.
--
-- See @docs/research/tinpproj-design.md@ for the design rationale and
-- the inversion algorithm that walks 'OutFields' gathering these
-- per-field reads.
data InCtor ci (ifs :: [Slot]) = InCtor
  { icName  :: String
  , icMatch :: ci -> Maybe (RegFile ifs)
  , icBuild :: RegFile ifs -> ci
  }


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
  -- per field of that constructor, plus a v1 hand-written inverse used
  -- by 'solveOutput'. The structural field-list 'OutFields' remains
  -- inspectable by 'checkHiddenInputs'; the explicit inverse is the v1
  -- pragmatic fix for the fact that 'TInpField' is an opaque function
  -- that 'solveOutput' cannot mechanically invert. v2 retires the
  -- inverse field once 'TInpProj' (structural input projection) lands.
  OPack :: WireCtor co fields
        -> OutFields rs ci fields
        -> (RegFile rs -> co -> Maybe ci)
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


-- | Structural input projection: read field @ix@ of the input
-- constructor described by @ic@. The v2 replacement for 'inp'.
inpCtor :: InCtor ci ifs -> Index ifs r -> Term rs ci r
inpCtor = TInpCtorField


-- | A constant 'Term'.
lit :: r -> Term rs ci r
lit = TLit


-- | Equality predicate sugar.
(.==) :: Eq r => Term rs ci r -> Term rs ci r -> HsPred rs ci
(.==) = PEq
infix 4 .==


-- | Structural-output construction. The third argument is the v1
-- hand-written inverse used by 'solveOutput'. v2 retires this in favour
-- of mechanical inversion via structural input projection.
pack :: WireCtor co fields
     -> OutFields rs ci fields
     -> (RegFile rs -> co -> Maybe ci)
     -> OutTerm rs ci co
pack = OPack


-- * Evaluators -------------------------------------------------------------

-- | Evaluate a 'Term' against a register file and an input symbol.
evalTerm :: Term rs ci r -> RegFile rs -> ci -> r
evalTerm (TLit r)              _    _  = r
evalTerm (TReg ix)             regs _  = regs ! ix
evalTerm (TInpField f)         _    ci = f ci
evalTerm (TInpCtorField ic ix) _    ci = case icMatch ic ci of
  Just rf -> rf ! ix
  Nothing -> error ("evalTerm: TInpCtorField guard violation: " ++ icName ic)
evalTerm (TApp1 f t)           regs ci = f (evalTerm t regs ci)
evalTerm (TApp2 f a b)         regs ci = f (evalTerm a regs ci) (evalTerm b regs ci)


-- | Evaluate an 'OutTerm' against a register file and an input symbol.
evalOut :: OutTerm rs ci co -> RegFile rs -> ci -> co
evalOut (OPack ctor fields _inv) regs ci =
  wcBuild ctor (evalOutFields fields regs ci)
evalOut (OFn f)                  regs ci = f regs ci


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

-- | Recover the input that produced a given output. For 'OPack' the
-- v1 implementation calls the user-provided inverse directly; for
-- 'OFn' the result is 'Nothing' (opaque output, not invertible). v2
-- replaces the 'OPack' inverse field with a structural walk over
-- 'OutFields' once 'TInpProj' lands.
solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci
solveOutput (OPack _ctor _fields inv) regs co = inv regs co
solveOutput (OFn _)                   _regs _co = Nothing


-- | A diagnostic produced by 'checkHiddenInputs'.
data HiddenInputWarning = HiddenInputWarning
  { hiwEdgeSource :: String
    -- ^ Description of the edge's source (typically @show s@).
  , hiwReason     :: String
    -- ^ Human-readable description of what's hidden.
  } deriving (Eq, Show)


-- | For every edge in the transducer, check whether the @update@ or
-- @guard@ touches the input symbol via an opaque path that the @output@
-- cannot recover on replay. Specifically:
--
--   * If @output@ is @Nothing@ (an ε-edge), and @update@ or @guard@
--     reaches into @ci@ via 'TInpField', the edge is opaque-input.
--     ε-edges are silent on the wire, so the input contribution is
--     unrecoverable.
--   * If @output@ is 'OFn', the whole output is opaque. Any @update@
--     or @guard@ reaching into @ci@ is also unrecoverable.
--   * If @output@ is 'OPack' with @TInpField@ leaves, those leaves are
--     structurally noted but cannot be inverted without the v1
--     hand-written inverse (which the user did supply). The check
--     reports them as best-effort warnings rather than hard errors.
--
-- The check is intentionally conservative: it flags candidates for the
-- author to inspect, not theorems.
checkHiddenInputs
  :: forall phi rs s ci co.
     (Bounded s, Enum s, Show s)
  => SymTransducer phi rs s ci co
  -> [HiddenInputWarning]
checkHiddenInputs t =
  [ HiddenInputWarning
      { hiwEdgeSource = show s
      , hiwReason     = reason
      }
  | s <- [minBound .. maxBound]
  , (n, e) <- zip [(0 :: Int) ..] (edgesOut t s)
  , reason <- edgeReasons n e
  ]
  where
    edgeReasons :: Int -> Edge phi rs ci co s -> [String]
    edgeReasons n e = case output e of
      Nothing
        | updateReadsInput (update e) ->
            [ "edge #" <> show n <> ": ε-edge with input read in update" ]
        | otherwise -> []
      Just (OFn _) ->
        [ "edge #" <> show n <> ": OFn output is opaque (no inverse)" ]
      Just (OPack _ fields _inv)
        | outFieldsHaveInpField fields ->
            [ "edge #" <> show n
              <> ": OPack field uses TInpField; v1 inverse is hand-written"
            ]
        | otherwise -> []


-- | Does the 'Update' read the input symbol via 'TInpField'?
updateReadsInput :: Update rs ci -> Bool
updateReadsInput UKeep          = False
updateReadsInput (USet _ t)     = termReadsInput t
updateReadsInput (UCombine a b) = updateReadsInput a || updateReadsInput b


-- | Does the 'Term' read the input symbol — via 'TInpField' (v1) or
-- 'TInpCtorField' (v2)?
termReadsInput :: Term rs ci r -> Bool
termReadsInput (TLit _)              = False
termReadsInput (TReg _)              = False
termReadsInput (TInpField _)         = True
termReadsInput (TInpCtorField _ _)   = True
termReadsInput (TApp1 _ t)           = termReadsInput t
termReadsInput (TApp2 _ a b)         = termReadsInput a || termReadsInput b


-- | Do the 'OutFields' contain a 'TInpField' anywhere?
outFieldsHaveInpField :: OutFields rs ci fs -> Bool
outFieldsHaveInpField OFNil           = False
outFieldsHaveInpField (OFCons t rest) =
  termReadsInput t || outFieldsHaveInpField rest
