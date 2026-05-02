{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
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
    Composite (..)
    -- * Sequential composition
  , compose
    -- * Index / term weakening (exposed for advanced uses)
  , WeakenR (..)
  , weakenL
  , weakenLTerm
  , weakenLPred
  , weakenLUpdate
    -- * Substitution (exposed for advanced uses)
  , substTerm
  , substPred
  , substUpdate
  , substOut
  , substOutFields
  ) where

import Unsafe.Coerce (unsafeCoerce)

import Keiki.Core
import Keiki.Generics (Append, appendRegFile)


-- * The composite vertex ---------------------------------------------------

-- | The composite of two vertex types. A newtype around a pair so
-- 'Bounded'/'Enum'/'Eq'/'Show' derive cleanly without orphan
-- instances on @(s1, s2)@ — those would conflict with downstream
-- code.
data Composite s1 s2 = Composite !s1 !s2
  deriving (Eq, Show)


instance (Bounded s1, Bounded s2) => Bounded (Composite s1 s2) where
  minBound = Composite minBound minBound
  maxBound = Composite maxBound maxBound


-- | Column-major enumeration: @Composite s1 s2@ enumerates
-- @s2@ within each @s1@. Indexing assumes both component
-- @Enum@s have contiguous @[minBound .. maxBound]@ ranges (the
-- common case for a derived 'Enum' on an enum-like data type).
instance ( Bounded s1, Enum s1
         , Bounded s2, Enum s2
         ) => Enum (Composite s1 s2) where
  toEnum n =
    let n2 = fromEnum (maxBound :: s2) - fromEnum (minBound :: s2) + 1
        (q, r) = n `divMod` n2
    in Composite (toEnum (q + fromEnum (minBound :: s1)))
                 (toEnum (r + fromEnum (minBound :: s2)))
  fromEnum (Composite a b) =
    let n2 = fromEnum (maxBound :: s2) - fromEnum (minBound :: s2) + 1
        ai = fromEnum a - fromEnum (minBound :: s1)
        bi = fromEnum b - fromEnum (minBound :: s2)
    in ai * n2 + bi


-- * WeakenR: lift an Index over rs2 to (Append rs1 rs2) -------------------

-- | Lift a tail-side 'Index' (or 'IndexN') across an rs1 prefix.
-- The class is indexed by @rs1@; instances walk rs1's slot list with
-- 'SIdx' / 'IS' prepends, converting an @'Index' rs2 r@ into an
-- @'Index' (Append rs1 rs2) r@ and an @'IndexN' s rs2 r@ into an
-- @'IndexN' s (Append rs1 rs2) r@.
class WeakenR (rs1 :: [Slot]) where
  weakenR
    :: forall rs2 r. Index rs2 r -> Index (Append rs1 rs2) r
  weakenRIndexN
    :: forall rs2 s r. IndexN s rs2 r -> IndexN s (Append rs1 rs2) r

instance WeakenR '[] where
  weakenR       i = i
  weakenRIndexN i = i

instance WeakenR rs1 => WeakenR ('(s, t) ': rs1) where
  weakenR       i = SIdx (weakenR       @rs1 i)
  weakenRIndexN i = IS   (weakenRIndexN @rs1 i)


-- * weakenL: lift an Index over rs1 to (Append rs1 rs2) -------------------

-- | Lift a head-side 'Index' across an rs2 suffix. Walks the
-- existing 'Index' shape; @ZIdx@ stays @ZIdx@, @SIdx i@ recurses.
weakenL :: forall rs1 rs2 r. Index rs1 r -> Index (Append rs1 rs2) r
weakenL ZIdx     = ZIdx
weakenL (SIdx i) = SIdx (weakenL @_ @rs2 i)


-- | Walk a 'Term' and weaken every register read across an rs2
-- suffix. 'TInpCtorField' / 'TLit' do not touch the register file,
-- so they pass through unchanged.
weakenLTerm
  :: forall rs1 rs2 ci r.
     Term rs1 ci r -> Term (Append rs1 rs2) ci r
