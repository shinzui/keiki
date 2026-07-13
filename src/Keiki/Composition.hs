{-# LANGUAGE TypeFamilies #-}
-- 'compose''s @Disjoint (Names rs1) (Names rs2)@ constraint is the
-- documented precondition that @rs1@ and @rs2@ have disjoint
-- slot-name domains; the body uses raw 'UCombine' (decision logged
-- in EP-18) so GHC sees the constraint as unused. Same reasoning as
-- "Keiki.Core"'s 'combine'.
{-# OPTIONS_GHC -Wno-redundant-constraints #-}

-- | Sequential composition of two 'SymTransducer's.
--
-- The single user-facing value is 'compose'. Given a transducer @t1@
-- whose output alphabet is @mid@ and a transducer @t2@ whose input
-- alphabet is also @mid@, @compose t1 t2@ is the composite transducer
-- whose input is t1's input, whose output is t2's output, whose
-- vertex is the pair (wrapped in 'Composite' so 'Bounded'/'Enum'
-- derive cleanly), and whose register file is @'Append' rs1 rs2@.
--
-- See @docs/research/composition-combinators-design.md@ for the
-- formal semantics, the substitution algorithm, the proof sketch
-- of single-valuedness preservation, and the documented
-- limitations (t1 outputs must be 'OPack', t2 mid-side guards must
-- be structural, both must avoid the v1 escape hatches).
--
-- Both EP-11 (under MP-4) and the design note are the source of
-- truth; this module's haddock summarises the mechanics, not the
-- rationale.
module Keiki.Composition
  ( -- * The composite vertex
    Composite (..),

    -- * Sequential composition
    compose,

    -- * Disjoint-input dispatch
    alternative,

    -- * Single-step feedback
    feedback1,

    -- * Index / term weakening (exposed for advanced uses)
    WeakenR (..),
    weakenL,
    weakenLTerm,
    weakenLPred,
    weakenLUpdate,
    weakenRTerm,
    weakenRPred,
    weakenRUpdate,
    weakenROutFields,

    -- * Slot-list witnesses
    SlotListWitness (..),
    KnownSlots (..),
    appendWitness,
    withKnownSlots,
    withDisjointNil,
    witnessNames,

    -- * Substitution (exposed for advanced uses)
    substTerm,
    substPred,
    substUpdate,
    substOut,
    substOutFields,

    -- * Either lifters (alternative-side, exposed for advanced uses)
    leftInCtor,
    rightInCtor,
    leftWireCtor,
    rightWireCtor,
    liftLTermAlt,
    liftRTermAlt,
    liftLPredAlt,
    liftRPredAlt,
    liftLUpdateAlt,
    liftRUpdateAlt,
    liftLOutAlt,
    liftROutAlt,
    liftLOutFieldsAlt,
    liftROutFieldsAlt,

    -- * N-ary coproduct injectors (EP-48)
    wireCtor3At1,
    wireCtor3At2,
    wireCtor3At3,
    inCtor3At1,
    inCtor3At2,
    inCtor3At3,
    outTerm3At1,
    outTerm3At2,
    outTerm3At3,
  )
where

import Data.Type.Equality ((:~:) (Refl))
import GHC.TypeLits (KnownSymbol)
import Keiki.Core
import Keiki.Generics (Append, appendRegFile)
import NoThunks.Class (NoThunks (..), allNoThunks)
import Unsafe.Coerce (unsafeCoerce)

-- * The composite vertex ---------------------------------------------------

-- | The composite of two vertex types. A newtype around a pair so
-- 'Bounded'/'Enum'/'Eq'/'Show' derive cleanly without orphan
-- instances on @(s1, s2)@ — those would conflict with downstream
-- code.
data Composite s1 s2 = Composite !s1 !s2
  deriving (Eq, Ord, Show)

instance (Bounded s1, Bounded s2) => Bounded (Composite s1 s2) where
  minBound = Composite minBound minBound
  maxBound = Composite maxBound maxBound

-- | Column-major enumeration: @Composite s1 s2@ enumerates
-- @s2@ within each @s1@. Indexing assumes both component
-- @Enum@s have contiguous @[minBound .. maxBound]@ ranges (the
-- common case for a derived 'Enum' on an enum-like data type).
instance
  ( Bounded s1,
    Enum s1,
    Bounded s2,
    Enum s2
  ) =>
  Enum (Composite s1 s2)
  where
  toEnum n =
    let n2 = fromEnum (maxBound :: s2) - fromEnum (minBound :: s2) + 1
        (q, r) = n `divMod` n2
     in Composite
          (toEnum (q + fromEnum (minBound :: s1)))
          (toEnum (r + fromEnum (minBound :: s2)))
  fromEnum (Composite a b) =
    let n2 = fromEnum (maxBound :: s2) - fromEnum (minBound :: s2) + 1
        ai = fromEnum a - fromEnum (minBound :: s1)
        bi = fromEnum b - fromEnum (minBound :: s2)
     in ai * n2 + bi

-- The 'Composite' constructor is strict in both components by
-- construction (see the bang patterns above), so leaks can only enter
-- through the children. The instance recurses into both.
instance (NoThunks s1, NoThunks s2) => NoThunks (Composite s1 s2) where
  showTypeOf _ = "Composite"
  wNoThunks ctx (Composite a b) =
    allNoThunks
      [ noThunks ("Composite.left" : ctx) a,
        noThunks ("Composite.right" : ctx) b
      ]

-- * WeakenR: lift an Index over rs2 to (Append rs1 rs2) -------------------

-- | Lift a tail-side 'Index' (or 'IndexN') across an rs1 prefix.
-- The class is indexed by @rs1@; instances walk rs1's slot list with
-- 'SIdx' / 'IS' prepends, converting an @'Index' rs2 r@ into an
-- @'Index' (Append rs1 rs2) r@ and an @'IndexN' s rs2 r@ into an
-- @'IndexN' s (Append rs1 rs2) r@.
class WeakenR (rs1 :: [Slot]) where
  weakenR ::
    forall rs2 r. Index rs2 r -> Index (Append rs1 rs2) r
  weakenRIndexN ::
    forall rs2 s r. IndexN s rs2 r -> IndexN s (Append rs1 rs2) r

instance WeakenR '[] where
  weakenR i = i
  weakenRIndexN i = i

instance (WeakenR rs1) => WeakenR ('(s, t) ': rs1) where
  weakenR i = SIdx (weakenR @rs1 i)
  weakenRIndexN i = IS (weakenRIndexN @rs1 i)

-- * Slot-list witnesses ---------------------------------------------------

-- | Value-level singleton of a slot-list spine. 'WNil' mirrors @'[]@;
-- 'WCons' mirrors one cons cell, capturing the slot name's
-- 'KnownSymbol'. Packed by 'Keiki.Profunctor.SomeSymTransducer' at
-- wrap time (where @rs@ is concrete) so that instance dictionaries
-- for hidden slot lists can later be re-derived by structural
-- recursion instead of fabricated with @unsafeCoerce@.
data SlotListWitness (rs :: [Slot]) where
  WNil :: SlotListWitness '[]
  WCons :: (KnownSymbol s) => SlotListWitness rs -> SlotListWitness ('(s, t) ': rs)

-- | Conjure a 'SlotListWitness' for a concrete slot list. The
-- superclasses bundle the two structural classes every wrapper
-- consumer needs, so a packed @KnownSlots rs@ also supplies
-- 'WeakenR' and 'KnownSlotNames'.
class (WeakenR rs, KnownSlotNames rs) => KnownSlots (rs :: [Slot]) where
  slotWitness :: SlotListWitness rs

instance KnownSlots '[] where
  slotWitness = WNil

instance (KnownSymbol s, KnownSlots rs) => KnownSlots ('(s, t) ': rs) where
  slotWitness = WCons (slotWitness @rs)

-- | Append two witnesses. This is the value-level mirror of
-- 'Keiki.Generics.appendRegFile'; each equation matches one
-- 'Append' reduction step.
appendWitness ::
  SlotListWitness rs1 ->
  SlotListWitness rs2 ->
  SlotListWitness (Append rs1 rs2)
appendWitness WNil w2 = w2
appendWitness (WCons w1) w2 = WCons (appendWitness w1 w2)

-- | Discharge @KnownSlots rs@, and therefore 'WeakenR rs' and
-- 'KnownSlotNames rs', from a witness by induction on its spine.
withKnownSlots :: SlotListWitness rs -> ((KnownSlots rs) => r) -> r
withKnownSlots WNil k = k
withKnownSlots (WCons w) k = withKnownSlots w k

-- | Discharge @Disjoint (Names rs) '[]@: no slot name collides with
-- the empty list. This replaces the fabricated evidence formerly
-- used by 'Keiki.Profunctor.left''.
withDisjointNil :: SlotListWitness rs -> ((Disjoint (Names rs) '[]) => r) -> r
withDisjointNil WNil k = k
withDisjointNil (WCons w) k = withDisjointNil w k

-- | Return the names described by a witness, using the same induction
-- that re-derives the structural dictionaries.
witnessNames :: forall rs. SlotListWitness rs -> [String]
witnessNames w = withKnownSlots w (slotNames @rs)

-- * weakenL: lift an Index over rs1 to (Append rs1 rs2) -------------------

-- | Lift a head-side 'Index' across an rs2 suffix. Walks the
-- existing 'Index' shape; @ZIdx@ stays @ZIdx@, @SIdx i@ recurses.
weakenL :: forall rs1 rs2 r. Index rs1 r -> Index (Append rs1 rs2) r
weakenL ZIdx = ZIdx
weakenL (SIdx i) = SIdx (weakenL @_ @rs2 i)

-- | Walk a 'Term' and weaken every register read across an rs2
-- suffix. 'TInpCtorField' / 'TLit' do not touch the register file,
-- so they pass through unchanged.
weakenLTerm ::
  forall rs1 rs2 ci ifs r.
  Term rs1 ci ifs r -> Term (Append rs1 rs2) ci ifs r
weakenLTerm (TLit r) = TLit r
weakenLTerm (TReg ix) = TReg (weakenL @rs1 @rs2 ix)
weakenLTerm (TInpCtorField ic ix) = TInpCtorField ic ix
weakenLTerm (TApp1 f t) = TApp1 f (weakenLTerm @rs1 @rs2 t)
weakenLTerm (TArith op a b) =
  TArith op (weakenLTerm @rs1 @rs2 a) (weakenLTerm @rs1 @rs2 b)
weakenLTerm (TApp2 f a b) =
  TApp2
    f
    (weakenLTerm @rs1 @rs2 a)
    (weakenLTerm @rs1 @rs2 b)

-- | Walk an 'HsPred' and weaken every term inside it.
weakenLPred ::
  forall rs1 rs2 ci.
  HsPred rs1 ci -> HsPred (Append rs1 rs2) ci
weakenLPred PTop = PTop
weakenLPred PBot = PBot
weakenLPred (PAnd p q) =
  PAnd
    (weakenLPred @rs1 @rs2 p)
    (weakenLPred @rs1 @rs2 q)
weakenLPred (POr p q) =
  POr
    (weakenLPred @rs1 @rs2 p)
    (weakenLPred @rs1 @rs2 q)
weakenLPred (PNot p) = PNot (weakenLPred @rs1 @rs2 p)
weakenLPred (PEq a b) =
  PEq
    (weakenLTerm @rs1 @rs2 a)
    (weakenLTerm @rs1 @rs2 b)
weakenLPred (PInCtor ic) = PInCtor ic
weakenLPred (PCmp op a b) =
  PCmp
    op
    (weakenLTerm @rs1 @rs2 a)
    (weakenLTerm @rs1 @rs2 b)

-- | Walk an 'Update' and weaken every register write + every
-- right-hand-side 'Term'. The slot-name index @w@ is preserved by
-- weakening — adding new slots to the right of @rs1@ does not change
-- which slot names the update writes.
weakenLUpdate ::
  forall rs1 rs2 w ci.
  Update rs1 w ci -> Update (Append rs1 rs2) w ci
weakenLUpdate UKeep = UKeep
weakenLUpdate (USet ix t) =
  USet
    (weakenLIndexN @rs1 @rs2 ix)
    (weakenLTerm @rs1 @rs2 t)
weakenLUpdate (UCombine a b) =
  UCombine
    (weakenLUpdate @rs1 @rs2 a)
    (weakenLUpdate @rs1 @rs2 b)

-- | Slot-name-tagged analogue of 'weakenL'. Walks an existing
-- 'IndexN' shape; @IZ@ stays @IZ@, @IS i@ recurses. Preserves the
-- slot symbol carried by the index.
weakenLIndexN :: forall rs1 rs2 s r. IndexN s rs1 r -> IndexN s (Append rs1 rs2) r
weakenLIndexN IZ = IZ
weakenLIndexN (IS i) = IS (weakenLIndexN @_ @rs2 i)

-- * weakenR-walking helpers: lift terms / preds / updates over an rs1 prefix --

-- | Walk a 'Term' on a tail-side register file and lift every register
-- read across an rs1 prefix using 'weakenR'. The input alphabet @ci@
-- is preserved.
weakenRTerm ::
  forall rs1 rs2 ci ifs r.
  (WeakenR rs1) =>
  Term rs2 ci ifs r -> Term (Append rs1 rs2) ci ifs r
weakenRTerm (TLit r) = TLit r
weakenRTerm (TReg ix) = TReg (weakenR @rs1 ix)
weakenRTerm (TInpCtorField ic ix) = TInpCtorField ic ix
weakenRTerm (TApp1 f t) = TApp1 f (weakenRTerm @rs1 @rs2 t)
weakenRTerm (TArith op a b) =
  TArith op (weakenRTerm @rs1 @rs2 a) (weakenRTerm @rs1 @rs2 b)
weakenRTerm (TApp2 f a b) =
  TApp2
    f
    (weakenRTerm @rs1 @rs2 a)
    (weakenRTerm @rs1 @rs2 b)

-- | Walk an 'HsPred' on a tail-side register file and lift every term
-- inside via 'weakenRTerm'.
weakenRPred ::
  forall rs1 rs2 ci.
  (WeakenR rs1) =>
  HsPred rs2 ci -> HsPred (Append rs1 rs2) ci
weakenRPred PTop = PTop
weakenRPred PBot = PBot
weakenRPred (PAnd p q) =
  PAnd
    (weakenRPred @rs1 @rs2 p)
    (weakenRPred @rs1 @rs2 q)
weakenRPred (POr p q) =
  POr
    (weakenRPred @rs1 @rs2 p)
    (weakenRPred @rs1 @rs2 q)
weakenRPred (PNot p) = PNot (weakenRPred @rs1 @rs2 p)
weakenRPred (PEq a b) =
  PEq
    (weakenRTerm @rs1 @rs2 a)
    (weakenRTerm @rs1 @rs2 b)
weakenRPred (PInCtor ic) = PInCtor ic
weakenRPred (PCmp op a b) =
  PCmp
    op
    (weakenRTerm @rs1 @rs2 a)
    (weakenRTerm @rs1 @rs2 b)

-- | Walk an 'Update' on a tail-side register file and lift every
-- register write + RHS 'Term' across an rs1 prefix. The slot-name
-- index @w@ is preserved.
weakenRUpdate ::
  forall rs1 rs2 w ci.
  (WeakenR rs1) =>
  Update rs2 w ci -> Update (Append rs1 rs2) w ci
weakenRUpdate UKeep = UKeep
weakenRUpdate (USet ix t) =
  USet
    (weakenRIndexN @rs1 ix)
    (weakenRTerm @rs1 @rs2 t)
weakenRUpdate (UCombine a b) =
  UCombine
    (weakenRUpdate @rs1 @rs2 a)
    (weakenRUpdate @rs1 @rs2 b)

-- | Walk an 'OutFields' chain on a tail-side register file and lift
-- every term across an rs1 prefix.
weakenROutFields ::
  forall rs1 rs2 ci ifs fs.
  (WeakenR rs1) =>
  OutFields rs2 ci ifs fs -> OutFields (Append rs1 rs2) ci ifs fs
weakenROutFields OFNil = OFNil
weakenROutFields (OFCons t rest) =
  OFCons
    (weakenRTerm @rs1 @rs2 t)
    (weakenROutFields @rs1 @rs2 rest)

-- | Walk an 'OutTerm' on a tail-side register file and lift every
-- register read across an rs1 prefix. The 'OPack' wrapping is
-- structurally preserved; only the underlying 'OutFields' chain is
-- walked.
weakenROut ::
  forall rs1 rs2 ci co.
  (WeakenR rs1) =>
  OutTerm rs2 ci co -> OutTerm (Append rs1 rs2) ci co
weakenROut (OPack ic wc fs) =
  OPack ic wc (weakenROutFields @rs1 @rs2 fs)

-- * weakenL-walking helpers (output-term variant) -------------------------

-- | Walk an 'OutFields' chain on a head-side register file and lift
-- every term across an rs2 suffix.
weakenLOutFields ::
  forall rs1 rs2 ci ifs fs.
  OutFields rs1 ci ifs fs -> OutFields (Append rs1 rs2) ci ifs fs
weakenLOutFields OFNil = OFNil
weakenLOutFields (OFCons t rest) =
  OFCons
    (weakenLTerm @rs1 @rs2 t)
    (weakenLOutFields @rs1 @rs2 rest)

-- | Walk an 'OutTerm' on a head-side register file and lift every
-- register read across an rs2 suffix.
weakenLOut ::
  forall rs1 rs2 ci co.
  OutTerm rs1 ci co -> OutTerm (Append rs1 rs2) ci co
weakenLOut (OPack ic wc fs) =
  OPack ic wc (weakenLOutFields @rs1 @rs2 fs)

-- * Substitution algorithm -------------------------------------------------

-- | The integer position of an 'Index' in its slot list.
-- (Local replica of 'Keiki.Core''s internal @indexInt@; not
-- exported there.)
indexInt :: Index rs r -> Int
indexInt ZIdx = 0
indexInt (SIdx i) = 1 + indexInt i

-- | Existential wrapper around a 'Term' so 'nthTerm' can return one
-- without exposing the field's type at the call site.
data SomeTerm rs ci where
  SomeTerm :: Term rs ci ifs r -> SomeTerm rs ci

-- | Walk an 'OutFields' chain to position @n@. Returns @Nothing@
-- when @n@ overshoots the chain (a bug in the caller; the design's
-- structural-alignment assumption guarantees @n@ is in range when
-- the constructor names match).
nthTerm :: Int -> OutFields rs ci ifs fs -> Maybe (SomeTerm rs ci)
nthTerm _ OFNil = Nothing
nthTerm 0 (OFCons t _) = Just (SomeTerm t)
nthTerm n (OFCons _ rest)
  | n > 0 = nthTerm (n - 1) rest
  | otherwise = Nothing

-- | Substitute a t2-side 'Term' against t1's edge output. See the
-- design note's "Substituting a Term" section for the rules.
--
-- The result reads from the appended register file
-- @Append rs1 rs2@: rs1 reads come from t1's of1 traversal (these
-- propagate t1's input @ci1@); rs2 reads come from t2's term
-- weakened across the rs1 prefix.
substTerm ::
  forall rs1 rs2 ci1 mid ifs2 ifsR r.
  (WeakenR rs1) =>
  Term rs2 mid ifs2 r ->
  OutTerm rs1 ci1 mid ->
  Term (Append rs1 rs2) ci1 ifsR r
substTerm (TLit r) _o1 = TLit r
substTerm (TReg ix2) _o1 = TReg (weakenR @rs1 ix2)
substTerm (TInpCtorField ic2 ix2) o1 =
  case o1 of
    OPack _ic1 wc1 of1
      | icName ic2 == wcName wc1 ->
          let n = indexInt ix2
           in case nthTerm n of1 of
                Just (SomeTerm tm) ->
                  -- tm :: Term rs1 ci1 ifsTm r' (r' ~ r and ifsTm ~ ifsR
                  -- structurally; the slot list of ic2 mirrors of1's tuple
                  -- shape via the GRecord/GTuple Generic derivations, and
                  -- of1's elements all read t1's input at the OPack's
                  -- schema). 'unsafeCoerceTerm' realigns both the result
                  -- type and the input field schema.
                  weakenLTerm @rs1 @rs2 (unsafeCoerceTerm tm)
                Nothing ->
                  error
                    ( "Keiki.Composition.compose: nthTerm overflow at\
                      \ position "
                        <> show n
                        <> " for InCtor "
                        <> icName ic2
                        <> " — t2 reads a field t1's OutFields doesn't expose.\
                           \ This indicates a structural mismatch between\
                           \ t1's wireCtor and t2's InCtor for the shared\
                           \ mid type."
                    )
      | otherwise ->
          error
            ( "Keiki.Composition.compose: TInpCtorField over "
                <> icName ic2
                <> " but t1's edge produced "
                <> wcName wc1
                <> " — caller should ensure structural alignment of mid's\
                   \ constructors. Substitution at this position is\
                   \ unsound; the composite edge guard's PInCtor\
                   \ substitution should make the edge unsatisfiable\
                   \ before evaluation reaches this term."
            )
substTerm (TApp1 f t) o1 = TApp1 f (substTerm @rs1 @rs2 t o1)
substTerm (TArith op a b) o1 =
  TArith op (substTerm @rs1 @rs2 a o1) (substTerm @rs1 @rs2 b o1)
substTerm (TApp2 f a b) o1 =
  TApp2
    f
    (substTerm @rs1 @rs2 a o1)
    (substTerm @rs1 @rs2 b o1)

-- | Existentially-coerce a 'Term''s result type /and/ input field
-- schema. Unsound in general; justified here by the structural-
-- alignment invariant the design note documents: when
-- @icName ic2 == wcName wc1@, the slot list of @ic2@ and the field
-- tuple of @wc1@ are derived from the same 'Generic' representation, so
-- positional reads agree on type; and the substituted term reads t1's
-- input at t1's 'OPack' schema, which is the schema the composite
-- 'OPack' is rebuilt at (see 'substOut').
unsafeCoerceTerm ::
  forall rs ci ifs ifs' r r'. Term rs ci ifs' r' -> Term rs ci ifs r
unsafeCoerceTerm = unsafeCoerce

-- | Substitute a t2-side 'HsPred' against t1's edge output. See
-- the design note's "Substituting an HsPred" section for the rules.
substPred ::
  forall rs1 rs2 ci1 mid.
  (WeakenR rs1) =>
  HsPred rs2 mid ->
  OutTerm rs1 ci1 mid ->
  HsPred (Append rs1 rs2) ci1
substPred PTop _o1 = PTop
substPred PBot _o1 = PBot
substPred (PAnd p q) o1 =
  PAnd
    (substPred @rs1 @rs2 p o1)
    (substPred @rs1 @rs2 q o1)
substPred (POr p q) o1 =
  POr
    (substPred @rs1 @rs2 p o1)
    (substPred @rs1 @rs2 q o1)
substPred (PNot p) o1 = PNot (substPred @rs1 @rs2 p o1)
substPred (PEq a b) o1 =
  PEq
    (substTerm @rs1 @rs2 a o1)
    (substTerm @rs1 @rs2 b o1)
substPred (PCmp op a b) o1 =
  PCmp
    op
    (substTerm @rs1 @rs2 a o1)
    (substTerm @rs1 @rs2 b o1)
substPred (PInCtor ic2) o1 =
  case o1 of
    OPack _ wc1 _
      | icName ic2 == wcName wc1 -> PTop
      | otherwise -> PBot

-- | Substitute a t2-side 'Update' against t1's edge output. The
-- slot-name index @w@ is preserved by substitution — substituting
-- input reads inside the right-hand-side 'Term's does not change
-- which slot names the update writes.
substUpdate ::
  forall rs1 rs2 w ci1 mid.
  (WeakenR rs1) =>
  Update rs2 w mid ->
  OutTerm rs1 ci1 mid ->
  Update (Append rs1 rs2) w ci1
substUpdate UKeep _o1 = UKeep
substUpdate (USet ix2 t) o1 =
  USet
    (weakenRIndexN @rs1 ix2)
    (substTerm @rs1 @rs2 t o1)
substUpdate (UCombine a b) o1 =
  UCombine
    (substUpdate @rs1 @rs2 a o1)
    (substUpdate @rs1 @rs2 b o1)

-- | Substitute a t2-side 'OutFields' chain against t1's edge output.
substOutFields ::
  forall rs1 rs2 ci1 mid ifs2 ifsR fs.
  (WeakenR rs1) =>
  OutFields rs2 mid ifs2 fs ->
  OutTerm rs1 ci1 mid ->
  OutFields (Append rs1 rs2) ci1 ifsR fs
substOutFields OFNil _o1 = OFNil
substOutFields (OFCons t rest) o1 =
  OFCons
    (substTerm @rs1 @rs2 t o1)
    (substOutFields @rs1 @rs2 rest o1)

-- | Substitute a t2-side 'OutTerm' against t1's edge output. The
-- composite's 'OPack' is tagged with t1's input constructor (the
-- @ic1@ from o1) — not t2's @ic2_co@. See the design note's
-- "Substituting an OutTerm" section.
substOut ::
  forall rs1 rs2 ci1 mid co.
  (WeakenR rs1) =>
  OutTerm rs2 mid co ->
  OutTerm rs1 ci1 mid ->
  OutTerm (Append rs1 rs2) ci1 co
substOut (OPack _ic2_co wc2_co of2) o1 =
  case o1 of
    OPack ic1 _wc1 _of1 ->
      OPack
        (unsafeCoerceInCtor ic1)
        wc2_co
        (substOutFields @rs1 @rs2 of2 o1)

-- | Coerce an 'InCtor''s @ci@ type. Unsound in general; the
-- composite uses ic1 (originally over @ci1@) and the type already
-- aligns — the call site is a structural identity. We use coerce
-- here only because the @InCtor@ shape doesn't admit a phantom
-- @ci@ tag we could thread through; this is a one-line escape
-- to keep the substitution writable. The runtime behaviour is
-- correct: ic1's icMatch / icBuild are exactly what 'solveOutput'
-- on the composite needs.
unsafeCoerceInCtor :: InCtor ci ifs -> InCtor ci' ifs
unsafeCoerceInCtor = unsafeCoerce

-- * Either lifters (alternative-side) -------------------------------------

-- | Lift an 'InCtor' from the left arm of an 'Either' input alphabet.
-- The resulting 'InCtor' matches only on @Left _@ inputs and
-- preserves the underlying constructor's slot list and round-trip;
-- 'icBuild' wraps the rebuilt @ci1@ in 'Left' so the lifted
-- transducer's 'solveOutput' walks back to the original input form.
leftInCtor :: InCtor ci1 ifs -> InCtor (Either ci1 ci2) ifs
leftInCtor InCtor {icName = n, icMatch = m, icBuild = b} =
  InCtor
    { icName = n,
      icMatch = \case
        Left c1 -> m c1
        Right _ -> Nothing,
      icBuild = Left . b
    }

-- | Lift an 'InCtor' from the right arm of an 'Either' input
-- alphabet. Symmetric to 'leftInCtor'.
rightInCtor :: InCtor ci2 ifs -> InCtor (Either ci1 ci2) ifs
rightInCtor InCtor {icName = n, icMatch = m, icBuild = b} =
  InCtor
    { icName = n,
      icMatch = \case
        Left _ -> Nothing
        Right c2 -> m c2,
      icBuild = Right . b
    }

-- | Lift a 'WireCtor' from the left arm of an 'Either' output
-- alphabet. Matches only on @Left _@ outputs; rebuilds via
-- @Left . wcBuild@.
leftWireCtor :: WireCtor co1 fs -> WireCtor (Either co1 co2) fs
leftWireCtor WireCtor {wcName = n, wcMatch = m, wcBuild = b} =
  WireCtor
    { wcName = n,
      wcMatch = \case
        Left c1 -> m c1
        Right _ -> Nothing,
      wcBuild = Left . b
    }

-- | Lift a 'WireCtor' from the right arm of an 'Either' output
-- alphabet. Symmetric to 'leftWireCtor'.
rightWireCtor :: WireCtor co2 fs -> WireCtor (Either co1 co2) fs
rightWireCtor WireCtor {wcName = n, wcMatch = m, wcBuild = b} =
  WireCtor
    { wcName = n,
      wcMatch = \case
        Left _ -> Nothing
        Right c2 -> m c2,
      wcBuild = Right . b
    }

-- | Lift a 'Term' from the left side's input alphabet to
-- @Either ci1 ci2@. Walks the AST and adjusts every 'TInpCtorField'
-- to read through 'leftInCtor'. 'TLit' / 'TReg' don't depend on
-- @ci@ and pass through unchanged.
liftLTermAlt ::
  forall rs ci1 ci2 ifs r.
  Term rs ci1 ifs r -> Term rs (Either ci1 ci2) ifs r
liftLTermAlt (TLit r) = TLit r
liftLTermAlt (TReg ix) = TReg ix
liftLTermAlt (TInpCtorField ic ix) = TInpCtorField (leftInCtor ic) ix
liftLTermAlt (TApp1 f t) = TApp1 f (liftLTermAlt @rs @ci1 @ci2 t)
liftLTermAlt (TArith op a b) =
  TArith op (liftLTermAlt @rs @ci1 @ci2 a) (liftLTermAlt @rs @ci1 @ci2 b)
liftLTermAlt (TApp2 f a b) =
  TApp2 f (liftLTermAlt @rs @ci1 @ci2 a) (liftLTermAlt @rs @ci1 @ci2 b)

-- | Lift a 'Term' from the right side's input alphabet to
-- @Either ci1 ci2@. Symmetric to 'liftLTermAlt'.
liftRTermAlt ::
  forall rs ci1 ci2 ifs r.
  Term rs ci2 ifs r -> Term rs (Either ci1 ci2) ifs r
liftRTermAlt (TLit r) = TLit r
liftRTermAlt (TReg ix) = TReg ix
liftRTermAlt (TInpCtorField ic ix) = TInpCtorField (rightInCtor ic) ix
liftRTermAlt (TApp1 f t) = TApp1 f (liftRTermAlt @rs @ci1 @ci2 t)
liftRTermAlt (TArith op a b) =
  TArith op (liftRTermAlt @rs @ci1 @ci2 a) (liftRTermAlt @rs @ci1 @ci2 b)
liftRTermAlt (TApp2 f a b) =
  TApp2 f (liftRTermAlt @rs @ci1 @ci2 a) (liftRTermAlt @rs @ci1 @ci2 b)

-- | Lift an 'HsPred' from the left side's input alphabet to
-- @Either ci1 ci2@. Walks the AST and recurses through every
-- 'Term' via 'liftLTermAlt'.
liftLPredAlt ::
  forall rs ci1 ci2.
  HsPred rs ci1 -> HsPred rs (Either ci1 ci2)
liftLPredAlt PTop = PTop
liftLPredAlt PBot = PBot
liftLPredAlt (PAnd p q) =
  PAnd
    (liftLPredAlt @rs @ci1 @ci2 p)
    (liftLPredAlt @rs @ci1 @ci2 q)
liftLPredAlt (POr p q) =
  POr
    (liftLPredAlt @rs @ci1 @ci2 p)
    (liftLPredAlt @rs @ci1 @ci2 q)
liftLPredAlt (PNot p) = PNot (liftLPredAlt @rs @ci1 @ci2 p)
liftLPredAlt (PEq a b) =
  PEq
    (liftLTermAlt @rs @ci1 @ci2 a)
    (liftLTermAlt @rs @ci1 @ci2 b)
liftLPredAlt (PInCtor ic) = PInCtor (leftInCtor ic)
liftLPredAlt (PCmp op a b) =
  PCmp
    op
    (liftLTermAlt @rs @ci1 @ci2 a)
    (liftLTermAlt @rs @ci1 @ci2 b)

-- | Lift an 'HsPred' from the right side's input alphabet to
-- @Either ci1 ci2@. Symmetric to 'liftLPredAlt'.
liftRPredAlt ::
  forall rs ci1 ci2.
  HsPred rs ci2 -> HsPred rs (Either ci1 ci2)
liftRPredAlt PTop = PTop
liftRPredAlt PBot = PBot
liftRPredAlt (PAnd p q) =
  PAnd
    (liftRPredAlt @rs @ci1 @ci2 p)
    (liftRPredAlt @rs @ci1 @ci2 q)
liftRPredAlt (POr p q) =
  POr
    (liftRPredAlt @rs @ci1 @ci2 p)
    (liftRPredAlt @rs @ci1 @ci2 q)
liftRPredAlt (PNot p) = PNot (liftRPredAlt @rs @ci1 @ci2 p)
liftRPredAlt (PEq a b) =
  PEq
    (liftRTermAlt @rs @ci1 @ci2 a)
    (liftRTermAlt @rs @ci1 @ci2 b)
liftRPredAlt (PInCtor ic) = PInCtor (rightInCtor ic)
liftRPredAlt (PCmp op a b) =
  PCmp
    op
    (liftRTermAlt @rs @ci1 @ci2 a)
    (liftRTermAlt @rs @ci1 @ci2 b)

-- | Lift an 'Update' from the left side's input alphabet to
-- @Either ci1 ci2@. The slot-name index @w@ is preserved; only the
-- right-hand-side 'Term's are walked.
liftLUpdateAlt ::
  forall rs w ci1 ci2.
  Update rs w ci1 -> Update rs w (Either ci1 ci2)
liftLUpdateAlt UKeep = UKeep
liftLUpdateAlt (USet ix t) = USet ix (liftLTermAlt @rs @ci1 @ci2 t)
liftLUpdateAlt (UCombine a b) = UCombine (liftLUpdateAlt a) (liftLUpdateAlt b)

-- | Lift an 'Update' from the right side's input alphabet to
-- @Either ci1 ci2@. Symmetric to 'liftLUpdateAlt'.
liftRUpdateAlt ::
  forall rs w ci1 ci2.
  Update rs w ci2 -> Update rs w (Either ci1 ci2)
liftRUpdateAlt UKeep = UKeep
liftRUpdateAlt (USet ix t) = USet ix (liftRTermAlt @rs @ci1 @ci2 t)
liftRUpdateAlt (UCombine a b) = UCombine (liftRUpdateAlt a) (liftRUpdateAlt b)

-- | Lift an 'OutFields' chain from the left side's input alphabet to
-- @Either ci1 ci2@. Recurses on each 'Term' via 'liftLTermAlt'.
liftLOutFieldsAlt ::
  forall rs ci1 ci2 ifs fs.
  OutFields rs ci1 ifs fs -> OutFields rs (Either ci1 ci2) ifs fs
liftLOutFieldsAlt OFNil = OFNil
liftLOutFieldsAlt (OFCons t rest) =
  OFCons
    (liftLTermAlt @rs @ci1 @ci2 t)
    (liftLOutFieldsAlt @rs @ci1 @ci2 rest)

-- | Lift an 'OutFields' chain from the right side's input alphabet
-- to @Either ci1 ci2@. Symmetric to 'liftLOutFieldsAlt'.
liftROutFieldsAlt ::
  forall rs ci1 ci2 ifs fs.
  OutFields rs ci2 ifs fs -> OutFields rs (Either ci1 ci2) ifs fs
liftROutFieldsAlt OFNil = OFNil
liftROutFieldsAlt (OFCons t rest) =
  OFCons
    (liftRTermAlt @rs @ci1 @ci2 t)
    (liftROutFieldsAlt @rs @ci1 @ci2 rest)

-- | Lift an 'OutTerm' from the left side's alphabets to
-- @Either ci1 ci2@ on the input and @Either co1 co2@ on the output.
-- The 'OPack' is re-tagged: the 'InCtor' becomes 'leftInCtor', the
-- 'WireCtor' becomes 'leftWireCtor', and every 'Term' inside the
-- 'OutFields' is lifted via 'liftLTermAlt'.
liftLOutAlt ::
  forall rs ci1 ci2 co1 co2.
  OutTerm rs ci1 co1 ->
  OutTerm rs (Either ci1 ci2) (Either co1 co2)
liftLOutAlt (OPack ic wc fs) =
  OPack
    (leftInCtor ic)
    (leftWireCtor wc)
    (liftLOutFieldsAlt @rs @ci1 @ci2 fs)

-- | Lift an 'OutTerm' from the right side's alphabets to
-- @Either ci1 ci2@ on the input and @Either co1 co2@ on the output.
-- Symmetric to 'liftLOutAlt'.
liftROutAlt ::
  forall rs ci1 ci2 co1 co2.
  OutTerm rs ci2 co2 ->
  OutTerm rs (Either ci1 ci2) (Either co1 co2)
liftROutAlt (OPack ic wc fs) =
  OPack
    (rightInCtor ic)
    (rightWireCtor wc)
    (liftROutFieldsAlt @rs @ci1 @ci2 fs)

-- * N-ary coproduct injectors (EP-48) ------------------------------------

-- $naryInjectors
--
-- These inject one already-derived event family into a sum of /three/
-- families, represented as the right-nested @'Either' co1 ('Either' co2
-- co3)@ on the output side (and the analogous nest on the input side).
-- They are nothing more than the shipped binary lifts
-- ('leftWireCtor'\/'rightWireCtor', 'leftInCtor'\/'rightInCtor',
-- 'liftLOutAlt'\/'liftROutAlt') composed the right number of times, so
-- no new machinery — and no new @unsafeCoerce@ — is introduced.
--
-- == Beyond three families
--
-- The pattern generalizes to any arity by composing one more @right…@
-- per extra family. For a right-nested sum of @N@ families, family @k@
-- injects via @right…@ applied @k-1@ times then @left…@ once, and the
-- /last/ family @N@ via @right…@ applied @N-1@ times (no trailing
-- @left…@, since the innermost arm is the bare family type). The
-- arity-3 helpers below are the worked common case; for larger @N@,
-- compose 'leftWireCtor'\/'rightWireCtor' (etc.) directly.
--
-- == Name-uniqueness obligation
--
-- 'Keiki.Core.solveOutput' matches input constructors by @icName@
-- /string equality/ (and groups outputs by @wcName@). When several
-- families are summed into one alphabet, their constructor-name strings
-- must be pairwise distinct, or inversion can silently recover the wrong
-- command. The 'Either' wrapper keeps families structurally apart at the
-- match step, but the names are the human-facing contract — keep them
-- unique across summed families.

-- | Inject a family-1 'WireCtor' into a 3-family output sum
-- @'Either' co1 ('Either' co2 co3)@.
wireCtor3At1 :: WireCtor co1 fs -> WireCtor (Either co1 (Either co2 co3)) fs
wireCtor3At1 = leftWireCtor

-- | Inject a family-2 'WireCtor' into a 3-family output sum.
wireCtor3At2 :: WireCtor co2 fs -> WireCtor (Either co1 (Either co2 co3)) fs
wireCtor3At2 = rightWireCtor . leftWireCtor

-- | Inject a family-3 (last) 'WireCtor' into a 3-family output sum.
wireCtor3At3 :: WireCtor co3 fs -> WireCtor (Either co1 (Either co2 co3)) fs
wireCtor3At3 = rightWireCtor . rightWireCtor

-- | Inject a family-1 'InCtor' into a 3-family input sum
-- @'Either' ci1 ('Either' ci2 ci3)@.
inCtor3At1 :: InCtor ci1 ifs -> InCtor (Either ci1 (Either ci2 ci3)) ifs
inCtor3At1 = leftInCtor

-- | Inject a family-2 'InCtor' into a 3-family input sum.
inCtor3At2 :: InCtor ci2 ifs -> InCtor (Either ci1 (Either ci2 ci3)) ifs
inCtor3At2 = rightInCtor . leftInCtor

-- | Inject a family-3 (last) 'InCtor' into a 3-family input sum.
inCtor3At3 :: InCtor ci3 ifs -> InCtor (Either ci1 (Either ci2 ci3)) ifs
inCtor3At3 = rightInCtor . rightInCtor

-- | Re-home a whole family-1 edge output term into the 3-family
-- input/output sums. This is the function that lets an edge authored
-- against family 1 participate in a transducer over the summed alphabet;
-- 'Keiki.Core.solveOutput' inverts the summed event straight back to the
-- (injected) command.
outTerm3At1 ::
  OutTerm rs ci1 co1 ->
  OutTerm rs (Either ci1 (Either ci2 ci3)) (Either co1 (Either co2 co3))
outTerm3At1 = liftLOutAlt

-- | Re-home a whole family-2 edge output term into the 3-family sums.
outTerm3At2 ::
  OutTerm rs ci2 co2 ->
  OutTerm rs (Either ci1 (Either ci2 ci3)) (Either co1 (Either co2 co3))
outTerm3At2 = liftROutAlt . liftLOutAlt

-- | Re-home a whole family-3 (last) edge output term into the 3-family sums.
outTerm3At3 ::
  OutTerm rs ci3 co3 ->
  OutTerm rs (Either ci1 (Either ci2 ci3)) (Either co1 (Either co2 co3))
outTerm3At3 = liftROutAlt . liftROutAlt

-- * Multi-event composition (EP-19 M6) -----------------------------------

-- | A symbolic write performed by an earlier t2 step in a multi-event
-- composition path. The value term has already been substituted into the
-- composite register/input domain. Its input-field schema is existential
-- because updates never expose that schema.
data PendingWrite rs ci where
  PendingWrite ::
    (KnownSymbol s) =>
    IndexN s rs r ->
    Term rs ci ifs r ->
    PendingWrite rs ci

-- | Compare a slot-name-tagged update index with a positional register
-- index. Equal positions refine the stored value types to equality.
matchIndex :: IndexN s rs a -> Index rs b -> Maybe (a :~: b)
matchIndex IZ ZIdx = Just Refl
matchIndex (IS i) (SIdx j) = matchIndex i j
matchIndex _ _ = Nothing

-- | Look up the most recent symbolic write to a register. The environment
-- is newest-first; 'unsafeCoerceTerm' only realigns the existential input
-- field schema, under the same justification used by 'substTerm'.
lookupPending ::
  Index rs r ->
  [PendingWrite rs ci] ->
  Maybe (Term rs ci ifs r)
lookupPending _ [] = Nothing
lookupPending ix (PendingWrite pendingIx pendingTerm : rest) =
  case matchIndex pendingIx ix of
    Just Refl -> Just (unsafeCoerceTerm pendingTerm)
    Nothing -> lookupPending ix rest

-- | Inline earlier t2 writes so a later chain step observes the symbolic
-- register state that sequential execution would have produced.
applyEnvTerm ::
  [PendingWrite rs ci] ->
  Term rs ci ifs r ->
  Term rs ci ifs r
applyEnvTerm _ (TLit r) = TLit r
applyEnvTerm env (TReg ix) = maybe (TReg ix) id (lookupPending ix env)
applyEnvTerm _ (TInpCtorField ic ix) = TInpCtorField ic ix
applyEnvTerm env (TApp1 f term) = TApp1 f (applyEnvTerm env term)
applyEnvTerm env (TArith op a b) =
  TArith op (applyEnvTerm env a) (applyEnvTerm env b)
applyEnvTerm env (TApp2 f a b) =
  TApp2 f (applyEnvTerm env a) (applyEnvTerm env b)

applyEnvPred ::
  [PendingWrite rs ci] ->
  HsPred rs ci ->
  HsPred rs ci
applyEnvPred _ PTop = PTop
applyEnvPred _ PBot = PBot
applyEnvPred env (PAnd a b) = PAnd (applyEnvPred env a) (applyEnvPred env b)
applyEnvPred env (POr a b) = POr (applyEnvPred env a) (applyEnvPred env b)
applyEnvPred env (PNot pred') = PNot (applyEnvPred env pred')
applyEnvPred env (PEq a b) = PEq (applyEnvTerm env a) (applyEnvTerm env b)
applyEnvPred env (PCmp op a b) =
  PCmp op (applyEnvTerm env a) (applyEnvTerm env b)
applyEnvPred _ (PInCtor ic) = PInCtor ic

applyEnvUpdate ::
  [PendingWrite rs ci] ->
  Update rs w ci ->
  Update rs w ci
applyEnvUpdate _ UKeep = UKeep
applyEnvUpdate env (USet ix term) = USet ix (applyEnvTerm env term)
applyEnvUpdate env (UCombine a b) =
  UCombine (applyEnvUpdate env a) (applyEnvUpdate env b)

applyEnvOutFields ::
  [PendingWrite rs ci] ->
  OutFields rs ci ifs fs ->
  OutFields rs ci ifs fs
applyEnvOutFields _ OFNil = OFNil
applyEnvOutFields env (OFCons term rest) =
  OFCons (applyEnvTerm env term) (applyEnvOutFields env rest)

applyEnvOut ::
  [PendingWrite rs ci] ->
  OutTerm rs ci co ->
  OutTerm rs ci co
applyEnvOut env (OPack ic wc fields) =
  OPack ic wc (applyEnvOutFields env fields)

-- | Collect one t2 step's writes newest-first. The right half is collected
-- before the left so an internal raw 'UCombine' that repeats a slot matches
-- 'runUpdate''s rightmost-write-wins application order.
pendingWrites :: Update rs w ci -> [PendingWrite rs ci]
pendingWrites UKeep = []
pendingWrites (USet ix term) = [PendingWrite ix term]
pendingWrites (UCombine a b) = pendingWrites b ++ pendingWrites a

-- | An in-progress t2-edge path through a multi-event 'compose'
-- expansion. Carries the accumulated guard (the lifted @e1@-guard
-- conjoined with each consumed t2-edge's substituted guard), the
-- chained update, the concatenation of t2-edge outputs (each
-- substituted against the corresponding mid-symbol), and the t2-
-- state after consuming all mid-symbols processed so far.
--
-- The existential @w@ closes over the chained 'Update''s slot-set
-- index — each step extends the chain via 'UCombine', so the
-- effective @w@ grows but is hidden from the surrounding code.
data PartialPath rs1 rs2 ci1 co s2
  = forall w.
    PartialPath
      !(HsPred (Append rs1 rs2) ci1) -- accumulated guard
      !(Update (Append rs1 rs2) w ci1) -- chained update (existential w)
      ![OutTerm (Append rs1 rs2) ci1 co] -- accumulated outputs in order
      ![PendingWrite (Append rs1 rs2) ci1] -- earlier t2 writes, newest first
      !s2 -- t2-state after consuming so far

-- * compose ----------------------------------------------------------------

-- | Sequential composition of two 'SymTransducer's. The composite
-- consumes t1's input alphabet and produces t2's output alphabet,
-- threading t1's events through t2 transparently.
--
-- Semantics (see the design note for the full case analysis):
--
--   * For each ε-edge of t1 from @s1@: one composite edge that
--     advances @s1@ and leaves @s2@ unchanged.
--   * For each non-ε edge of t1 from @s1@, paired with each edge of
--     t2 from @s2@: one composite edge whose guard / update /
--     output are t2's structurally substituted against t1's edge
--     output, conjoined with t1's lifted guard / update.
--
-- The composite preserves the keiki guarantees:
--   * Mechanical inversion: 'solveOutput' on the composite
--     'OPack' walks t2's wire form back through t1's structural
--     reads, recovering @ci1@.
--   * Hidden-input check: 'checkHiddenInputs' surfaces
--     transitively-hidden fields (a field of @ci1@ that t1 keeps
--     in @mid@ but t2 drops on the wire is flagged at the
--     composite level).
--   * Symbolic single-valuedness: the composite is single-valued
--     when t1 and t2 are individually single-valued; the
--     substitution is a syntactic rewrite that preserves
--     unsatisfiability.
--
-- See the design note for the proofs / case analyses.
compose ::
  forall rs1 rs2 s1 s2 ci1 mid co.
  ( WeakenR rs1,
    Disjoint (Names rs1) (Names rs2)
  ) =>
  SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 mid ->
  SymTransducer (HsPred rs2 mid) rs2 s2 mid co ->
  SymTransducer
    (HsPred (Append rs1 rs2) ci1)
    (Append rs1 rs2)
    (Composite s1 s2)
    ci1
    co
compose t1 t2 =
  SymTransducer
    { edgesOut = composedEdges,
      initial = Composite (initial t1) (initial t2),
      initialRegs = appendRegFile (initialRegs t1) (initialRegs t2),
      isFinal = \(Composite a b) -> isFinal t1 a && isFinal t2 b
    }
  where
    composedEdges ::
      Composite s1 s2 ->
      [ Edge
          (HsPred (Append rs1 rs2) ci1)
          (Append rs1 rs2)
          ci1
          co
          (Composite s1 s2)
      ]
    composedEdges (Composite s1 s2) =
      concatMap (composeEdge s1 s2) (edgesOut t1 s1)

    composeEdge ::
      s1 ->
      s2 ->
      Edge (HsPred rs1 ci1) rs1 ci1 mid s1 ->
      [ Edge
          (HsPred (Append rs1 rs2) ci1)
          (Append rs1 rs2)
          ci1
          co
          (Composite s1 s2)
      ]
    composeEdge _s1Source s2 e1 = case output e1 of
      [] -> [epsilonEdge e1 s2]
      [o1] -> map (productEdge e1 o1) (edgesOut t2 s2)
      mids ->
        -- EP-19 M6 library-side chain expansion: walk t2 through the
        -- N mid-symbols of e1's output list, gathering all paths
        -- (cartesian product of t2 edges per intermediate state).
        -- Each completed path becomes one length-N composite edge.
        -- See docs/research/gsm-widening-design.md §5.
        map (finalizePath e1) (expandPaths mids (initialPath e1 s2))

    epsilonEdge ::
      Edge (HsPred rs1 ci1) rs1 ci1 mid s1 ->
      s2 ->
      Edge
        (HsPred (Append rs1 rs2) ci1)
        (Append rs1 rs2)
        ci1
        co
        (Composite s1 s2)
    epsilonEdge e1 s2 = case e1 of
      Edge {update = u1} ->
        Edge
          { guard = weakenLPred @rs1 @rs2 (guard e1),
            update = weakenLUpdate @rs1 @rs2 u1,
            output = [],
            target = Composite (target e1) s2
          }

    productEdge ::
      Edge (HsPred rs1 ci1) rs1 ci1 mid s1 ->
      OutTerm rs1 ci1 mid ->
      Edge (HsPred rs2 mid) rs2 mid co s2 ->
      Edge
        (HsPred (Append rs1 rs2) ci1)
        (Append rs1 rs2)
        ci1
        co
        (Composite s1 s2)
    productEdge e1 o1 e2 = case (e1, e2) of
      -- Pattern-match brings each Edge's existential @w1@ / @w2@ into
      -- scope so that 'weakenLUpdate' / 'substUpdate' can pin their
      -- result types to the inputs' indices. The composite @w@
      -- becomes 'Concat w1 w2'; we use the raw 'UCombine' constructor
      -- (no 'Disjoint' constraint) because the structural
      -- disjointness here — left writes only into the rs1 prefix,
      -- right writes only into the rs2 suffix — cannot be promoted
      -- to a type-level constraint without carrying a @Subset w
      -- (Names rs)@ witness through 'Edge'\'s existential and a
      -- hand-written lemma function. External aggregate authors
      -- still get the static 'Disjoint' check via 'combine'; this
      -- internal call site is the documented exception. See EP-18's
      -- Decision Log entry dated 2026-05-02.
      (Edge {update = u1}, Edge {update = u2}) ->
        Edge
          { guard =
              PAnd
                (weakenLPred @rs1 @rs2 (guard e1))
                (substPred @rs1 @rs2 (guard e2) o1),
            update =
              UCombine
                (weakenLUpdate @rs1 @rs2 u1)
                (substUpdate @rs1 @rs2 u2 o1),
            output = map (\o2 -> substOut @rs1 @rs2 o2 o1) (output e2),
            target = Composite (target e1) (target e2)
          }

    -- \| The starting point for EP-19 M6's chain expansion. Carries
    -- t1's edge contribution (lifted guard, lifted update) into the
    -- accumulator; the recursion threads through it without re-
    -- referencing t1.
    initialPath ::
      Edge (HsPred rs1 ci1) rs1 ci1 mid s1 ->
      s2 ->
      PartialPath rs1 rs2 ci1 co s2
    initialPath e1 s2 = case e1 of
      Edge {update = u1} ->
        PartialPath
          (weakenLPred @rs1 @rs2 (guard e1))
          (weakenLUpdate @rs1 @rs2 u1)
          []
          []
          s2

    -- \| Enumerate all t2-edge paths that consume the supplied
    -- mid-symbol list in order, starting from the path's current
    -- t2-state. Each completed path's @ppEnd@ is the t2-state after
    -- the final mid-symbol; its @ppOutputs@ is the concatenation of
    -- t2-edge outputs (each substituted against the corresponding
    -- mid-symbol of t1's edge), in declaration order.
    --
    -- The base case (empty mid-symbol list) returns the path as-is —
    -- the recursion has consumed every mid-symbol.
    expandPaths ::
      [OutTerm rs1 ci1 mid] ->
      PartialPath rs1 rs2 ci1 co s2 ->
      [PartialPath rs1 rs2 ci1 co s2]
    expandPaths [] path = [path]
    expandPaths (o : rest) path =
      case path of
        PartialPath g u outs env s2 ->
          concatMap
            (\e2 -> expandPaths rest (stepPath g u outs env o s2 e2))
            (edgesOut t2 s2)

    -- \| Extend a path by one t2-edge consuming one mid-symbol.
    -- Pattern-matching @e2@ brings the edge's existential @w2@ into
    -- scope so the @UCombine@ can chain into the accumulator. The
    -- accumulator's existential @w@ comes from 'PartialPath'.
    stepPath ::
      forall w.
      HsPred (Append rs1 rs2) ci1 ->
      Update (Append rs1 rs2) w ci1 ->
      [OutTerm (Append rs1 rs2) ci1 co] ->
      [PendingWrite (Append rs1 rs2) ci1] ->
      OutTerm rs1 ci1 mid ->
      s2 ->
      Edge (HsPred rs2 mid) rs2 mid co s2 ->
      PartialPath rs1 rs2 ci1 co s2
    stepPath g u outs env o _s2 e2 = case e2 of
      Edge {update = u2} ->
        let stepGuard =
              applyEnvPred env (substPred @rs1 @rs2 (guard e2) o)
            stepUpdate =
              applyEnvUpdate env (substUpdate @rs1 @rs2 u2 o)
            stepOutputs =
              map
                (applyEnvOut env . (\o2 -> substOut @rs1 @rs2 o2 o))
                (output e2)
            nextEnv = pendingWrites stepUpdate ++ env
         in PartialPath
              (PAnd g stepGuard)
              (UCombine u stepUpdate)
              (outs ++ stepOutputs)
              nextEnv
              (target e2)

    -- \| Convert a fully-expanded path to a composite edge by
    -- borrowing t1's @target@ for the composite's target.
    finalizePath ::
      Edge (HsPred rs1 ci1) rs1 ci1 mid s1 ->
      PartialPath rs1 rs2 ci1 co s2 ->
      Edge
        (HsPred (Append rs1 rs2) ci1)
        (Append rs1 rs2)
        ci1
        co
        (Composite s1 s2)
    finalizePath e1 (PartialPath g u outs _env s2End) =
      Edge
        { guard = g,
          update = u,
          output = outs,
          target = Composite (target e1) s2End
        }

-- * alternative -----------------------------------------------------------

-- | Disjoint-input dispatch of two 'SymTransducer's. The composite
-- consumes @Either ci1 ci2@ and emits @Either co1 co2@: a @Left ci1@
-- advances @t1@ from its current sub-vertex (leaving t2's
-- sub-vertex unchanged) and emits @Left co1@; a @Right ci2@
-- advances @t2@ from its current sub-vertex (leaving t1's
-- sub-vertex unchanged) and emits @Right co2@. The two
-- sub-aggregates have **independent state** that evolves in
-- parallel as commands arrive for the appropriate arm.
--
-- Semantics:
--
--   * The composite vertex is 'Composite' s1 s2 (the same product
--     vertex 'compose' uses). At each composite vertex
--     @Composite s1 s2@, the outgoing edges are the union of:
--       - t1's edges from @s1@, lifted into the @Either ci1 ci2@
--         input alphabet (gated to fire only on @Left _@) with
--         target @Composite (target e1) s2@;
--       - t2's edges from @s2@, lifted symmetrically with target
--         @Composite s1 (target e2)@.
--   * Initial state is @Composite (initial t1) (initial t2)@.
--   * @isFinal@ requires both sub-aggregates to be final.
--
-- The composite preserves the keiki guarantees:
--
--   * Mechanical inversion: each composite output @OPack (leftInCtor
--     ic) (leftWireCtor wc) of_lifted@ runs the underlying
--     @icMatch@ / @icBuild@ unchanged after stripping the @Left@
--     wrapping; symmetric for @Right@.
--   * Hidden-input check: each side's per-edge check inherits via
--     the lifters (which preserve 'TInpCtorField' slot reads).
--   * Symbolic single-valuedness: at any @Composite s1 s2@, the t1
--     edges' guards (which require @Left _@ via 'leftInCtor') and
--     t2 edges' guards (which require @Right _@ via 'rightInCtor')
--     are pairwise mutually exclusive. Within each arm,
--     single-valuedness reduces to the underlying sub-aggregate's
--     check at the relevant sub-vertex. **No cross-transducer
--     mutual-exclusion check is needed** — the @Either@ arms make
--     it vacuous.
--
-- See 'docs/research/composition-combinators-design.md' under
-- "Combinators beyond `compose`" → "`alternative` — admitted" for
-- the full design record (signature, semantics, single-step
-- example, preservation arguments, limitations).
alternative ::
  forall rs1 rs2 s1 s2 ci1 ci2 co1 co2.
  ( WeakenR rs1,
    Disjoint (Names rs1) (Names rs2)
  ) =>
  SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 co1 ->
  SymTransducer (HsPred rs2 ci2) rs2 s2 ci2 co2 ->
  SymTransducer
    (HsPred (Append rs1 rs2) (Either ci1 ci2))
    (Append rs1 rs2)
    (Composite s1 s2)
    (Either ci1 ci2)
    (Either co1 co2)
alternative t1 t2 =
  SymTransducer
    { edgesOut = altEdges,
      initial = Composite (initial t1) (initial t2),
      initialRegs = appendRegFile (initialRegs t1) (initialRegs t2),
      isFinal = \(Composite s1 s2) -> isFinal t1 s1 && isFinal t2 s2
    }
  where
    altEdges ::
      Composite s1 s2 ->
      [ Edge
          (HsPred (Append rs1 rs2) (Either ci1 ci2))
          (Append rs1 rs2)
          (Either ci1 ci2)
          (Either co1 co2)
          (Composite s1 s2)
      ]
    altEdges (Composite s1 s2) =
      map (liftEdgeL s2) (edgesOut t1 s1)
        ++ map (liftEdgeR s1) (edgesOut t2 s2)

    liftEdgeL ::
      s2 ->
      Edge (HsPred rs1 ci1) rs1 ci1 co1 s1 ->
      Edge
        (HsPred (Append rs1 rs2) (Either ci1 ci2))
        (Append rs1 rs2)
        (Either ci1 ci2)
        (Either co1 co2)
        (Composite s1 s2)
    liftEdgeL s2 e1 = case e1 of
      Edge {update = u1} ->
        Edge
          { guard =
              liftLPredAlt @(Append rs1 rs2) @ci1 @ci2
                (weakenLPred @rs1 @rs2 (guard e1)),
            update =
              liftLUpdateAlt @(Append rs1 rs2) @_ @ci1 @ci2
                (weakenLUpdate @rs1 @rs2 u1),
            output =
              map
                ( liftLOutAlt @(Append rs1 rs2) @ci1 @ci2 @co1 @co2
                    . weakenLOut @rs1 @rs2
                )
                (output e1),
            target = Composite (target e1) s2
          }

    liftEdgeR ::
      s1 ->
      Edge (HsPred rs2 ci2) rs2 ci2 co2 s2 ->
      Edge
        (HsPred (Append rs1 rs2) (Either ci1 ci2))
        (Append rs1 rs2)
        (Either ci1 ci2)
        (Either co1 co2)
        (Composite s1 s2)
    liftEdgeR s1 e2 = case e2 of
      Edge {update = u2} ->
        Edge
          { guard =
              liftRPredAlt @(Append rs1 rs2) @ci1 @ci2
                (weakenRPred @rs1 @rs2 (guard e2)),
            update =
              liftRUpdateAlt @(Append rs1 rs2) @_ @ci1 @ci2
                (weakenRUpdate @rs1 @rs2 u2),
            output =
              map
                ( liftROutAlt @(Append rs1 rs2) @ci1 @ci2 @co1 @co2
                    . weakenROut @rs1 @rs2
                )
                (output e2),
            target = Composite s1 (target e2)
          }

-- * feedback1 ------------------------------------------------------------

-- | Single-step feedback combinator. Models one round of an
-- aggregate ↔ stateless-policy reaction: the aggregate consumes an
-- external command, the policy observes the aggregate's emitted
-- event and emits a follow-up command, and the aggregate consumes
-- that follow-up. The composite emits the aggregate's *second*
-- event as its output.
--
-- Operationally, @feedback1 t f = compose t (compose f t)@:
--
--   * The inner @compose f t@ chains the policy's output (a
--     command for t) into a second invocation of t.
--   * The outer @compose t _@ feeds t's first event into that
--     inner pipeline.
--
-- The composite vertex is @Composite s1 (Composite s2 s1)@ —
-- "outer t state, then (policy state, inner t state)". Even though
-- the inner @s1@ is the same Haskell type as the outer, it occupies
-- a distinct dimension of the composite vertex tuple, so
-- 'Keiki.Symbolic.isSingleValuedSym''s per-vertex enumeration walks
-- all @|s1| * |s2| * |s1|@ combinations independently.
--
-- Multi-round patterns are expressed by nesting:
--
--     twoRounds = feedback1 (feedback1 t f) f
--
-- The pure-core boundary holds because there is no loop — the
-- cascade runs exactly once per external command.
--
-- == Constraints and limitations
--
-- The constraint @'Disjoint' ('Names' rs1) ('Names' ('Append' rs2 rs1))@
-- is the outer 'compose''s slot-disjointness check applied to
-- @rs1@ versus @Append rs2 rs1@. Since @rs1@ appears on both sides,
-- the constraint is only satisfiable when @rs1 = '[]@ — i.e. when
-- t is **stateless** (its register file is empty). For non-empty
-- @rs1@, the call site fails with a slot-collision @TypeError@.
--
-- This restriction follows from the design's
-- "two-stacked-@compose@" reduction: t appears twice, and keiki's
-- register-file model gives each appearance its own copy of @rs1@.
-- A "shared-state" variant — where the second t reads/writes the
-- first t's registers via a custom edge construction — is
-- documented as a future extension and is not in scope for MP-8.
-- The "stateless policy" recommendation (single vertex, empty
-- @rs2@) is convention rather than enforced; if violated, the
-- composite still typechecks but the single-step semantics may
-- not be preserved.
--
-- == Future extensions
--
-- A bounded-step variant @feedbackN n t f@ that iterates the
-- cascade @n@ times is documented in
-- 'docs/research/composition-combinators-design.md' but is not
-- shipped here.
--
-- See 'docs/research/composition-combinators-design.md' under
-- "Combinators beyond `compose`" → "`feedback1` — admitted
-- (single-step reduction)" for the full design record.
feedback1 ::
  forall rs1 rs2 s1 s2 ci co.
  ( WeakenR rs1,
    WeakenR rs2,
    Disjoint (Names rs2) (Names rs1),
    Disjoint (Names rs1) (Names (Append rs2 rs1))
  ) =>
  SymTransducer (HsPred rs1 ci) rs1 s1 ci co ->
  SymTransducer (HsPred rs2 co) rs2 s2 co ci ->
  SymTransducer
    (HsPred (Append rs1 (Append rs2 rs1)) ci)
    (Append rs1 (Append rs2 rs1))
    (Composite s1 (Composite s2 s1))
    ci
    co
feedback1 t f = compose t (compose f t)
