-- 'unsafeCoerceDisjointness' fabricates a 'Disjoint' constraint
-- dictionary via 'unsafeCoerce' on the trivially-disjoint
-- @Disjoint '[] '[]@ witness. GHC sees the @forall xs ys.@ as
-- ambiguous because neither @xs@ nor @ys@ appear in the result; that
-- is intentional — call sites pin them via 'TypeApplications'.
{-# LANGUAGE PatternSynonyms #-}
{-# OPTIONS_GHC -Wno-redundant-constraints #-}

-- | Existential wrapper for 'SymTransducer' enabling participation in
-- the standard 'Profunctor' / 'Category' ecosystem, plus standalone
-- variance combinators on the concrete 'SymTransducer' type.
--
-- The wrapper 'SomeSymTransducer ci co' hides the register-file slot
-- list and the control-vertex type, exposing only the input alphabet
-- @ci@ and the output alphabet @co@. This is the form ecosystem
-- typeclasses ('Profunctor', 'Category', 'Strong', 'Choice', 'Arrow')
-- expect.
--
-- Stability: experimental. The wrapper and its categorical instances may
-- change before the law contract is resolved. Concrete checked composition
-- through 'Keiki.Composition.composeChecked' is the supported validation
-- boundary for aggregate pipelines.
--
-- == Law status: forward fragment versus inversion/replay
--
-- /Forward equivalence/ means that 'Keiki.Core.delta', 'Keiki.Core.omega',
-- and 'Keiki.Core.step' agree for every command sequence, comparing control
-- states up to the documented state isomorphism. /Inversion equivalence/ adds
-- agreement of 'Keiki.Core.solveOutput', streaming replay, and
-- reconstitution. Because replay is public and central to keiki, a law that
-- holds only forward is called a /forward fragment/, not an unqualified law.
--
-- * 'Profunctor'/'Functor': identity and composition hold on tested multi-step
--   forward traces. They fail inversion equivalence because input maps poison
--   @icBuild@ and output maps poison @wcMatch@. Mapped names are stamped with
--   @#lmapped@/@#rmapped@; arm predicates lowered by contramap use the same
--   marker and are symbolically conservative.
-- * 'Category': the identity sentinel is definitional, and stateful forward
--   associativity is tested after the real witness and snapshot fixes.
--   Non-identity composition is partial: slot overlap raises
--   'CategoryOverlapError', and a mapped boundary raises
--   'PoisonedCompositionError'. It is therefore not an unqualified lawful
--   'Category' over all public values.
-- * 'Choice': 'left''/'right'' preserve forward routing and replay for a
--   replayable stateful transducer on tested multi-step traces; they do not
--   repair an underlying transducer's inversion defect. Real
--   'PLeftArm'/'PRightArm' guards make the arms disjoint even for
--   epsilon/register-only underlying guards.
-- * 'Strong': 'first''/'second'' preserve the threaded value and forward
--   state evolution, but fail inversion equivalence because their paired
--   descriptors are not invertible. A Strong-produced boundary is poisoned.
-- * 'Arrow': standalone 'Arr.arr' has forward function behavior but is not
--   replay-invertible. Fusion fails: @arr f >>> arr g@ raises
--   'PoisonedCompositionError' rather than equalling @arr (g . f)@.
--
-- Deferred API choices (recorded 2026-07-12) are a forward-only wrapper, a
-- separate replay-safe/isomorphism capability, a total internal category, or
-- selective instance removal. This module selects none of them; all existing
-- instances remain available while the experimental contract is evaluated.
--
-- See @docs/plans/27-existential-wrapper-for-symtransducer-plus-profunctor-instance-and-variance-combinators.md@
-- for the design rationale and the documented variance caveat:
-- transducers produced by 'lmapCi' / 'rmapCo' / 'dimapTransducer' /
-- 'lmapMaybeCi' do *not* preserve the round-trip guarantee of
-- 'Keiki.Core.solveOutput'. Forward processing
-- ('Keiki.Core.delta', 'Keiki.Core.omega', 'Keiki.Core.evalPred',
-- 'Keiki.Core.evalTerm') is unaffected; only the inversion-from-event
-- path is dropped on lmapped/rmapped edges. See each combinator's
-- haddock for the precise contract.
--
-- This module also hosts the 'Control.Category.Category' instance
-- on 'SomeSymTransducer' (EP-28 of MasterPlan 9). The 'Cat.id' lift
-- uses 'identityTransducer' (a one-vertex transducer that emits its
-- input as its output via a phantom one-slot register file); 'Cat..'
-- delegates to 'Keiki.Composition.compose' after a *runtime*
-- slot-name overlap check that raises 'CategoryOverlapError' on
-- collisions. The check exists because the wrapper hides @rs@, so
-- 'compose''s static @Disjoint (Names rs1) (Names rs2)@ constraint
-- cannot be discharged by GHC at the wrapper boundary.
module Keiki.Profunctor
  ( -- * Existential wrapper
    SomeSymTransducer (SomeSymIdentity),
    pattern SomeSymTransducer,
    someSymTransducer,
    PoisonProvenance (..),

    -- * Standalone variance combinators on the concrete 'SymTransducer'
    lmapCi,
    rmapCo,
    dimapTransducer,
    lmapMaybeCi,

    -- * Identity transducer (concrete form; 'Cat.id' uses the sentinel constructor)
    IdVertex (..),
    identityTransducer,

    -- * Arrow's @arr@ (concrete form; the 'Arr.Arrow' instance wraps it)
    arrTransducer,

    -- * Category-instance overlap exception
    CategoryOverlapError (..),
    PoisonedCompositionError (..),
  )
where

import Control.Arrow qualified as Arr
import Control.Category qualified as Cat
import Control.Exception (Exception, throw)
import Data.Profunctor (Choice (..), Profunctor (..), Strong (..))
import Data.Proxy (Proxy (..))
import Keiki.Composition
  ( KnownSlots (..),
    SlotListWitness (WNil),
    alternative,
    appendWitness,
    compose,
    withDisjointNil,
    withKnownSlots,
  )
import Keiki.Core
import Unsafe.Coerce (unsafeCoerce)

-- | Existential wrapper hiding @rs@ (register-file slot list) and
-- @s@ (control vertex), exposing only the input alphabet @ci@ and
-- output alphabet @co@. Predicate carrier is fixed to 'HsPred' since
-- "Keiki.Composition"'s combinators are pinned to that carrier.
--
-- The packed 'KnownSlots' constraint supplies a value-level witness
-- for the hidden slot-list spine and bundles 'WeakenR' and
-- 'KnownSlotNames' as superclasses. Composite wrappers append the
-- real witnesses and re-derive all three dictionaries by structural
-- induction; no method-carrying dictionary is fabricated. The
-- packed constraints @Bounded s@ and
-- @Enum s@ let pattern-matched-out transducers participate in the
-- symbolic analyses ('Keiki.Symbolic.isSingleValuedSym',
-- 'Keiki.Core.checkHiddenInputs'), which both enumerate the vertex
-- type. Every keiki vertex type already derives 'Bounded' and
-- 'Enum' (see 'Keiki.Fixtures.EmailDelivery.EmailVertex',
-- 'Keiki.CompositionAlternativeSpec.PingVertex', and 'IdVertex'
-- in this module), so packing the constraints does not restrict
-- what users can wrap.
--
-- The wrapper has two constructors:
--
--   * 'SomeSymTransducer' — wraps a concrete 'SymTransducer'.
--   * 'SomeSymIdentity'   — a sentinel for 'Cat.id'. Constraint
--     @ci ~ co@ comes from the constructor's GADT signature.
--
-- The sentinel exists because 'Keiki.Composition.compose' substitutes
-- t2's 'TInpCtorField'-on-@ic2@ against t1's 'WireCtor'-named
-- emission, requiring @icName ic2 == wcName wc1@ for the substitution
-- to be sound. A *generic* identity transducer (one whose 'InCtor' is
-- the same regardless of @ci@) cannot satisfy this for arbitrary
-- upstream wire names. The sentinel sidesteps this by short-circuiting
-- @id . t@ and @t . id@ in 'Cat..' rather than running them through
-- 'compose'. See 'identityTransducer' for the concrete-identity
-- transducer that some non-Category code paths still want.
--
-- Pattern-match on the compatibility pattern to recover the underlying
-- 'SymTransducer' (the @rs@ and @s@ variables come into scope as
-- skolem types — they may not escape the pattern match). Handle
-- 'SomeSymIdentity' explicitly when traversing arbitrary
-- 'SomeSymTransducer' values.
--
-- | Tracks whether an existential wrapper's input or output descriptor has
-- been rewritten in a way that is unsafe to cross at a composition boundary.
data PoisonProvenance = PoisonProvenance
  { poisonedInput :: !Bool,
    poisonedOutput :: !Bool
  }
  deriving stock (Eq, Show)

cleanProvenance :: PoisonProvenance
cleanProvenance = PoisonProvenance False False

-- | A concrete symbolic transducer with its register and vertex types hidden,
-- or the definitional identity sentinel used by the 'Cat.Category' instance.
data SomeSymTransducer ci co where
  SomeSymTransducerWith ::
    ( KnownSlots rs,
      Bounded s,
      Enum s
    ) =>
    PoisonProvenance ->
    SymTransducer (HsPred rs ci) rs s ci co ->
    SomeSymTransducer ci co
  SomeSymIdentity :: SomeSymTransducer a a

-- | Compatibility construction and match pattern for a concrete wrapper.
-- Direct construction starts with honest input/output alphabets; internal
-- instance operations retain provenance through @SomeSymTransducerWith@.
pattern SomeSymTransducer ::
  forall ci co.
  () =>
  forall rs s.
  (KnownSlots rs, Bounded s, Enum s) =>
  SymTransducer (HsPred rs ci) rs s ci co ->
  SomeSymTransducer ci co
pattern SomeSymTransducer t <- SomeSymTransducerWith _ t
  where
    SomeSymTransducer t = SomeSymTransducerWith cleanProvenance t

{-# COMPLETE SomeSymTransducer, SomeSymIdentity #-}

-- | Smart constructor: lift a concrete 'SymTransducer' into the
-- wrapper. Equivalent to applying the data constructor; provided for
-- naming consistency with the rest of @Keiki.Profunctor@'s exports
-- and for users who prefer functions over constructors.
someSymTransducer ::
  ( KnownSlots rs,
    Bounded s,
    Enum s
  ) =>
  SymTransducer (HsPred rs ci) rs s ci co ->
  SomeSymTransducer ci co
someSymTransducer = SomeSymTransducerWith cleanProvenance

-- * Standalone variance combinators ---------------------------------------

-- | Pre-compose with a contramap on the input alphabet. Walks every
-- 'InCtor' inside the transducer's guards / updates / outputs and
-- replaces each with one whose 'icMatch' is precomposed with @f@.
--
-- /Variance caveat (see "Law status" above):/ the rewritten 'InCtor's 'icBuild' is poisoned
-- (raises a runtime error if invoked) — callers must not invoke
-- 'Keiki.Core.solveOutput' on edges produced by this combinator. The
-- forward evaluation path ('Keiki.Core.evalPred',
-- 'Keiki.Core.evalTerm', 'Keiki.Core.delta', 'Keiki.Core.omega') only
-- ever consults 'icMatch'; it is unaffected by the poisoned
-- 'icBuild'.
lmapCi ::
  forall ci ci' rs s co.
  (ci' -> ci) ->
  SymTransducer (HsPred rs ci) rs s ci co ->
  SymTransducer (HsPred rs ci') rs s ci' co
lmapCi f t =
  SymTransducer
    { edgesOut = \s -> map (rewriteEdge f) (edgesOut t s),
      initial = initial t,
      initialRegs = initialRegs t,
      isFinal = isFinal t
    }

-- | Pre-compose with a partial contramap on the input alphabet.
-- Inputs for which @f@ returns 'Nothing' fail every guard's
-- structural 'PInCtor' check, effectively filtering them out of the
-- transducer's command stream.
--
-- /Variance caveat (see "Law status" above):/ same as 'lmapCi' — 'Keiki.Core.solveOutput' is
-- not preserved.
lmapMaybeCi ::
  forall ci ci' rs s co.
  (ci' -> Maybe ci) ->
  SymTransducer (HsPred rs ci) rs s ci co ->
  SymTransducer (HsPred rs ci') rs s ci' co
lmapMaybeCi f t =
  SymTransducer
    { edgesOut = \s -> map (rewriteEdgeMaybe f) (edgesOut t s),
      initial = initial t,
      initialRegs = initialRegs t,
      isFinal = isFinal t
    }

-- | Post-compose with a covariant map on the output alphabet. Walks
-- every 'WireCtor' inside the transducer's outputs and replaces each
-- with one whose 'wcBuild' is post-composed with @g@.
--
-- /Variance caveat (see "Law status" above):/ the rewritten 'WireCtor's 'wcMatch' is set to
-- @const Nothing@ — 'Keiki.Core.solveOutput' on rewritten edges
-- returns 'Nothing'. The forward output construction (which only
-- uses 'wcBuild') is unaffected.
rmapCo ::
  forall ci co co' rs s.
  (co -> co') ->
  SymTransducer (HsPred rs ci) rs s ci co ->
  SymTransducer (HsPred rs ci) rs s ci co'
rmapCo g t =
  SymTransducer
    { edgesOut = \s -> map (rewriteEdgeOut g) (edgesOut t s),
      initial = initial t,
      initialRegs = initialRegs t,
      isFinal = isFinal t
    }

-- | Bidirectional map on input and output alphabets. Equivalent to
-- @'rmapCo' g . 'lmapCi' f@. /Variance caveat (see "Law status" above)/ as both 'lmapCi' and
-- 'rmapCo': 'Keiki.Core.solveOutput' is not preserved on the result.
dimapTransducer ::
  (ci' -> ci) ->
  (co -> co') ->
  SymTransducer (HsPred rs ci) rs s ci co ->
  SymTransducer (HsPred rs ci') rs s ci' co'
dimapTransducer f g = rmapCo g . lmapCi f

-- * Profunctor / Functor instances on the wrapper -----------------------

-- | Standard 'Data.Profunctor.Profunctor' instance. Delegates to the
-- standalone combinators above. Inherits their /variance caveat/:
-- 'lmap' / 'rmap' / 'dimap' on the wrapper produce transducers whose
-- 'Keiki.Core.solveOutput' is no longer informative — see each
-- combinator's haddock.
--
-- The 'SomeSymIdentity' sentinel is materialised into a concrete
-- 'identityTransducer' wrap before the variance combinators run, so
-- the @ci@/@co@ rewrites apply uniformly.
instance Profunctor SomeSymTransducer where
  dimap f g (SomeSymTransducerWith provenance t) =
    SomeSymTransducerWith
      provenance {poisonedInput = True, poisonedOutput = True}
      (dimapTransducer f g t)
  dimap f g SomeSymIdentity =
    SomeSymTransducerWith
      (PoisonProvenance True True)
      (dimapTransducer f g identityTransducer)
  lmap f (SomeSymTransducerWith provenance t) =
    SomeSymTransducerWith
      provenance {poisonedInput = True}
      (lmapCi f t)
  lmap f SomeSymIdentity =
    SomeSymTransducerWith
      (PoisonProvenance True False)
      (lmapCi f identityTransducer)
  rmap g (SomeSymTransducerWith provenance t) =
    SomeSymTransducerWith
      provenance {poisonedOutput = True}
      (rmapCo g t)
  rmap g SomeSymIdentity =
    SomeSymTransducerWith
      (PoisonProvenance False True)
      (rmapCo g identityTransducer)

-- | 'Functor' on the output alphabet. @'fmap' = 'rmap'@.
instance Functor (SomeSymTransducer ci) where
  fmap = rmap

-- * Identity transducer (used by 'Cat.id') ------------------------------

-- | One-vertex enum used as the control vertex of 'identityTransducer'.
-- The single nullary constructor lets the identity transducer have a
-- single edge (from 'IdVertex' back to 'IdVertex') that copies the
-- input straight through to the output.
data IdVertex = IdVertex
  deriving stock (Eq, Show, Bounded, Enum)

-- | An 'InCtor' for an arbitrary alphabet @a@. Uses a phantom
-- one-slot register file @'[ '("payload", a) ]@ to bridge the
-- alphabet through the inversion machinery: 'icMatch' wraps any @a@
-- as a singleton 'RegFile'; 'icBuild' unwraps the same. The phantom
-- slot exists only inside this 'InCtor''s wrapping types — the
-- transducer's *real* @initialRegs@ stays 'RNil', so no runtime
-- register is allocated.
identityInCtor :: forall a. InCtor a '[ '("payload", a)]
identityInCtor =
  InCtor
    { icName = "Identity",
      icMatch = \a -> Just (RCons (Proxy @"payload") a RNil),
      icBuild = \(RCons _ a RNil) -> a
    }

-- | A 'WireCtor' for an arbitrary alphabet @a@. Uses the field-tuple
-- @(a, ())@ that 'OutFields' produces for a single-element list: one
-- field of type @a@ followed by the trailing 'OFNil' encoded as
-- @()@. Forward construction unwraps the tuple to its single
-- payload; inversion via 'wcMatch' wraps an @a@ back up.
identityWireCtor :: forall a. WireCtor a (a, ())
identityWireCtor =
  WireCtor
    { wcName = "Identity",
      wcMatch = \a -> Just (a, ()),
      wcBuild = \(a, ()) -> a
    }

-- | The identity transducer for an arbitrary alphabet @a@. One vertex
-- ('IdVertex'); one edge whose guard is @'PInCtor' 'identityInCtor'@
-- (semantically equivalent to 'PTop' standalone — 'identityInCtor''s
-- 'icMatch' always returns 'Just' — but arm-discriminating when
-- lifted by 'Keiki.Composition.alternative'), writes nothing
-- (@'UKeep'@), and emits its input as the wire output. Used by
-- 'Cat.id' on 'SomeSymTransducer'.
--
-- Forward processing on input @a@ evaluates the 'OutFields' by
-- reading the @"payload"@ slot via the 'InCtor' (which round-trips
-- @a@ through the phantom register file), then 'wcBuild :: (a, ()) -> a'
-- unwraps the field tuple to produce @a@. Inversion via
-- 'Keiki.Core.solveOutput' goes the other way and is similarly
-- well-defined; the identity transducer satisfies all keiki
-- guarantees by construction.
--
-- /Why @PInCtor identityInCtor@ rather than @PTop@:/ EP-29 M1
-- discovered that the simpler @PTop@ guard fires on every input,
-- including the *wrong arm* of an 'Keiki.Composition.alternative'
-- composite. 'liftRPredAlt PTop = PTop' (the lift recurses
-- structurally and has no PInCtor to lift), so an
-- @alternative t identityTransducer@ composite at @Left _@ inputs
-- would see *both* arms' edges fire — t1's correctly, but
-- identityTransducer's incorrectly (it should be inactive on the
-- Left arm). Replacing 'PTop' with 'PInCtor identityInCtor' is
-- semantically a no-op standalone (icMatch always succeeds) but
-- becomes arm-discriminating after 'liftLPredAlt' / 'liftRPredAlt'
-- wraps the InCtor in 'leftInCtor' / 'rightInCtor' (whose
-- 'icMatch' returns 'Nothing' on the wrong arm).
identityTransducer ::
  forall a.
  SymTransducer (HsPred '[] a) '[] IdVertex a a
identityTransducer =
  SymTransducer
    { edgesOut = \IdVertex ->
        [ Edge
            { guard = PInCtor identityInCtor,
              update = UKeep,
              output = [identityOutTerm],
              target = IdVertex
            }
        ],
      initial = IdVertex,
      initialRegs = RNil,
      isFinal = const True
    }
  where
    identityOutTerm :: OutTerm '[] a a
    identityOutTerm =
      OPack
        identityInCtor
        identityWireCtor
        (OFCons (TInpCtorField identityInCtor ZIdx) OFNil)

-- * Disjointness escape hatch (private) ---------------------------------

-- | Exception raised when 'Cat..' is invoked on two
-- 'SomeSymTransducer' values whose underlying register files share a
-- slot name. Carries the colliding slot names so the message points
-- at the actual offender.
--
-- Catch with @Control.Exception.catch@ or use @evaluate@ to force
-- the throw at a controlled point in your program.
data CategoryOverlapError = CategoryOverlapError
  { coeSlots :: [String]
  }
  deriving stock (Eq, Show)

instance Exception CategoryOverlapError

-- | Exception raised when categorical composition would cross a boundary
-- rewritten by a non-invertible input/output map. The boundary is rejected
-- before name substitution can silently bypass the map.
data PoisonedCompositionError = PoisonedCompositionError
  { pceSide :: String,
    pceDetail :: String
  }
  deriving stock (Eq, Show)

instance Exception PoisonedCompositionError

-- | A constraint dictionary for @'Disjoint' xs ys@. Used together
-- with 'unsafeCoerceDisjointness' to smuggle the constraint into
-- scope after a value-level overlap check.
data DictDisjoint xs ys where
  DictDisjoint :: (Disjoint xs ys) => DictDisjoint xs ys

-- | Fabricate a 'DictDisjoint' for arbitrary @xs@ and @ys@. This is
-- the only fabricated dictionary in this module, and its only call
-- site is the body of 'Cat..' after the value-level check has
-- confirmed the slot lists are disjoint. Composite wrappers carry
-- real 'KnownSlots' witnesses, so the checked names remain accurate
-- under arbitrary nesting. Calling this without that check can
-- produce a semantically broken composite.
--
-- Implementation: @'Disjoint' '[] '[]@ reduces to the trivially-true
-- constraint @()@, so @DictDisjoint @'[] @'[]@ is always
-- constructible. 'unsafeCoerce' rewrites the existential type
-- arguments to whatever the call site demands.
unsafeCoerceDisjointness ::
  forall xs ys.
  DictDisjoint xs ys
unsafeCoerceDisjointness =
  unsafeCoerce (DictDisjoint :: DictDisjoint '[] '[])

-- * Category instance --------------------------------------------------

-- | Standard 'Control.Category.Category' instance.
--
-- @'Cat.id'@ is the 'SomeSymIdentity' sentinel constructor; @'Cat..'@
-- short-circuits when either argument is the sentinel, returning the
-- other argument unchanged. The Category laws @id . t = t@ and
-- @t . id = t@ thus hold *by definition* (no behavioural test
-- needed). 'identityTransducer' is the concrete-form identity used
-- by the 'Profunctor' / 'Functor' instances when they need to apply
-- variance combinators to the sentinel; it is not used by 'Cat..'.
--
-- For non-identity composition, @'Cat..'@ delegates to
-- 'Keiki.Composition.compose'. The wrapper hides @rs@, so
-- @compose@'s static @Disjoint (Names rs1) (Names rs2)@ constraint
-- cannot be discharged by GHC; instead, the operator reads each
-- transducer's slot names at the value level via 'KnownSlots',
-- checks for overlap, and either:
--
--   * raises 'CategoryOverlapError' (synchronously, on overlap), or
--   * uses 'unsafeCoerceDisjointness' for the methodless constraint,
--     calls 'compose', and re-derives the composite's method-carrying
--     dictionaries from the appended slot-list witnesses.
--
-- /Why a sentinel rather than a real identity transducer:/
-- 'Keiki.Composition.compose' substitutes t2's @TInpCtorField ic2@
-- against t1's emitted 'WireCtor' @wc1@ and demands
-- @icName ic2 == wcName wc1@; otherwise it raises a "structural
-- mismatch" runtime error. A *generic* identity transducer (one
-- 'InCtor' that serves every alphabet) cannot satisfy this for
-- arbitrary upstream wire names, so feeding it through 'compose'
-- would always fail. The sentinel sidesteps this by short-circuiting.
--
-- See @test/Keiki/CategorySpec.hs@ for the law tests (behavioural
-- equality on @id . t@, @t . id@, and associativity, plus the
-- 'CategoryOverlapError' path).
instance Cat.Category SomeSymTransducer where
  id = SomeSymIdentity

  SomeSymIdentity . t = t
  t . SomeSymIdentity = t
  SomeSymTransducerWith provenance2 t2 . SomeSymTransducerWith provenance1 t1 =
    composeWrappers provenance1 t1 provenance2 t2

-- | Compose two existentially-packed transducers, performing the
-- runtime overlap check that 'Cat..' delegates to. Factored out so
-- the existential @rs1@ and @rs2@ skolems are bound to named type
-- variables (the instance method's pattern signatures cannot, on
-- their own, name them in a form usable inside 'TypeApplications').
composeWrappers ::
  forall rs1 rs2 s1 s2 ci mid co.
  ( KnownSlots rs1,
    KnownSlots rs2,
    Bounded s1,
    Enum s1,
    Bounded s2,
    Enum s2
  ) =>
  PoisonProvenance ->
  SymTransducer (HsPred rs1 ci) rs1 s1 ci mid ->
  PoisonProvenance ->
  SymTransducer (HsPred rs2 mid) rs2 s2 mid co ->
  SomeSymTransducer ci co
composeWrappers provenance1 t1 provenance2 t2 =
  let names1 = slotNames @rs1
      names2 = slotNames @rs2
      overlap = filter (`elem` names2) names1
      boundaryPoison
        | poisonedOutput provenance1 =
            Just
              ( PoisonedCompositionError
                  "upstream output"
                  "the upstream wrapper was produced by rmap/dimap/first/arr; move the output map outside the composition (see Law status)"
              )
        | poisonedInput provenance2 =
            Just
              ( PoisonedCompositionError
                  "downstream input"
                  "the downstream wrapper was produced by lmap/dimap/first; move the input map outside the composition (see Law status)"
              )
        | otherwise = Nothing
   in case boundaryPoison of
        Just err -> throw err
        Nothing | not (null overlap) -> throw (CategoryOverlapError overlap)
        Nothing -> case unsafeCoerceDisjointness @(Names rs1) @(Names rs2) of
          DictDisjoint ->
            withKnownSlots
              (appendWitness (slotWitness @rs1) (slotWitness @rs2))
              ( SomeSymTransducerWith
                  ( PoisonProvenance
                      { poisonedInput = poisonedInput provenance1,
                        poisonedOutput = poisonedOutput provenance2
                      }
                  )
                  (compose t1 t2)
              )

-- * Choice instance ----------------------------------------------------

-- | Standard 'Data.Profunctor.Choice.Choice' instance.
--
-- @'left''@ on @t :: 'SomeSymTransducer' a b@ produces a transducer
-- of type @'SomeSymTransducer' (Either a c) (Either b c)@: a @Left a@
-- input is routed through @t@ producing @Left b@; a @Right c@ input
-- passes straight through unchanged. Implemented as
-- @'alternative' t 'identityTransducer'@ — the right arm is the
-- one-vertex identity transducer at alphabet @c@.
--
-- @'right''@ is the symmetric routing: @'alternative' identityTransducer t@.
--
-- /No slot-name overlap risk:/ 'identityTransducer' has @rs = '[]@,
-- so the @'Disjoint' (Names rs) (Names '[])@ side condition on
-- 'alternative' is proved by induction over the packed 'KnownSlots'
-- witness — no 'CategoryOverlapError' path and no coercion are needed.
-- For 'right'', the left register list is empty, so both append and
-- disjointness reduce definitionally and the original witness applies.
--
-- /Sentinel handling:/ when the input is the 'SomeSymIdentity'
-- sentinel, both @'left''@ and @'right''@ return 'SomeSymIdentity' —
-- @'left'' Cat.id = Cat.id@ at the @Either@ alphabet, by definition
-- of identity. The Choice law @left' Cat.id = Cat.id@ holds *by
-- construction* on the wrapper.
--
-- /Variance caveat (see "Law status" above):/ inherits 'Keiki.Composition.alternative''s
-- mechanical-inversion preservation: @solveOutput@ on edges produced
-- by @left'@ / @right'@ runs the underlying alternative's
-- @leftInCtor@ / @rightInCtor@ wrappers, which preserve round-trip
-- behaviour. This is *more* preservation than the
-- 'lmapCi' / 'rmapCo' combinators (which poison @icBuild@); the
-- Choice instance does not introduce additional loss.
instance Choice SomeSymTransducer where
  left' ::
    forall a b c.
    SomeSymTransducer a b ->
    SomeSymTransducer (Either a c) (Either b c)
  left' SomeSymIdentity = SomeSymIdentity
  left' (SomeSymTransducerWith provenance t) = leftWrap provenance t

  right' ::
    forall a b c.
    SomeSymTransducer a b ->
    SomeSymTransducer (Either c a) (Either c b)
  right' SomeSymIdentity = SomeSymIdentity
  right' (SomeSymTransducerWith provenance t) = rightWrap provenance t

-- | Helper for 'left'' on a wrapped concrete transducer. Factored out
-- to bind the existentially-packed @rs@ and @s@ to named type
-- variables for the witness induction.
leftWrap ::
  forall rs s ci co c.
  ( KnownSlots rs,
    Bounded s,
    Enum s
  ) =>
  PoisonProvenance ->
  SymTransducer (HsPred rs ci) rs s ci co ->
  SomeSymTransducer (Either ci c) (Either co c)
leftWrap provenance t =
  let w = slotWitness @rs
   in withDisjointNil w $
        withKnownSlots
          (appendWitness w WNil)
          (SomeSymTransducerWith provenance (alternative t (identityTransducer @c)))

-- | Helper for 'right'' on a wrapped concrete transducer. Symmetric
-- to 'leftWrap'.
rightWrap ::
  forall rs s ci co c.
  ( KnownSlots rs,
    Bounded s,
    Enum s
  ) =>
  PoisonProvenance ->
  SymTransducer (HsPred rs ci) rs s ci co ->
  SomeSymTransducer (Either c ci) (Either c co)
rightWrap provenance t =
  SomeSymTransducerWith provenance (alternative (identityTransducer @c) t)

-- * Strong instance ----------------------------------------------------

-- | Thread an unrelated value @c@ through a transducer that only
-- knows about @ci -> co@. Implemented from primitives because MP-8
-- declined the general 'parallel' combinator (see
-- @docs/plans/24-composition-combinators-beyond-sequential-design-milestone.md@).
--
-- Implementation walks each edge of @t@:
--
--   * Guards / updates are rewritten via 'contraPred' / 'contraUpdate'
--     with @fst@ as the contramap. The original guards (which test
--     'PInCtor's against @ci@) become guards that test the same
--     'PInCtor's against the @ci@ projection of @(ci, c)@.
--   * Outputs (each @'OPack' ic wc fields@) are rewritten by
--     prepending a @c@-projection field at the head of the
--     'OutFields' chain (read via 'pairSndInCtor') and replacing the
--     'WireCtor' with one that consumes @(c, fs)@ and produces
--     @(co, c)@ — @\\(c, fs) -> (wcBuild wc fs, c)@.
--
-- /Variance caveat (see "Law status" above):/ same lossy-@solveOutput@ contract as 'lmapCi' /
-- 'rmapCo'. The contramapped 'InCtor's 'icBuild' is poisoned, the
-- new 'WireCtor's 'wcMatch' is @const Nothing@, and 'pairSndInCtor''s
-- 'icBuild' is poisoned. Forward processing
-- ('Keiki.Core.delta', 'Keiki.Core.omega') is unaffected.
firstSym ::
  forall rs s ci co c.
  SymTransducer (HsPred rs ci) rs s ci co ->
  SymTransducer (HsPred rs (ci, c)) rs s (ci, c) (co, c)
firstSym t =
  SymTransducer
    { edgesOut = \s -> map firstEdge (edgesOut t s),
      initial = initial t,
      initialRegs = initialRegs t,
      isFinal = isFinal t
    }
  where
    firstEdge ::
      Edge (HsPred rs ci) rs ci co s ->
      Edge (HsPred rs (ci, c)) rs (ci, c) (co, c) s
    firstEdge Edge {guard = g, update = u, output = mo, target = tgt} =
      Edge
        { guard = contraPred fst g,
          update = contraUpdate fst u,
          output = fmap firstOutTerm mo,
          target = tgt
        }

    -- EP-53: 'OutFields' is now indexed by a single input field schema,
    -- so the threaded-@c@ projection and the original fields must share
    -- one schema. We build a /combined/ 'InCtor' for @(ci, c)@ whose
    -- schema prepends a @"snd"@ slot (carrying @c@) onto the original
    -- constructor's @ifs@, then re-home the original fields' reads into
    -- it (shifting each index past the new head slot). 'firstSym''s
    -- 'solveOutput' stays dead ('firstWireCtor''s @wcMatch@ is
    -- @const Nothing@), so this is correctness-neutral for forward
    -- processing while making the lossy edge well-typed.
    firstOutTerm :: OutTerm rs ci co -> OutTerm rs (ci, c) (co, c)
    firstOutTerm (OPack ic wc fields) =
      let cic = firstInCtor ic
       in OPack cic (firstWireCtor wc) (firstOutFields cic fields)

    firstWireCtor :: forall fs. WireCtor co fs -> WireCtor (co, c) (c, fs)
    firstWireCtor WireCtor {wcName = n, wcBuild = b} =
      WireCtor
        { wcName = n <> "_first",
          wcMatch = \_ -> Nothing,
          wcBuild = \(cv, fs) -> (b fs, cv)
        }

    -- \| Combine an @(ci)@ input constructor with the threaded @c@ into a
    -- @(ci, c)@ constructor whose field schema is @"snd"@ (for @c@)
    -- prepended to the original @ifs@.
    firstInCtor ::
      forall ifs. InCtor ci ifs -> InCtor (ci, c) ('("snd", c) ': ifs)
    firstInCtor ic@InCtor {} =
      InCtor
        { icName = icName ic,
          icMatch = \(civ, cv) -> case icMatch ic civ of
            Just rf -> Just (RCons (Proxy @"snd") cv rf)
            Nothing -> Nothing,
          icBuild = \(RCons _ cv rf) -> (icBuild ic rf, cv)
        }

    firstOutFields ::
      forall ifs fs.
      InCtor (ci, c) ('("snd", c) ': ifs) ->
      OutFields rs ci ifs fs ->
      OutFields rs (ci, c) ('("snd", c) ': ifs) (c, fs)
    firstOutFields cic fields =
      OFCons (TInpCtorField cic ZIdx) (goFields fields)
      where
        goFields ::
          forall fs'.
          OutFields rs ci ifs fs' ->
          OutFields rs (ci, c) ('("snd", c) ': ifs) fs'
        goFields OFNil = OFNil
        goFields (OFCons tm fs') = OFCons (goTerm tm) (goFields fs')

        -- Re-home each read into the combined constructor, shifting the
        -- index past the new @"snd"@ head slot. The original reads name
        -- the edge's one input constructor, so reusing @cic@ (built from
        -- the OPack's 'InCtor') preserves forward semantics.
        goTerm ::
          forall a.
          Term rs ci ifs a ->
          Term rs (ci, c) ('("snd", c) ': ifs) a
        goTerm (TLit r) = TLit r
        goTerm (TReg ix) = TReg ix
        goTerm (TInpCtorField _ ix) = TInpCtorField cic (SIdx ix)
        goTerm (TApp1 h a) = TApp1 h (goTerm a)
        goTerm (TApp2 h a b) = TApp2 h (goTerm a) (goTerm b)
        goTerm (TArith op a b) = TArith op (goTerm a) (goTerm b)

-- | Standard 'Data.Profunctor.Strong.Strong' instance. Threads an
-- unrelated value through a transducer.
--
-- @'first''@ delegates to 'firstSym' on a wrapped concrete
-- transducer; on the 'SomeSymIdentity' sentinel it returns
-- 'SomeSymIdentity' (since @(a, c) -> (a, c)@ is identity).
--
-- @'second''@ is derived via @swap@: @second' = lmap swap . first' . rmap swap@,
-- which compiles to one extra contramap pair around the @firstSym@
-- core. A direct @secondSym@ implementation could shave the two
-- rewrites for ~10% better build cost, but the current shape keeps
-- the symmetry obvious and the implementation small.
--
-- /Variance caveat (see "Law status" above):/ inherits 'firstSym''s lossy-@solveOutput@
-- contract.
instance Strong SomeSymTransducer where
  first' ::
    forall a b c.
    SomeSymTransducer a b ->
    SomeSymTransducer (a, c) (b, c)
  first' SomeSymIdentity = SomeSymIdentity
  first' (SomeSymTransducerWith provenance t) =
    SomeSymTransducerWith
      provenance {poisonedInput = True, poisonedOutput = True}
      (firstSym t)

  second' ::
    forall a b c.
    SomeSymTransducer a b ->
    SomeSymTransducer (c, a) (c, b)
  second' SomeSymIdentity = SomeSymIdentity
  second' (SomeSymTransducerWith provenance t) =
    SomeSymTransducerWith
      provenance {poisonedInput = True, poisonedOutput = True}
      (lmapCi swap (rmapCo swap (firstSym t)))
    where
      swap :: forall x y. (x, y) -> (y, x)
      swap (x, y) = (y, x)

-- * Arrow instance ------------------------------------------------------

-- | A stateless one-edge transducer that lifts an arbitrary Haskell
-- function. Used by the 'Arr.Arrow' instance's 'Arr.arr' method.
--
-- Construction: one vertex ('IdVertex'); one edge whose guard is
-- @'PInCtor' 'identityInCtor'@ (always-fires standalone, but
-- arm-discriminating when lifted by 'Keiki.Composition.alternative'
-- — see 'identityTransducer' for the same lesson); the edge's
-- 'WireCtor's 'wcBuild' applies @f@ to the read input.
--
-- /Variance caveat (see "Law status" above):/ same lossy-@solveOutput@ contract as
-- 'lmapCi' / 'rmapCo' / 'firstSym'. The 'WireCtor's 'wcMatch' is
-- @const Nothing@ — there is no inverse function in general.
-- Forward processing ('Keiki.Core.delta', 'Keiki.Core.omega') is
-- unaffected.
--
-- /Composition limitation (see "Law status" above):/ 'Keiki.Composition.compose' substitutes
-- t2's 'TInpCtorField' against t1's 'WireCtor'-emitted output and
-- demands 'icName ic2 == wcName wc1'. An 'arrTransducer'-produced
-- transducer's 'WireCtor' is named @"arr"@ but the next stage's
-- 'TInpCtorField' uses 'identityInCtor' (named @"Identity"@), so
-- 'arr f >>> arr g' will not produce 'arr (g . f)' through 'Cat..'
-- — substitution turns the composed guard into 'PBot' and the
-- composite never fires. This is documented rather than worked
-- around because the symbolic 'Term' AST has no
-- 'TPure'-style constructor for arbitrary function application
-- (intentional; see 'Keiki.Symbolic.translateTermSym' for why
-- function applications would be untranslatable). Use 'Arr.arr'
-- standalone for adapter purposes; for actual composition, build
-- one transducer that wraps the combined function.
arrTransducer ::
  forall a b.
  (a -> b) ->
  SymTransducer (HsPred '[] a) '[] IdVertex a b
arrTransducer f =
  SymTransducer
    { edgesOut = \IdVertex ->
        [ Edge
            { guard = PInCtor identityInCtor,
              update = UKeep,
              output = [arrOut],
              target = IdVertex
            }
        ],
      initial = IdVertex,
      initialRegs = RNil,
      isFinal = const True
    }
  where
    arrOut :: OutTerm '[] a b
    arrOut =
      OPack
        identityInCtor
        arrWc
        (OFCons (TInpCtorField identityInCtor ZIdx) OFNil)

    arrWc :: WireCtor b (a, ())
    arrWc =
      WireCtor
        { wcName = "arr",
          wcMatch = \_ -> Nothing,
          wcBuild = \(a, ()) -> f a
        }

-- | Standard 'Control.Arrow.Arrow' instance.
--
-- @'Arr.arr' f@ wraps 'arrTransducer' (a stateless one-edge
-- transducer with @'wcBuild' = \\(a, ()) -> f a@). @'Arr.first'@
-- delegates to 'Strong.first''; @'Arr.second'@ delegates to
-- 'Strong.second''. @'Arr.>>>'@ and @'Arr.<<<'@ inherit the
-- 'Cat.Category' instance's runtime overlap check + sentinel
-- short-circuit.
--
-- The default @'***'@ and @'&&&'@ methods of 'Arr.Arrow' use
-- 'Arr.arr', 'Arr.first', and 'Arr.>>>' under the hood; they
-- typecheck and produce composite transducers. The same
-- @icName == wcName@ alignment limitation that affects
-- 'arr f >>> arr g' applies — see 'arrTransducer' for the full
-- caveat.
instance Arr.Arrow SomeSymTransducer where
  arr f =
    SomeSymTransducerWith
      (PoisonProvenance False True)
      (arrTransducer f)
  first = first'
  second = second'

-- * Internal rewriters --------------------------------------------------

-- These walk the closed AST of 'Edge', 'HsPred', 'Update', 'Term',
-- 'OutTerm', 'OutFields', 'InCtor', and 'WireCtor', threading a
-- contramap on @ci@ (or a covariant map on @co@) through every
-- position the type parameter occupies.

-- | Contramap an 'InCtor' over its alphabet. The resulting 'InCtor's
-- 'icBuild' is poisoned: callers must not invoke
-- 'Keiki.Core.solveOutput' on edges built from this 'InCtor'.
contraInCtor :: (ci' -> ci) -> InCtor ci ifs -> InCtor ci' ifs
contraInCtor f InCtor {icName = n, icMatch = m} =
  InCtor
    { icName = n <> "#lmapped",
      icMatch = m . f,
      icBuild = poisonedIcBuild n
    }

-- | Partial-contramap an 'InCtor'. The 'icMatch' becomes
-- @\ci' -> f ci' >>= m@; 'icBuild' is poisoned (same caveat as
-- 'contraInCtor').
contraMaybeInCtor :: (ci' -> Maybe ci) -> InCtor ci ifs -> InCtor ci' ifs
contraMaybeInCtor f InCtor {icName = n, icMatch = m} =
  InCtor
    { icName = n <> "#lmapped",
      icMatch = \ci' -> f ci' >>= m,
      icBuild = poisonedIcBuild n
    }

poisonedIcBuild :: String -> a -> b
poisonedIcBuild icN = \_ ->
  error
    ( "Keiki.Profunctor: icBuild on a contramapped InCtor \""
        <> icN
        <> "\" was invoked. lmapCi/lmapMaybeCi-rewritten transducers \
           \cannot rebuild ci from a wire event via solveOutput. See \
           \the haddock for Keiki.Profunctor.lmapCi."
    )

-- | Covariant map a 'WireCtor' over its alphabet. The resulting
-- 'WireCtor's 'wcMatch' is set to @const Nothing@.
mapWireCtor :: (co -> co') -> WireCtor co fs -> WireCtor co' fs
mapWireCtor g WireCtor {wcName = n, wcBuild = b} =
  WireCtor
    { wcName = n <> "#rmapped",
      wcMatch = \_co' -> Nothing,
      wcBuild = g . b
    }

-- ** Term ---------------------------------------------------------------

contraTerm :: forall ci ci' rs ifs r. (ci' -> ci) -> Term rs ci ifs r -> Term rs ci' ifs r
contraTerm f = go
  where
    go :: forall a. Term rs ci ifs a -> Term rs ci' ifs a
    go (TLit r) = TLit r
    go (TReg ix) = TReg ix
    go (TInpCtorField ic ix) = TInpCtorField (contraInCtor f ic) ix
    go (TApp1 h a) = TApp1 h (go a)
    go (TApp2 h a b) = TApp2 h (go a) (go b)
    go (TArith op a b) = TArith op (go a) (go b)

contraMaybeTerm :: forall ci ci' rs ifs r. (ci' -> Maybe ci) -> Term rs ci ifs r -> Term rs ci' ifs r
contraMaybeTerm f = go
  where
    go :: forall a. Term rs ci ifs a -> Term rs ci' ifs a
    go (TLit r) = TLit r
    go (TReg ix) = TReg ix
    go (TInpCtorField ic ix) = TInpCtorField (contraMaybeInCtor f ic) ix
    go (TApp1 h a) = TApp1 h (go a)
    go (TApp2 h a b) = TApp2 h (go a) (go b)
    go (TArith op a b) = TArith op (go a) (go b)

-- ** HsPred -------------------------------------------------------------

contraPred :: forall ci ci' rs. (ci' -> ci) -> HsPred rs ci -> HsPred rs ci'
contraPred f = go
  where
    go :: HsPred rs ci -> HsPred rs ci'
    go PTop = PTop
    go PBot = PBot
    go (PAnd p q) = PAnd (go p) (go q)
    go (POr p q) = POr (go p) (go q)
    go (PNot p) = PNot (go p)
    go (PEq a b) = PEq (contraTerm f a) (contraTerm f b)
    go (PInCtor ic) = PInCtor (contraInCtor f ic)
    go PLeftArm = PInCtor (mappedArmInCtor (Just . f) True)
    go PRightArm = PInCtor (mappedArmInCtor (Just . f) False)
    go (PCmp op a b) = PCmp op (contraTerm f a) (contraTerm f b)

contraMaybePred :: forall ci ci' rs. (ci' -> Maybe ci) -> HsPred rs ci -> HsPred rs ci'
contraMaybePred f = go
  where
    go :: HsPred rs ci -> HsPred rs ci'
    go PTop = PTop
    go PBot = PBot
    go (PAnd p q) = PAnd (go p) (go q)
    go (POr p q) = POr (go p) (go q)
    go (PNot p) = PNot (go p)
    go (PEq a b) = PEq (contraMaybeTerm f a) (contraMaybeTerm f b)
    go (PInCtor ic) = PInCtor (contraMaybeInCtor f ic)
    go PLeftArm = PInCtor (mappedArmInCtor f True)
    go PRightArm = PInCtor (mappedArmInCtor f False)
    go (PCmp op a b) = PCmp op (contraMaybeTerm f a) (contraMaybeTerm f b)

mappedArmInCtor ::
  (ci' -> Maybe (Either ci1 ci2)) ->
  Bool ->
  InCtor ci' '[]
mappedArmInCtor f wantLeft =
  InCtor
    { icName = if wantLeft then "keiki#leftArm#lmapped" else "keiki#rightArm#lmapped",
      icMatch = \ci' -> case f ci' of
        Just (Left _) | wantLeft -> Just RNil
        Just (Right _) | not wantLeft -> Just RNil
        _ -> Nothing,
      icBuild = poisonedIcBuild (if wantLeft then "keiki#leftArm#lmapped" else "keiki#rightArm#lmapped")
    }

-- ** Update -------------------------------------------------------------

contraUpdate :: forall ci ci' rs w. (ci' -> ci) -> Update rs w ci -> Update rs w ci'
contraUpdate f = go
  where
    go :: forall w'. Update rs w' ci -> Update rs w' ci'
    go UKeep = UKeep
    go (USet ixn term) = USet ixn (contraTerm f term)
    go (UCombine u1 u2) = UCombine (go u1) (go u2)

contraMaybeUpdate :: forall ci ci' rs w. (ci' -> Maybe ci) -> Update rs w ci -> Update rs w ci'
contraMaybeUpdate f = go
  where
    go :: forall w'. Update rs w' ci -> Update rs w' ci'
    go UKeep = UKeep
    go (USet ixn term) = USet ixn (contraMaybeTerm f term)
    go (UCombine u1 u2) = UCombine (go u1) (go u2)

-- ** OutTerm + OutFields -----------------------------------------------

contraOutTerm :: (ci' -> ci) -> OutTerm rs ci co -> OutTerm rs ci' co
contraOutTerm f (OPack ic wc fields) =
  OPack (contraInCtor f ic) wc (contraOutFields f fields)

contraOutFields :: forall ci ci' rs ifs fs. (ci' -> ci) -> OutFields rs ci ifs fs -> OutFields rs ci' ifs fs
contraOutFields f = go
  where
    go :: forall fs'. OutFields rs ci ifs fs' -> OutFields rs ci' ifs fs'
    go OFNil = OFNil
    go (OFCons t fs) = OFCons (contraTerm f t) (go fs)

contraMaybeOutTerm :: (ci' -> Maybe ci) -> OutTerm rs ci co -> OutTerm rs ci' co
contraMaybeOutTerm f (OPack ic wc fields) =
  OPack (contraMaybeInCtor f ic) wc (contraMaybeOutFields f fields)

contraMaybeOutFields :: forall ci ci' rs ifs fs. (ci' -> Maybe ci) -> OutFields rs ci ifs fs -> OutFields rs ci' ifs fs
contraMaybeOutFields f = go
  where
    go :: forall fs'. OutFields rs ci ifs fs' -> OutFields rs ci' ifs fs'
    go OFNil = OFNil
    go (OFCons t fs) = OFCons (contraMaybeTerm f t) (go fs)

-- | Covariant map of a single OPack over its co alphabet.
mapOutTermCo :: (co -> co') -> OutTerm rs ci co -> OutTerm rs ci co'
mapOutTermCo g (OPack ic wc fields) =
  OPack ic (mapWireCtor g wc) fields

-- ** Edge ---------------------------------------------------------------

rewriteEdge :: (ci' -> ci) -> Edge (HsPred rs ci) rs ci co s -> Edge (HsPred rs ci') rs ci' co s
rewriteEdge f Edge {guard = g, update = u, output = mo, target = tgt} =
  Edge
    { guard = contraPred f g,
      update = contraUpdate f u,
      output = fmap (contraOutTerm f) mo,
      target = tgt
    }

rewriteEdgeMaybe ::
  (ci' -> Maybe ci) ->
  Edge (HsPred rs ci) rs ci co s ->
  Edge (HsPred rs ci') rs ci' co s
rewriteEdgeMaybe f Edge {guard = g, update = u, output = mo, target = tgt} =
  Edge
    { guard = contraMaybePred f g,
      update = contraMaybeUpdate f u,
      output = fmap (contraMaybeOutTerm f) mo,
      target = tgt
    }

rewriteEdgeOut ::
  (co -> co') ->
  Edge (HsPred rs ci) rs ci co s ->
  Edge (HsPred rs ci) rs ci co' s
rewriteEdgeOut g Edge {guard = guardP, update = u, output = mo, target = tgt} =
  Edge
    { guard = guardP,
      update = u,
      output = fmap (mapOutTermCo g) mo,
      target = tgt
    }