weakenLTerm (TLit r)              = TLit r
weakenLTerm (TReg ix)             = TReg (weakenL @rs1 @rs2 ix)
weakenLTerm (TInpCtorField ic ix) = TInpCtorField ic ix
weakenLTerm (TApp1 f t)           = TApp1 f (weakenLTerm @rs1 @rs2 t)
weakenLTerm (TApp2 f a b)         = TApp2 f (weakenLTerm @rs1 @rs2 a)
                                              (weakenLTerm @rs1 @rs2 b)


-- | Walk an 'HsPred' and weaken every term inside it.
weakenLPred
  :: forall rs1 rs2 ci.
     HsPred rs1 ci -> HsPred (Append rs1 rs2) ci
weakenLPred PTop          = PTop
weakenLPred PBot          = PBot
weakenLPred (PAnd p q)    = PAnd (weakenLPred @rs1 @rs2 p)
                                  (weakenLPred @rs1 @rs2 q)
weakenLPred (POr  p q)    = POr  (weakenLPred @rs1 @rs2 p)
                                  (weakenLPred @rs1 @rs2 q)
weakenLPred (PNot p)      = PNot (weakenLPred @rs1 @rs2 p)
weakenLPred (PEq a b)     = PEq  (weakenLTerm @rs1 @rs2 a)
                                  (weakenLTerm @rs1 @rs2 b)
weakenLPred (PInCtor ic)  = PInCtor ic


-- | Walk an 'Update' and weaken every register write + every
-- right-hand-side 'Term'. The slot-name index @w@ is preserved by
-- weakening — adding new slots to the right of @rs1@ does not change
-- which slot names the update writes.
weakenLUpdate
  :: forall rs1 rs2 w ci.
     Update rs1 w ci -> Update (Append rs1 rs2) w ci
weakenLUpdate UKeep          = UKeep
weakenLUpdate (USet ix t)    = USet (weakenLIndexN @rs1 @rs2 ix)
                                     (weakenLTerm @rs1 @rs2 t)
weakenLUpdate (UCombine a b) = UCombine (weakenLUpdate @rs1 @rs2 a)
                                         (weakenLUpdate @rs1 @rs2 b)


-- | Slot-name-tagged analogue of 'weakenL'. Walks an existing
-- 'IndexN' shape; @IZ@ stays @IZ@, @IS i@ recurses. Preserves the
-- slot symbol carried by the index.
weakenLIndexN :: forall rs1 rs2 s r. IndexN s rs1 r -> IndexN s (Append rs1 rs2) r
weakenLIndexN IZ     = IZ
weakenLIndexN (IS i) = IS (weakenLIndexN @_ @rs2 i)


-- * Substitution algorithm -------------------------------------------------

-- | The integer position of an 'Index' in its slot list.
-- (Local replica of 'Keiki.Core''s internal @indexInt@; not
-- exported there.)
indexInt :: Index rs r -> Int
indexInt ZIdx     = 0
indexInt (SIdx i) = 1 + indexInt i

-- | Existential wrapper around a 'Term' so 'nthTerm' can return one
-- without exposing the field's type at the call site.
data SomeTerm rs ci where
  SomeTerm :: Term rs ci r -> SomeTerm rs ci


-- | Walk an 'OutFields' chain to position @n@. Returns @Nothing@
-- when @n@ overshoots the chain (a bug in the caller; the design's
-- structural-alignment assumption guarantees @n@ is in range when
-- the constructor names match).
nthTerm :: Int -> OutFields rs ci fs -> Maybe (SomeTerm rs ci)
nthTerm _  OFNil           = Nothing
nthTerm 0  (OFCons t _)    = Just (SomeTerm t)
nthTerm n  (OFCons _ rest)
  | n > 0     = nthTerm (n - 1) rest
  | otherwise = Nothing


-- | Substitute a t2-side 'Term' against t1's edge output. See the
-- design note's "Substituting a Term" section for the rules.
--
-- The result reads from the appended register file
-- @Append rs1 rs2@: rs1 reads come from t1's of1 traversal (these
-- propagate t1's input @ci1@); rs2 reads come from t2's term
-- weakened across the rs1 prefix.
substTerm
  :: forall rs1 rs2 ci1 mid r.
     WeakenR rs1
  => Term rs2 mid r
  -> OutTerm rs1 ci1 mid
  -> Term (Append rs1 rs2) ci1 r
