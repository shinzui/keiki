-- 'combine''s 'Disjoint' constraint is the static check itself; GHC
-- sees it as unused (the body is @UCombine@) and would otherwise warn.
-- Same reasoning for any future helpers that re-export the constraint
-- as a typed witness.
{-# OPTIONS_GHC -Wno-redundant-constraints #-}

-- | The pure core of keiki: the symbolic-register transducer.
--
-- This module is the v1 prototype of the design pinned by
-- @docs/research/dsl-shape-for-symbolic-register.md@ (the DSL note),
-- @docs/research/effects-boundary.md@ (the boundary note), and
-- @docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md@
-- (the working baseline). See those notes for the rationale behind every
-- shape declared here.
--
-- All v1 escape hatches were retired by MasterPlan 6 (see the
-- Outcomes section of
-- @docs/masterplans/6-retire-remaining-v1-escape-hatches-in-pure-core-ofn-pmatchc-unsafecombine-static-check.md@):
-- @TInpField@ / @OPack@'s hand-written inverse (MP-2 EP-1), 'OFn' /
-- 'mkOut' (MP-6 EP-16), 'PMatchC' / 'matchCmd' (MP-6 EP-17), and
-- 'unsafeCombine' (MP-6 EP-18, replaced by the static 'Disjoint'
-- check on 'combine').
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
  , NumOp (..)
    -- * Input-side structural constructor (v2)
  , InCtor (..)
  , AssembleRegFile
  , KnownSlotNames (..)
    -- * Slot-name machinery (re-exported from "Keiki.Internal.Slots")
  , IndexN (..)
  , HasIndexN (..)
  , Disjoint
  , Concat
  , Names
    -- * Update language
  , Update (..)
  , combine
    -- * Output term language
  , WireCtor (..)
  , OutFields (..)
  , (*:)
  , oNil
  , OutTerm (..)
    -- * Predicate carrier (v1 first-class AST)
  , HsPred (..)
  , Cmp (..)
    -- * Effective Boolean algebra
  , BoolAlg (..)
  , Sat (..)
    -- * Edges and the transducer
  , Edge (..)
  , SymTransducer (..)
  , applyEdgeUpdate
  , edgeReadsInput
    -- * Helpers (the user-facing DSL surface)
  , matchInCtor
  , proj
  , inpCtor
  , lit
  , tadd
  , tsub
  , tmul
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
  , applyEvent
  , applyEventStreaming
  , applyEvents
    -- * Streaming-replay state wrapper (EP-19 M3)
  , InFlight (..)
    -- * Build-time analyses
  , solveOutput
  , HiddenInputWarning (..)
  , checkHiddenInputs
    -- * Internals exposed for testing
  , termReadsInput
  , updateReadsInput
  , outFieldsHaveInpCtorField
  , detectMissingInCtorFields
  , MissingInCtorFields (..)
  ) where

import Data.Kind (Type)
import Data.List (nub, (\\))
import Data.Proxy (Proxy (..))
import Data.Typeable (Typeable)
import GHC.OverloadedLabels (IsLabel (..))
import GHC.TypeLits (KnownSymbol, Symbol, symbolVal)
import Unsafe.Coerce (unsafeCoerce)

import Keiki.Internal.Slots
  ( Concat
  , Disjoint
  , HasIndexN (..)
  , IndexN (..)
  , Names
  )


-- | A register slot is a label paired with the type of its value.
type Slot = (Symbol, Type)


-- * Register file -----------------------------------------------------------

-- | A typed heterogeneous register tuple indexed by a list of 'Slot's.
--
-- The slot-value field is intentionally lazy: 'Keiki.Generics.emptyRegFile'
-- seeds each slot with a deferred @error "uninit: \<slot\>"@ thunk so
-- that reading an unwritten slot fails loudly with a targeted message
-- instead of returning a silent bottom. Strictness for *written*
-- slots is enforced on the write path ('setSlotN') instead — see
-- EP-23's Surprises entry for the long-running-service rationale.
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