substTerm (TLit r)              _o1 = TLit r
substTerm (TReg ix2)            _o1 = TReg (weakenR @rs1 ix2)
substTerm (TInpCtorField ic2 ix2) o1 =
  case o1 of
    OPack _ic1 wc1 of1
      | icName ic2 == wcName wc1 ->
          let n = indexInt ix2
          in case nthTerm n of1 of
               Just (SomeTerm tm) ->
                 -- tm :: Term rs1 ci1 r' (r' ~ r structurally;
                 -- the slot list of ic2 mirrors of1's tuple shape
                 -- via the GRecord/GTuple Generic derivations).
                 weakenLTerm @rs1 @rs2 (unsafeCoerceTerm tm)
               Nothing -> error
                 ("Keiki.Composition.compose: nthTerm overflow at\
                  \ position " <> show n
                  <> " for InCtor " <> icName ic2
                  <> " — t2 reads a field t1's OutFields doesn't expose.\
                     \ This indicates a structural mismatch between\
                     \ t1's wireCtor and t2's InCtor for the shared\
                     \ mid type.")
      | otherwise -> error
          ("Keiki.Composition.compose: TInpCtorField over " <> icName ic2
           <> " but t1's edge produced " <> wcName wc1
           <> " — caller should ensure structural alignment of mid's\
              \ constructors. Substitution at this position is\
              \ unsound; the composite edge guard's PInCtor\
              \ substitution should make the edge unsatisfiable\
              \ before evaluation reaches this term.")
substTerm (TApp1 f t) o1 = TApp1 f (substTerm @rs1 @rs2 t o1)
substTerm (TApp2 f a b) o1 = TApp2 f (substTerm @rs1 @rs2 a o1)
                                       (substTerm @rs1 @rs2 b o1)


-- | Existentially-coerce a 'Term''s result type. Unsound in general;
-- justified here by the structural-alignment invariant the design
-- note documents: when @icName ic2 == wcName wc1@, the slot list of
-- @ic2@ and the field tuple of @wc1@ are derived from the same
-- 'Generic' representation, so positional reads agree on type.
unsafeCoerceTerm :: forall rs ci r r'. Term rs ci r' -> Term rs ci r
unsafeCoerceTerm = unsafeCoerce


-- | Substitute a t2-side 'HsPred' against t1's edge output. See
-- the design note's "Substituting an HsPred" section for the rules.
substPred
  :: forall rs1 rs2 ci1 mid.
     WeakenR rs1
  => HsPred rs2 mid
  -> OutTerm rs1 ci1 mid
  -> HsPred (Append rs1 rs2) ci1
substPred PTop          _o1 = PTop
substPred PBot          _o1 = PBot
substPred (PAnd p q)     o1 = PAnd (substPred @rs1 @rs2 p o1)
                                    (substPred @rs1 @rs2 q o1)
substPred (POr  p q)     o1 = POr  (substPred @rs1 @rs2 p o1)
                                    (substPred @rs1 @rs2 q o1)
substPred (PNot p)       o1 = PNot (substPred @rs1 @rs2 p o1)
substPred (PEq a b)      o1 = PEq  (substTerm @rs1 @rs2 a o1)
                                    (substTerm @rs1 @rs2 b o1)
substPred (PInCtor ic2)  o1 =
  case o1 of
    OPack _ wc1 _
      | icName ic2 == wcName wc1 -> PTop
      | otherwise                -> PBot


-- | Substitute a t2-side 'Update' against t1's edge output. The
-- slot-name index @w@ is preserved by substitution — substituting
-- input reads inside the right-hand-side 'Term's does not change
-- which slot names the update writes.
substUpdate
  :: forall rs1 rs2 w ci1 mid.
     WeakenR rs1
  => Update rs2 w mid
  -> OutTerm rs1 ci1 mid
  -> Update (Append rs1 rs2) w ci1
substUpdate UKeep            _o1 = UKeep
substUpdate (USet ix2 t)      o1 = USet (weakenRIndexN @rs1 ix2)
                                          (substTerm @rs1 @rs2 t o1)
substUpdate (UCombine a b)    o1 = UCombine (substUpdate @rs1 @rs2 a o1)
                                              (substUpdate @rs1 @rs2 b o1)