-- | Resolve a label directly to a 'Term' that reads the named register.
-- This instance lets call sites write @#name@ in any 'Term'-typed
-- context (the arguments of 'requireEq', the elements of 'OutFields',
-- etc.) without the @proj (#name :: Index Regs T)@ annotation that
-- 'IsLabel s (Index rs r)' alone would require.
--
-- The two 'IsLabel' instances ('Index' and 'Term') coexist because GHC
-- dispatches by the expected result type: a context expecting an
-- 'Index' (e.g. 'inpFoo'\'s argument) selects the 'Index' instance; a
-- context expecting a 'Term' (e.g. 'requireEq'\'s arguments) selects
-- this one.
instance forall s rs ci r.
         HasIndex s rs r
      => IsLabel s (Term rs ci r) where
  fromLabel = TReg (indexOf @s @rs @r)

-- The @IsLabel s (IndexN s rs r)@ instance lives next to 'IndexN' in
-- "Keiki.Internal.Slots" so the orphan check is satisfied.


-- * Term language ----------------------------------------------------------

-- | A numeric operation carried by 'TArith'. @OpAdd@\/@OpSub@\/@OpMul@
-- are @+@\/@-@\/@*@ respectively. Kept as a single tag (rather than
-- three 'Term' constructors) so each total 'Term' walker switches on
-- one value; the three directions are recovered by the smart
-- constructors 'tadd'\/'tsub'\/'tmul'.
data NumOp = OpAdd | OpSub | OpMul
  deriving stock (Eq, Show)


-- | A pure expression over the register file and the input symbol,
-- yielding a value of type @r@.
data Term (rs :: [Slot]) (ci :: Type) (r :: Type) where
  TLit      :: r -> Term rs ci r
  TReg      :: Index rs r -> Term rs ci r
  -- | Structural input projection: read field @ix@ of the input
  -- constructor described by @ic@. The 'InCtor' value names the
  -- expected constructor and supplies the round-trip
  -- ('icMatch'/'icBuild') so that 'solveOutput' can mechanically
  -- recover @ci@ from an observed output. See
  -- @docs/research/tinpproj-design.md@.
  TInpCtorField :: InCtor ci ifs -> Index ifs r -> Term rs ci r
  TApp1     :: (a -> r)
            -> Term rs ci a
            -> Term rs ci r
  TApp2     :: (a -> b -> r)
            -> Term rs ci a
            -> Term rs ci b
            -> Term rs ci r
  -- | Structural arithmetic over a numeric operand type. Unlike the
  -- opaque 'TApp1'\/'TApp2' escape hatches, the SBV translator reads
  -- 'TArith' for real (on a 'Keiki.Symbolic.discoverSymNum' hit), so a
  -- guard over a /computed/ value — a weighted sum, a derived cap — is
  -- visible to the solver. The 'Num' constraint prevents constructing
  -- arithmetic at non-numeric operand types; 'Typeable' lets the SBV
  -- translator dispatch on @r@. Build with 'tadd'\/'tsub'\/'tmul'.
  TArith    :: (Num r, Typeable r)
            => NumOp
            -> Term rs ci r
            -> Term rs ci r
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
-- The constraints 'AssembleRegFile' and 'KnownSlotNames' on the data
-- constructor mean that any code holding an 'InCtor' can both
-- mechanically rebuild a 'RegFile' from a bag of '(Index, value)' pairs
-- and recover the slot names of @ifs@ at run time. The instances are
-- automatic for any concrete slot list, so users do not write any
-- additional code.
--
-- See @docs/research/tinpproj-design.md@ for the design rationale and
-- the inversion algorithm that walks 'OutFields' gathering these
-- per-field reads.
data InCtor ci (ifs :: [Slot]) where
  InCtor
    :: (AssembleRegFile ifs, KnownSlotNames ifs)
    => { icName  :: String
       , icMatch :: ci -> Maybe (RegFile ifs)
       , icBuild :: RegFile ifs -> ci
       }
    -> InCtor ci ifs


-- * Slot-list helper classes (v2 inversion machinery) ---------------------

-- | Recover the slot names of an @ifs :: [Slot]@ at run time. Used to
-- print precise hidden-input warnings.
class KnownSlotNames (rs :: [Slot]) where
  slotNames :: [String]

instance KnownSlotNames '[] where
  slotNames = []

instance (KnownSymbol s, KnownSlotNames rs)
      => KnownSlotNames ('(s, r) ': rs) where
  slotNames = symbolVal (Proxy @s) : slotNames @rs


-- | An (Index, value) pair indexed by an InCtor's slot list. Using a
-- GADT existential lets us bag entries with different element types
-- under one slot list and unpack them safely via pattern matching on
-- the carried 'Index'.
data ByIndex (ifs :: [Slot]) where
  ByIndex :: Index ifs r -> r -> ByIndex ifs


-- | Class to assemble a 'RegFile' from a bag of '(Index, value)' pairs.
-- 'assemble' returns 'Just' iff every slot of @ifs@ is covered by
-- exactly one entry of the bag (extra entries beyond what slots
-- demand are ignored as long as the per-slot lookups succeed in
-- order).
class AssembleRegFile (ifs :: [Slot]) where
  assemble :: [ByIndex ifs] -> Maybe (RegFile ifs)

instance AssembleRegFile '[] where
  assemble _ = Just RNil

instance (KnownSymbol s, AssembleRegFile rs)
      => AssembleRegFile ('(s, r) ': rs) where
  assemble entries = do
    v    <- findHead entries
    rest <- assemble (popHead entries)
    pure (RCons (Proxy @s) v rest)
    where
      findHead :: [ByIndex ('(s, r) ': rs)] -> Maybe r
      findHead []                       = Nothing
      findHead (ByIndex ZIdx v : _)     = Just v
      findHead (_ : rest)               = findHead rest

      popHead :: [ByIndex ('(s, r) ': rs)] -> [ByIndex rs]
      popHead []                                = []
      popHead (ByIndex ZIdx     _ : rest)       = popHead rest
      popHead (ByIndex (SIdx i) v : rest)       = ByIndex i v : popHead rest


-- * Update language --------------------------------------------------------

-- | The copyless update language. The @(w :: [Symbol])@ index
-- records the set of slot names this update writes; the smart
-- constructor 'combine' demands @'Disjoint' w1 w2@ to combine two
-- updates, so "each register is written at most once per edge
-- update" becomes a type-level invariant rather than a runtime check.
--
-- The 'UCombine' raw constructor is *not* constrained by 'Disjoint':
-- the invariant is enforced at the smart-constructor introduction
-- point ('combine'). This keeps internal pattern-matches in
-- "Keiki.Composition" (which reconstruct 'UCombine' values during
-- weakening / substitution) cheap. EP-18 M8 retired the v1
-- 'unsafeCombine' escape hatch; aggregate authors use 'combine'
-- exclusively.
data Update (rs :: [Slot]) (w :: [Symbol]) (ci :: Type) where
  UKeep    :: Update rs '[] ci
  USet     :: KnownSymbol s
           => IndexN s rs r -> Term rs ci r -> Update rs '[s] ci
  UCombine :: Update rs w1 ci
           -> Update rs w2 ci
           -> Update rs (Concat w1 w2) ci


-- | Smart constructor for 'UCombine'. The @'Disjoint' w1 w2@
-- constraint statically enforces that the two halves write to
-- disjoint slot-name sets; an aggregate that writes the same slot
-- twice (e.g. @'USet' #email t1 \`combine\` 'USet' #email t2@) is
-- rejected at compile time with a 'GHC.TypeError.TypeError' naming
-- the offending slot.
combine
  :: Disjoint w1 w2
  => Update rs w1 ci
  -> Update rs w2 ci
  -> Update rs (Concat w1 w2) ci
combine = UCombine




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


-- | Right-associative HList constructor synonym for 'OFCons'. Lets
-- 'OutFields' literals read top-to-bottom in the wire ctor's field
-- order:
--
-- > d.recipient *: d.subject *: d.at *: oNil
--
-- Identical AST: @t1 *: t2 *: oNil@ produces the same 'OutFields'
-- value as @OFCons t1 (OFCons t2 OFNil)@. Available at the AST
-- layer (here) so authors who skip the builder can use it; also
-- re-exported by "Keiki.Builder" for builder-form call sites.
(*:) :: Term rs ci f -> OutFields rs ci fs -> OutFields rs ci (f, fs)
(*:) = OFCons
infixr 5 *:


-- | The empty 'OutFields' HList. Synonym for 'OFNil'.
oNil :: OutFields rs ci ()
oNil = OFNil


-- | A pure expression yielding an output value @co@.
data OutTerm (rs :: [Slot]) (ci :: Type) (co :: Type) where
  -- | Structural pack: tagged by an input constructor (which the edge
  -- consumes) and an output wire constructor (which the edge produces),
  -- with one 'Term' per field of the wire constructor. 'solveOutput'
  -- walks the structural 'OutFields', gathering '(Index, value)' pairs
  -- against the named 'InCtor', and reconstructs the input by calling
  -- 'icBuild' on the assembled register file. Empty-payload input
  -- constructors (the 'InCtor's slot list is @\'[]@) recover trivially
  -- as @icBuild ic RNil@.
  OPack :: InCtor ci ifs
        -> WireCtor co fields
        -> OutFields rs ci fields
        -> OutTerm rs ci co


-- * Predicate carrier ------------------------------------------------------

-- | The predicate AST. Carries enough structure to evaluate guards and
-- to translate to SMT through the SBV-backed 'BoolAlg' instance in
-- "Keiki.Symbolic" (added in EP-2 of MasterPlan 2).
data HsPred (rs :: [Slot]) (ci :: Type) where
  PTop    :: HsPred rs ci
  PBot    :: HsPred rs ci
  PAnd    :: HsPred rs ci -> HsPred rs ci -> HsPred rs ci
  POr     :: HsPred rs ci -> HsPred rs ci -> HsPred rs ci
  PNot    :: HsPred rs ci -> HsPred rs ci
  PEq     :: (Eq r, Typeable r)
          => Term rs ci r -> Term rs ci r -> HsPred rs ci
  -- | Structural input-constructor guard: @True@ iff the input symbol
  -- is the constructor named by the carried 'InCtor'. The SBV-backed
  -- 'BoolAlg' instance recognises constructor mutual exclusion
  -- symbolically through this constructor. See
  -- @docs/research/sbv-boolalg-design.md@.
  PInCtor :: InCtor ci ifs -> HsPred rs ci
  -- | Ordering guard: compares two 'Term's of the same orderable type
  -- with the relation named by 'Cmp'. @PCmp CmpGe a b@ means @a >= b@,
  -- and so on. Unlike a threshold written through 'TApp1'\/'TApp2'
  -- (which is opaque to the solver), 'PCmp' is /structural/: the
  -- SBV-backed translator in "Keiki.Symbolic" emits a real symbolic
  -- comparison (@.<@, @.<=@, @.>@, @.>=@) whenever the operand type's
  -- 'Keiki.Symbolic.SymRep' is symbolically orderable (see
  -- 'Keiki.Symbolic.discoverSymOrd'); otherwise it falls back to a
  -- fresh opaque 'SBool', exactly as 'PEq' does for non-'Sym' operands.
  -- Equality is intentionally left to 'PEq' — 'Cmp' has no "equal"
  -- case. Added by EP-41.
  PCmp :: (Ord r, Typeable r)
       => Cmp -> Term rs ci r -> Term rs ci r -> HsPred rs ci


-- | A four-way ordering relation carried by 'PCmp'. @Lt@\/@Le@\/@Gt@\/
-- @Ge@ are @<@\/@<=@\/@>@\/@>=@ respectively. Kept as a single tag
-- (rather than four 'HsPred' constructors) so the evaluator and the
-- SBV translator each switch on one value; the four directions are
-- recovered by the builder conveniences
-- 'Keiki.Builder.requireLt'\/'requireLe'\/'requireGt'\/'requireGe'.
data Cmp = CmpLt | CmpLe | CmpGt | CmpGe
  deriving stock (Eq, Show)


-- * Effective Boolean algebra ----------------------------------------------

-- | An effective Boolean algebra over @a@-typed witnesses, used as the
-- guard carrier of edges. Witness /extraction/ ('sat') is a separate,
-- stronger capability — see 'Sat'.
class BoolAlg phi a | phi -> a where
  top    :: phi
  bot    :: phi
  conj   :: phi -> phi -> phi
  disj   :: phi -> phi -> phi
  neg    :: phi -> phi
  models :: phi -> a -> Bool
  isBot  :: phi -> Bool


-- | A 'BoolAlg' whose witnesses can be /extracted/ from a satisfiable
-- predicate: @'sat' phi@ returns 'Just' a value satisfying @phi@, or
-- 'Nothing' when @phi@ is unsatisfiable.
--
-- Split out of 'BoolAlg' by EP-44 (MasterPlan 12). Witness
-- reconstruction needs carrier-specific evidence — for the SBV-backed
-- 'Keiki.Symbolic.SymPred' carrier, @ExtractRegFile rs@ (to rebuild the
-- register file from the solver model) and @KnownInCtors ci@ (to rebuild
-- the command) — that the algebra's build/decide methods do not. Keeping
-- 'sat' in its own class means the witness-free analyses
-- ('Keiki.Symbolic.isSingleValuedSym', which uses only 'isBot'/'conj')
-- carry no extraction constraints, so they keep type-checking on
-- register-file-existential carriers (e.g. 'Keiki.Profunctor.SomeSymTransducer')
-- and on composition-produced @ci@ types ('Either', tuples) that have no
-- 'KnownInCtors'. See @docs/research/sbv-boolalg-design.md@.
class BoolAlg phi a => Sat phi a where
  sat :: phi -> Maybe a


instance BoolAlg (HsPred rs ci) (RegFile rs, ci) where
  top                 = PTop
  bot                 = PBot
  conj p q            = PAnd p q
  disj p q            = POr p q
  neg p               = PNot p
  models p (regs, ci) = evalPred p regs ci
  isBot PBot          = True
  isBot _             = False


-- | The v1 syntactic carrier has no solver, hence no extractable
-- witness; 'sat' is always 'Nothing'. The precise witnesses come from
-- the SBV-backed @Sat (SymPred …)@ instance in "Keiki.Symbolic".
instance Sat (HsPred rs ci) (RegFile rs, ci) where
  sat _ = Nothing


-- * Edges and the transducer -----------------------------------------------

-- | A single transition. The 'output' is a list of 'OutTerm's:
-- @[]@ is the ε-edge (no observable emission), @[o]@ is the letter
-- edge (one event, identical to today's @'Just' o@), @[o1, o2, ...]@
-- is the multi-event edge — one transition emits N events in
-- declaration order. See @docs/research/gsm-widening-design.md@.
--
-- The @(w :: [Symbol])@ index on 'update' (the slot-name set the
-- update writes) is *existentially* quantified at the 'Edge' record
-- — different edges out of the same vertex write different slot
-- sets, but the homogeneous list @[Edge phi rs ci co s]@ in
-- 'edgesOut' demands a single @Edge@ type. The existential preserves
-- the static disjointness check at the *introduction* point of any
-- 'Update' value (via 'combine') without polluting the @Edge@'s
-- public type with a per-edge @w@ parameter.
data Edge phi rs ci co s where
  Edge
    :: { guard  :: phi
       , update :: Update rs w ci
       , output :: [OutTerm rs ci co]
       , target :: s
       }
    -> Edge phi rs ci co s


-- | The single source of truth: a finite control graph plus a register
-- file evolved by edges' 'update' terms.
data SymTransducer phi rs s ci co = SymTransducer
  { edgesOut    :: s -> [Edge phi rs ci co s]
  , initial     :: s
  , initialRegs :: RegFile rs
  , isFinal     :: s -> Bool
  }


-- | Apply an edge's update to the register file. The 'Edge''s
-- existentially-quantified @w@ index makes @'update' e@ unusable as
-- a function (GHC rejects with "escaped type variables"); this
-- helper hides the existential by pattern-matching internally.
applyEdgeUpdate
  :: Edge phi rs ci co s -> RegFile rs -> ci -> RegFile rs
applyEdgeUpdate Edge{ update = u } regs ci = runUpdate u regs ci


-- | Does an edge's update read the input symbol via 'TInpCtorField'?
-- Existential-hiding companion to 'updateReadsInput'.
edgeReadsInput :: Edge phi rs ci co s -> Bool
edgeReadsInput Edge{ update = u } = updateReadsInput u


-- * Helpers (DSL surface) --------------------------------------------------

-- | Structural input-constructor guard: @True@ iff the input symbol
-- is the constructor named by the supplied 'InCtor'. The SBV-backed
-- 'BoolAlg' instance can decide constructor-mutual-exclusion
-- symbolically through this guard. The semantics is
-- @evalPred (matchInCtor ic) regs ci == isJust (icMatch ic ci)@.
matchInCtor :: InCtor ci ifs -> HsPred rs ci
matchInCtor = PInCtor


-- | Read a register slot into a 'Term'.
proj :: Index rs r -> Term rs ci r
proj = TReg


-- | Structural input projection: read field @ix@ of the input
-- constructor described by @ic@.
inpCtor :: InCtor ci ifs -> Index ifs r -> Term rs ci r
inpCtor = TInpCtorField


-- | A constant 'Term'.
lit :: r -> Term rs ci r
lit = TLit


-- | Structural arithmetic smart constructors. @tadd@\/@tsub@\/@tmul@
-- build a 'TArith' over @+@\/@-@\/@*@. The operand type must be numeric
-- ('Num') and 'Typeable'; the SBV translator reads them structurally
-- (see 'Keiki.Symbolic.discoverSymNum'), unlike the opaque 'TApp'
-- escape hatches.
tadd, tsub, tmul
  :: (Num r, Typeable r)
  => Term rs ci r -> Term rs ci r -> Term rs ci r
tadd = TArith OpAdd
tsub = TArith OpSub
tmul = TArith OpMul


-- | Equality predicate sugar.
(.==) :: (Eq r, Typeable r) => Term rs ci r -> Term rs ci r -> HsPred rs ci
(.==) = PEq
infix 4 .==


-- | Structural-output construction. 'solveOutput' inverts the result
-- mechanically by walking 'OutFields' against the named input
-- constructor; users no longer supply an inverse function. The
-- 'InCtor' first argument names the @ci@ constructor the edge expects;
-- it makes recovery work even for edges whose input has no payload
-- (e.g. a singleton 'Continue' command).
pack :: InCtor ci ifs
     -> WireCtor co fields
     -> OutFields rs ci fields
     -> OutTerm rs ci co
pack = OPack


-- * Evaluators -------------------------------------------------------------

-- | Evaluate a 'Term' against a register file and an input symbol.
evalTerm :: Term rs ci r -> RegFile rs -> ci -> r
evalTerm (TLit r)              _    _  = r
evalTerm (TReg ix)             regs _  = regs ! ix
evalTerm (TInpCtorField ic ix) _    ci = case icMatch ic ci of
  Just rf -> rf ! ix
  Nothing -> error ("evalTerm: TInpCtorField guard violation: " ++ icName ic)
evalTerm (TApp1 f t)           regs ci = f (evalTerm t regs ci)
evalTerm (TApp2 f a b)         regs ci = f (evalTerm a regs ci) (evalTerm b regs ci)
evalTerm (TArith op a b)       regs ci =
  applyNumOp op (evalTerm a regs ci) (evalTerm b regs ci)


-- | Interpret a 'NumOp' tag as the corresponding numeric operation.
-- The 'Num' evidence is supplied by matching the 'TArith' constructor.
applyNumOp :: Num r => NumOp -> r -> r -> r
applyNumOp OpAdd = (+)
applyNumOp OpSub = (-)
applyNumOp OpMul = (*)


-- | Evaluate an 'OutTerm' against a register file and an input symbol.
-- The 'InCtor' on 'OPack' is consulted only by the inverse direction
-- ('solveOutput'); evaluation just runs the wire build over the
-- evaluated 'OutFields'.
evalOut :: OutTerm rs ci co -> RegFile rs -> ci -> co
evalOut (OPack _ic ctor fields) regs ci =
  wcBuild ctor (evalOutFields fields regs ci)


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
evalPred (PInCtor ic)  _    c  = case icMatch ic c of
                                   Just _  -> True
                                   Nothing -> False
evalPred (PCmp op a b) r    c  = applyCmp op (evalTerm a r c) (evalTerm b r c)
  where
    applyCmp :: Ord x => Cmp -> x -> x -> Bool
    applyCmp CmpLt x y = x <  y
    applyCmp CmpLe x y = x <= y
    applyCmp CmpGt x y = x >  y
    applyCmp CmpGe x y = x >= y


-- | Apply an 'Update' to the register file. 'UCombine' applies left
-- then right; the smart 'combine''s 'Disjoint' constraint guarantees
-- the two halves write to disjoint slots, so the application order
-- does not affect the result.
runUpdate :: Update rs w ci -> RegFile rs -> ci -> RegFile rs
runUpdate UKeep          regs _  = regs
runUpdate (USet ix t)    regs ci = setSlotN ix (evalTerm t regs ci) regs
runUpdate (UCombine a b) regs ci = runUpdate b (runUpdate a regs ci) ci


-- | Pure register-file slot update at a slot-name-tagged 'IndexN'.
--
-- The bang-pattern on @v@ forces the new slot value to WHNF before
-- threading it into the rebuilt 'RCons'. Without this, every
-- 'runUpdate' / 'step' cycle in a long-running embedder accumulates
-- a tower of thunks at the written slot, which is exactly the failure
-- mode the @NoThunks (RegFile rs)@ instance ("Keiki.NoThunks") was
-- introduced to detect (EP-23). Untouched slots retain whatever
-- WHNF status they already had, which preserves
-- 'Keiki.Generics.emptyRegFile'\'s targeted @uninit:@ sentinels for
-- slots that have never been written.
setSlotN :: IndexN s rs r -> r -> RegFile rs -> RegFile rs
setSlotN IZ     !v regs = case regs of RCons p _ rest -> RCons p v rest
setSlotN (IS i) !v regs = case regs of
  RCons p x rest ->
    let !rest' = setSlotN i v rest
    in RCons p x rest'


-- | Single-step transition. Returns 'Just (s', regs')' iff exactly one
-- outgoing edge has a satisfied guard.
delta
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> s -> RegFile rs -> ci -> Maybe (s, RegFile rs)
delta t s regs ci =
  case [ (target e, applyEdgeUpdate e regs ci)
       | e <- edgesOut t s
       , models (guard e) (regs, ci)
       ] of
    [single] -> Just single
    _        -> Nothing


-- | Single-step output. Returns the list of events emitted by the
-- unique active edge: @[]@ for an ε-edge, @[o]@ for a letter edge,
-- @[o1, o2, ...]@ for a multi-event edge. Returns @[]@ if no edge
-- (or more than one edge) is active — the caller cannot distinguish
-- "no active edge" from "active ε-edge" from this function alone;
-- use 'step' or 'delta' if that distinction matters.
omega
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> s -> RegFile rs -> ci -> [co]
omega t s regs ci =
  case [ [ evalOut o regs ci | o <- output e ]
       | e <- edgesOut t s
       , models (guard e) (regs, ci)
       ] of
    [evaluatedOuts] -> evaluatedOuts
    _               -> []


-- * Pure-layer entry points ------------------------------------------------

-- | One full step of the transducer combining 'delta' and 'omega'.
-- Returns 'Nothing' if no edge from the current vertex has a satisfied
-- guard. The inner @[co]@ is @[]@ for an ε-edge, @[o]@ for a letter
-- edge, @[o1, o2, ...]@ for a multi-event edge.
step
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> (s, RegFile rs)
  -> ci
  -> Maybe (s, RegFile rs, [co])
step t (s, regs) ci = case delta t s regs ci of
  Nothing          -> Nothing
  Just (s', regs') -> Just (s', regs', omega t s regs ci)


-- | Apply one observed output to the state by walking outgoing edges,
-- inverting each edge's @output@ via 'solveOutput', verifying the
-- guard on the recovered input, and applying the edge's @update@.
-- Used by 'reconstitute' for full-log replay and exposed so that
-- single-event façades (notably 'Keiki.Decider.toDecider') can
-- implement an @evolve :: s -> e -> s@ step on top of it.
--
-- == Letter-only semantics
--
-- This function handles ε-edges (@output = []@; skipped because they
-- emit nothing observable) and letter edges (@output = [o]@;
-- inverted via 'solveOutput'). For multi-event edges (@output =
-- [o1, ..., oN]@ with N >= 2), this letter-flavoured 'applyEvent'
-- only inverts against the *head* of the output list, returning the
-- target vertex on a successful match. It is suitable when the
-- caller knows it is replaying letter-only events; for true
-- streaming replay across multi-event edges (where intermediate
-- events in the chain must be matched against the expected tail of
-- a prior edge's output list) use 'applyEventStreaming'.
applyEvent
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> s -> RegFile rs -> co -> Maybe (s, RegFile rs)
applyEvent t s regs co =
  case [ (target e, applyEdgeUpdate e regs ci)
       | e <- edgesOut t s
       , o : _   <- [output e]
       , Just ci <- [solveOutput o regs co]
       , models (guard e) (regs, ci)
       ] of
    [single] -> Just single
    _        -> Nothing


-- | Streaming-replay state wrapper. Used by 'applyEventStreaming'
-- (the InFlight-aware replay) and exposed as the carrier of the
-- 'Keiki.Decider.evolveStreaming' field added in EP-19 M5.
--
-- @'Settled' s@ is the state at a stable vertex — the next event
-- must be the first emission of /some/ outgoing edge of @s@.
--
-- @'InFlight' s [e2, ..., eN]@ is the mid-chain state at vertex
-- @s@ (the *target* of the in-flight chain's edge; register updates
-- have already been applied at the transition into 'InFlight'). The
-- queue holds the *evaluated* expected events in order; the next
-- observed event must equal the head, popping it; when the queue
-- empties, the wrapper transitions to @'Settled' s@.
--
-- See @docs/research/gsm-widening-design.md@ §4 for the formal
-- treatment and a worked example on the @StartRegistration@ chain.
data InFlight s co
  = Settled  !s
  | InFlight !s ![co]
  deriving (Eq, Show)


-- | Apply one observed output to a streaming-replay state. Two arms:
--
--   1. @'Settled' s@ — walk outgoing edges of @s@; find the unique
--      edge whose @output@'s *head* inverts to a valid @ci@ via
--      'solveOutput' satisfying the guard. Commit to that edge, run
--      its update, evaluate the *tail* of the output list against
--      the recovered @(regs, ci)@ snapshot. If the tail is empty
--      (letter edge), return @('Settled' (target e), regs')@. If the
--      tail is non-empty (multi-event edge), return @('InFlight'
--      (target e) tail, regs')@.
--
--   2. @'InFlight' s (q1 : rest) regs@ — equality-check @q1@
--      against the observed event. On match, advance the queue
--      (returning @'Settled' s@ when @rest == []@, otherwise
--      @'InFlight' s rest@). No register update — registers were
--      updated at the @Settled → InFlight@ transition. On mismatch
--      (out-of-order replay) return 'Nothing'.
--
-- The 'Eq' constraint on @co@ supports the queue equality check.
-- Most aggregate event types derive 'Eq' (a documented expectation
-- of the foundations).
applyEventStreaming
  :: (BoolAlg phi (RegFile rs, ci), Eq co)
  => SymTransducer phi rs s ci co
  -> InFlight s co -> RegFile rs -> co
  -> Maybe (InFlight s co, RegFile rs)
applyEventStreaming t (Settled s) regs co =
  case [ (e, ci) | e <- edgesOut t s
                 , o : _   <- [output e]
                 , Just ci <- [solveOutput o regs co]
                 , models (guard e) (regs, ci)
       ] of
    [(e, ci)] ->
      let regs'         = applyEdgeUpdate e regs ci
          evaluatedTail = [ evalOut o regs ci | o <- drop 1 (output e) ]
          wrapped       = case evaluatedTail of
            [] -> Settled (target e)
            xs -> InFlight (target e) xs
      in Just (wrapped, regs')
    _ -> Nothing
applyEventStreaming _ (InFlight s queue) regs co = case queue of
  []          -> Nothing
  [q1]
    | q1 == co -> Just (Settled s, regs)
    | otherwise -> Nothing
  (q1 : rest)
    | q1 == co -> Just (InFlight s rest, regs)
    | otherwise -> Nothing


-- | Reconstitute @(state, registers)@ from a log of outputs by
-- replaying each event through the InFlight-aware
-- 'applyEventStreaming', which threads mid-chain state through
-- multi-event edges invisibly and unwraps to 'Settled' at the log's
-- end.
--
-- For letter-only transducers (every edge has @output@ of length 0
-- or 1) the streaming wrapper is always 'Settled' and the result is
-- identical to the pre-EP-19 letter-fold. A log that ends mid-chain
-- through a multi-event edge returns 'Nothing' — there is no valid
-- @(s, regs)@ to surface from an 'InFlight' final state.
reconstitute
  :: (BoolAlg phi (RegFile rs, ci), Eq co)
  => SymTransducer phi rs s ci co
  -> [co]
  -> Maybe (s, RegFile rs)
reconstitute t = applyEvents t (initial t, initialRegs t)


-- | Replay a chunk of events from a caller-supplied
-- @(state, registers)@ start. Structurally similar to 'reconstitute'
-- except that the start state is an argument rather than the
-- transducer's initial state, so a runtime adapter can chunk-replay
-- the events corresponding to one logical command from any current
-- state.
--
-- Useful when the runtime preserves command boundaries (event store
-- with command-id tags, transactional batches, deterministic test
-- fixtures): replay one command's events as one atomic step and
-- consume the unwrapped final state.
--
-- == Multi-event edges (EP-19 M3)
--
-- Internally, the implementation lifts the start state to 'Settled'
-- and folds 'applyEventStreaming' over the chunk; the wrapper
-- transitions through 'InFlight' for multi-event edges and unwraps
-- back to 'Settled' when the chunk completes. A chunk that ends
-- mid-flight (the queue is non-empty at the end of the input list)
-- returns 'Nothing'; this signals a truncated chunk relative to the
-- edge's static output length.
--
-- For length-0/1 edges the behaviour is identical to the legacy
-- letter-fold; for length-2+ edges the chunk must contain the full
-- expected sequence of evaluated events in order.
--
-- Returns 'Nothing' if any event in the chunk fails to replay (e.g.
-- a malformed log, an event that does not match any active edge's
-- output at the current vertex, or a chunk that ends mid-flight).
applyEvents
  :: (BoolAlg phi (RegFile rs, ci), Eq co)
  => SymTransducer phi rs s ci co
  -> (s, RegFile rs)
  -> [co]
  -> Maybe (s, RegFile rs)
applyEvents t (s0, regs0) cos_ = go (Settled s0) regs0 cos_
  where
    go (Settled s) regs []     = Just (s, regs)
    go (InFlight _ _) _    []  = Nothing  -- chunk ended mid-flight
    go inFlight regs (co : rest) = do
      (inFlight', regs') <- applyEventStreaming t inFlight regs co
      go inFlight' regs' rest


-- * Build-time analyses ----------------------------------------------------

-- | Recover the input that produced a given output by walking
-- 'OutFields' structurally against the input constructor named by the
-- 'OPack'. Gather '(Index, value)' pairs from every 'TInpCtorField'
-- read whose 'InCtor' matches by 'icName'; assemble a 'RegFile'
-- covering every slot of the 'InCtor'; call 'icBuild'.
solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci
solveOutput (OPack ic@InCtor{} ctor fields) _regs co = do
  fs_obs  <- wcMatch ctor co
  entries <- gatherInpEntries fields fs_obs ic
  rf      <- assemble entries
  pure (icBuild ic rf)


-- | Walk an 'OutFields' HList in lockstep with an observed-fields
-- tuple, gathering '(Index, value)' pairs for the named 'InCtor'.
-- Returns 'Nothing' on a malformed edge (a 'TInpCtorField' for a
-- different 'InCtor', or any opaque term such as 'TApp1' or
-- 'TApp2'). Returns @'Just' []@ for an 'OutFields' that carries no
-- input projection; 'assemble []' for an empty 'ifs' is 'Just RNil',
-- so empty-payload input constructors recover trivially.
gatherInpEntries
  :: forall rs ci ifs fs.
     OutFields rs ci fs -> fs -> InCtor ci ifs -> Maybe [ByIndex ifs]
gatherInpEntries OFNil           ()        _ic = Just []
gatherInpEntries (OFCons t rest) (v, fs)   ic  = do
  here <- stepOne t v ic
  more <- gatherInpEntries rest fs ic
  pure (here ++ more)
  where
    stepOne :: forall f. Term rs ci f -> f -> InCtor ci ifs -> Maybe [ByIndex ifs]
    stepOne (TLit _)                  _val _   = Just []
    stepOne (TReg _)                  _val _   = Just []
    stepOne (TInpCtorField ic2 ix)    val  ic1
      | icName ic1 == icName ic2 = Just [ByIndex (unsafeCoerce ix) val]
      | otherwise                = Nothing
    stepOne (TApp1 _ _)               _val _   = Nothing
    stepOne (TApp2 _ _ _)             _val _   = Nothing
    stepOne (TArith _ _ _)            _val _   = Nothing


-- | A diagnostic produced by 'checkHiddenInputs'.
data HiddenInputWarning = HiddenInputWarning
  { hiwEdgeSource :: String
    -- ^ Description of the edge's source (typically @show s@).
  , hiwReason     :: String
    -- ^ Human-readable description of what's hidden.
  } deriving (Eq, Show)


-- | For every edge in the transducer, check whether the @output@ can
-- mechanically recover the input on replay. Specifically:
--
--   * If @output@ is @[]@ (an ε-edge), and @update@ reads the input
--     symbol, that contribution is silent on the wire and
--     unrecoverable.
--   * If @output@ is non-empty, the per-edge check groups the
--     'OPack's by 'InCtor' name (via 'icName') and computes the
--     *union* of slots visited across every 'OPack' naming the same
--     'InCtor'. If the union still leaves any of the 'InCtor''s
--     slots unvisited, the warning names the 'InCtor' and the
--     missing slot(s).
--
-- For length-1 edges this matches the legacy per-'OPack' check
-- (there is only one 'OPack' so the union is trivial). For length-2+
-- edges the union strengthening means an 'InCtor' jointly recovered
-- by multiple 'OPack's in the same edge — none of which covers all
-- slots alone, but together they do — does *not* fire the warning.
--
-- The check is intentionally conservative: it flags candidates for
-- the author to inspect, not theorems.
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
      []
        | edgeReadsInput e ->
            [ "edge #" <> show n <> ": ε-edge with input read in update" ]
        | otherwise -> []
      outs -> unionMisses n outs

    -- | For an edge's non-empty output list, group OPacks by InCtor
    -- name; for each group, compute the union of visited slots; flag
    -- any InCtor whose slot list is not fully covered by the union.
    -- The grouping preserves first-seen order so warning messages
    -- are deterministic.
    unionMisses :: Int -> [OutTerm rs ci co] -> [String]
    unionMisses n outs =
      let groups = groupByInCtorName outs
      in [ formatMiss n icN missing
         | (icN, allSlots, visitedUnion) <- groups
         , let missing = allSlots \\ nub visitedUnion
         , not (null missing)
         ]

    -- | Walk the output list, accumulating per-InCtor (slot list,
    -- visited slots). First seen wins on the slot list; subsequent
    -- OPacks with the same InCtor name extend the visited list.
    groupByInCtorName
      :: [OutTerm rs ci co] -> [(String, [String], [String])]
    groupByInCtorName = foldl add []
      where
        add acc (OPack ic _ fields) =
          let icN     = icName ic
              allSl   = slotNamesOf ic
              visited = visitedSlotsOf ic fields
          in extend acc icN allSl visited

        extend [] icN allSl visited = [(icN, allSl, visited)]
        extend ((n, sl, v) : rest) icN allSl visited
          | n == icN  = (n, sl, v ++ visited) : rest
          | otherwise = (n, sl, v) : extend rest icN allSl visited

    -- | Slots of an OPack's named 'InCtor' that the supplied
    -- 'OutFields' walk visits via 'TInpCtorField'.
    visitedSlotsOf
      :: forall ifs fs.
         InCtor ci ifs -> OutFields rs ci fs -> [String]
    visitedSlotsOf ic@InCtor{} fields = goFields fields
      where
        allSlots = slotNamesOf ic

        goFields :: forall fs'. OutFields rs ci fs' -> [String]
        goFields OFNil           = []
        goFields (OFCons tt rest) = goTerm tt ++ goFields rest

        goTerm :: forall r. Term rs ci r -> [String]
        goTerm (TInpCtorField ic2 ix)
          | icName ic2 == icName ic =
              [allSlots !! indexPos ix]
          | otherwise = []
        goTerm (TApp1 _ tt')  = goTerm tt'
        goTerm (TApp2 _ a b)  = goTerm a ++ goTerm b
        goTerm (TArith _ a b) = goTerm a ++ goTerm b
        goTerm _              = []

        indexPos :: forall rs' r. Index rs' r -> Int
        indexPos ZIdx     = 0
        indexPos (SIdx i) = 1 + indexPos i

    formatMiss :: Int -> String -> [String] -> String
    formatMiss n icN missing =
      "edge #" <> show n
        <> ": OPack walk for InCtor \"" <> icN
        <> "\" leaves field"
        <> (if length missing == 1 then " " else "s ")
        <> "{" <> showMissing missing <> "} unrecovered"

    showMissing :: [String] -> String
    showMissing []     = ""
    showMissing [x]    = "\"" <> x <> "\""
    showMissing (x:xs) = "\"" <> x <> "\", " <> showMissing xs


-- | Does the 'Update' read the input symbol via 'TInpCtorField'?
updateReadsInput :: Update rs w ci -> Bool
updateReadsInput UKeep          = False
updateReadsInput (USet _ t)     = termReadsInput t
updateReadsInput (UCombine a b) = updateReadsInput a || updateReadsInput b


-- | Does the 'Term' read the input symbol via 'TInpCtorField'?
termReadsInput :: Term rs ci r -> Bool
termReadsInput (TLit _)              = False
termReadsInput (TReg _)              = False
termReadsInput (TInpCtorField _ _)   = True
termReadsInput (TApp1 _ t)           = termReadsInput t
termReadsInput (TApp2 _ a b)         = termReadsInput a || termReadsInput b
termReadsInput (TArith _ a b)        = termReadsInput a || termReadsInput b


-- | Do the 'OutFields' contain a 'TInpCtorField' read anywhere?
outFieldsHaveInpCtorField :: OutFields rs ci fs -> Bool
outFieldsHaveInpCtorField OFNil           = False
outFieldsHaveInpCtorField (OFCons t rest) =
  termHasInpCtorField t || outFieldsHaveInpCtorField rest
  where
    termHasInpCtorField :: Term rs ci r -> Bool
    termHasInpCtorField (TLit _)              = False
    termHasInpCtorField (TReg _)              = False
    termHasInpCtorField (TInpCtorField _ _)   = True
    termHasInpCtorField (TApp1 _ t')          = termHasInpCtorField t'
    termHasInpCtorField (TApp2 _ a b)         = termHasInpCtorField a || termHasInpCtorField b
    termHasInpCtorField (TArith _ a b)        = termHasInpCtorField a || termHasInpCtorField b


-- | The result of 'detectMissingInCtorFields': the offending 'InCtor'
-- name plus the names of slots its 'OutFields' walk does not visit.
data MissingInCtorFields = MissingInCtorFields
  { mifIcName  :: String
  , mifMissing :: [String]
  } deriving (Eq, Show)


-- | Given the 'InCtor' an 'OPack' is tagged with and that 'OPack'\'s
-- 'OutFields', return the field names of the 'InCtor' that the
-- 'OutFields' walk does not visit. 'Nothing' means every slot of the
-- 'InCtor' is visited. The slot list comes from the 'InCtor' itself
-- (via 'KnownSlotNames'), not from any 'TInpCtorField' inside the
-- 'OutFields' — this lets us flag empty 'OutFields' against a non-
-- empty 'InCtor' as well.
detectMissingInCtorFields
  :: forall rs ci ifs fs.
     InCtor ci ifs
  -> OutFields rs ci fs
  -> Maybe MissingInCtorFields
detectMissingInCtorFields ic@InCtor{} fields =
  case allSlots \\ nub visited of
    []      -> Nothing
    missing -> Just (MissingInCtorFields (icName ic) missing)
  where
    allSlots = slotNamesOf ic
    visited  = goFields fields

    goFields :: forall fs'. OutFields rs ci fs' -> [String]
    goFields OFNil           = []
    goFields (OFCons t rest) = goTerm t ++ goFields rest

    goTerm :: forall r. Term rs ci r -> [String]
    goTerm (TInpCtorField ic2 ix)
      | icName ic2 == icName ic =
          [allSlots !! indexPos ix]
      | otherwise = []
    goTerm (TApp1 _ t')   = goTerm t'
    goTerm (TApp2 _ a b)  = goTerm a ++ goTerm b
    goTerm (TArith _ a b) = goTerm a ++ goTerm b
    goTerm _              = []

    indexPos :: forall rs' r. Index rs' r -> Int
    indexPos ZIdx     = 0
    indexPos (SIdx i) = 1 + indexPos i


-- | Read the slot-name list out of an 'InCtor' (uses the
-- 'KnownSlotNames' instance carried by the data constructor).
slotNamesOf :: forall ci ifs. InCtor ci ifs -> [String]
slotNamesOf InCtor{} = slotNames @ifs