-- | Substitute a t2-side 'OutFields' chain against t1's edge output.
substOutFields
  :: forall rs1 rs2 ci1 mid fs.
     WeakenR rs1
  => OutFields rs2 mid fs
  -> OutTerm rs1 ci1 mid
  -> OutFields (Append rs1 rs2) ci1 fs
substOutFields OFNil           _o1 = OFNil
substOutFields (OFCons t rest)  o1 = OFCons (substTerm @rs1 @rs2 t o1)
                                              (substOutFields @rs1 @rs2 rest o1)


-- | Substitute a t2-side 'OutTerm' against t1's edge output. The
-- composite's 'OPack' is tagged with t1's input constructor (the
-- @ic1@ from o1) — not t2's @ic2_co@. See the design note's
-- "Substituting an OutTerm" section.
substOut
  :: forall rs1 rs2 ci1 mid co.
     WeakenR rs1
  => OutTerm rs2 mid co
  -> OutTerm rs1 ci1 mid
  -> OutTerm (Append rs1 rs2) ci1 co
substOut (OPack _ic2_co wc2_co of2) o1 =
  case o1 of
    OPack ic1 _wc1 _of1 ->
      OPack (unsafeCoerceInCtor ic1)
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
compose
  :: forall rs1 rs2 s1 s2 ci1 mid co.
     ( WeakenR rs1
     , Disjoint (Names rs1) (Names rs2)
     )
  => SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 mid
  -> SymTransducer (HsPred rs2 mid) rs2 s2 mid co
  -> SymTransducer (HsPred (Append rs1 rs2) ci1)
                   (Append rs1 rs2)
                   (Composite s1 s2)
                   ci1
                   co
compose t1 t2 = SymTransducer
  { edgesOut    = composedEdges
  , initial     = Composite (initial t1) (initial t2)
  , initialRegs = appendRegFile (initialRegs t1) (initialRegs t2)
  , isFinal     = \(Composite a b) -> isFinal t1 a && isFinal t2 b
  }
  where
    composedEdges
      :: Composite s1 s2
      -> [Edge (HsPred (Append rs1 rs2) ci1)
               (Append rs1 rs2) ci1 co (Composite s1 s2)]
    composedEdges (Composite s1 s2) =
      concatMap (composeEdge s1 s2) (edgesOut t1 s1)

    composeEdge
      :: s1 -> s2
      -> Edge (HsPred rs1 ci1) rs1 ci1 mid s1
      -> [Edge (HsPred (Append rs1 rs2) ci1)
               (Append rs1 rs2) ci1 co (Composite s1 s2)]
    composeEdge _s1Source s2 e1 = case output e1 of
      Nothing  -> [epsilonEdge e1 s2]
      Just o1  -> map (productEdge e1 o1) (edgesOut t2 s2)

    epsilonEdge
      :: Edge (HsPred rs1 ci1) rs1 ci1 mid s1 -> s2
      -> Edge (HsPred (Append rs1 rs2) ci1)
              (Append rs1 rs2) ci1 co (Composite s1 s2)
    epsilonEdge e1 s2 = case e1 of
      Edge { update = u1 } -> Edge
        { guard  = weakenLPred @rs1 @rs2 (guard e1)
        , update = weakenLUpdate @rs1 @rs2 u1
        , output = Nothing
        , target = Composite (target e1) s2
        }

    productEdge
      :: Edge (HsPred rs1 ci1) rs1 ci1 mid s1
      -> OutTerm rs1 ci1 mid
      -> Edge (HsPred rs2 mid)  rs2  mid co s2
      -> Edge (HsPred (Append rs1 rs2) ci1)
              (Append rs1 rs2) ci1 co (Composite s1 s2)
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
      (Edge { update = u1 }, Edge { update = u2 }) -> Edge
        { guard  = PAnd (weakenLPred @rs1 @rs2 (guard e1))
                        (substPred  @rs1 @rs2 (guard e2) o1)
        , update = UCombine
                     (weakenLUpdate @rs1 @rs2 u1)
                     (substUpdate   @rs1 @rs2 u2 o1)
        , output = fmap (\o2 -> substOut @rs1 @rs2 o2 o1) (output e2)
        , target = Composite (target e1) (target e2)
        }
