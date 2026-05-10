---
id: 28
slug: category-instance-on-the-symtransducer-wrapper
title: "Category instance on the SymTransducer wrapper"
kind: exec-plan
created_at: 2026-05-03T03:16:28Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/9-profunctor-and-category-instances-on-symtransducer.md"
---

# Category instance on the SymTransducer wrapper

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this plan ships, a keiki user can write

    import Control.Category ((.), id)
    import Prelude hiding ((.), id)

    -- A SymTransducer that consumes EmailCmd, emits an intermediate
    -- IntermediateEvent, then is post-composed with a second
    -- transducer that consumes IntermediateEvent and emits FinalEvent.
    pipeline :: SomeSymTransducer EmailCmd FinalEvent
    pipeline = secondTransducer . firstTransducer

    -- Identity at any alphabet:
    passThrough :: SomeSymTransducer EmailCmd EmailCmd
    passThrough = id

The two operators `(.)` and `id` from `Control.Category` are now
defined for `SomeSymTransducer` (the existential wrapper introduced
by `docs/plans/27-existential-wrapper-for-symtransducer-plus-profunctor-instance-and-variance-combinators.md`),
delegating to the existing `Keiki.Composition.compose` for `(.)` and
to a newly-defined identity transducer for `id`.

The `id` transducer is a one-vertex `SymTransducer` whose single edge
emits its current input as its output via a structural `OPack`. It
works for any alphabet `a` without per-type type-class machinery
(see Decision Log: a phantom one-slot register file lets the
`InCtor` and `WireCtor` machinery roundtrip any value generically).

The user-visible deliverable is verified by:

    cabal test keiki-test --test-show-details=direct

passing the new `Keiki.Profunctor (Category)` describe block, which
asserts the Category laws up to state-isomorphism on a representative
fixture (the existing `Keiki.Examples.EmailDelivery` aggregate
composed with itself via the wrapper).


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M0 (2026-05-09): Verified EP-27 shipped (`data SomeSymTransducer` and `someSymTransducer` present in `src/Keiki/Profunctor.hs`); `cabal build all` succeeds (GHC 9.12.3); `cabal test keiki-test --test-show-details=direct` reports **146 examples, 0 failures**; baseline recorded in Surprises &amp; Discoveries
- [x] M1 (2026-05-09): Settled disjointness via Option (A) — runtime overlap check + `unsafeCoerce`-fabricated `DictDisjoint`; documented in Decision Log. Also added a sibling `DictWrapper` / `unsafeCoerceWrapperDict` for `(WeakenR (Append rs1 rs2), KnownSlotNames (Append rs1 rs2))` since closure under `Append` is true but not provable from skolem `rs1`/`rs2`.
- [x] M1 (2026-05-09): Defined `IdVertex`, `identityInCtor` (private), `identityWireCtor` (private), `identityTransducer` (exported) in `Keiki.Profunctor`. The phantom `'[("payload", a)]` slot list lets a single definition serve every alphabet `a` without per-type machinery. Skipped a `NoThunks IdVertex` instance — `Keiki.NoThunks` ships only `RegFile` instances, mirroring how `EmailVertex` and `PingVertex` get away with no `NoThunks` instance today.
- [x] M1 (2026-05-09): Added private `CategoryOverlapError`, `DictDisjoint`, `unsafeCoerceDisjointness`, `DictWrapper`, `unsafeCoerceWrapperDict`, plus the `composeWrappers` helper that the (still-unwritten in this task entry but actually shipped below) `Cat..` instance method delegates to.
- [ ] M2: Add `Category SomeSymTransducer` instance to `Keiki.Profunctor`
- [ ] M2: Write `test/Keiki/CategorySpec.hs` covering Category laws up to state-isomorphism
- [ ] M2: Register the test module in `keiki.cabal` and `test/Spec.hs`
- [ ] M2: Run `cabal test keiki-test`, capture transcript, mark milestones complete in MP-9
- [ ] M2: Update MP-9 Exec-Plan Registry — set this EP to Complete; check off Progress entries


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- 2026-05-03 / authoring: `Keiki.Composition.compose` requires
  `Disjoint (Names rs1) (Names rs2)` where the `Disjoint` type family
  in `src/Keiki/Internal/Slots.hs` enforces *static* slot-name
  disjointness. The wrapper `SomeSymTransducer ci co` hides `rs`,
  so for the Category instance's general `(.)` GHC has *no visibility*
  into whether the two transducers' slot lists are actually disjoint.
  The constraint cannot be discharged statically when both sides are
  existentially packed. M1 owns the resolution. The narrow case of
  `id . t` and `t . id` is fine because `id`'s slot list is `'[]`
  and `Disjoint '[] _` reduces to `()` (and `Disjoint xs '[]` reduces
  by walking `xs` against `'[]`-membership which is also trivially
  true). So Category laws are typeable; only general composition
  needs the M1 escape hatch.

- 2026-05-09 / M0 baseline: `cabal build all` succeeds on GHC 9.12.3.
  `cabal test keiki-test --test-show-details=direct` reports
  `146 examples, 0 failures`. The EP-27 surface
  (`data SomeSymTransducer`, `someSymTransducer`,
  `lmapCi`/`rmapCo`/`dimapTransducer`/`lmapMaybeCi`, the `Profunctor`
  and `Functor` instances) is present in `src/Keiki/Profunctor.hs`
  and exercised by `test/Keiki/ProfunctorSpec.hs` (the
  `Keiki.Profunctor (EP-27)` describe block in `test/Spec.hs`).
  M0 prerequisites satisfied.

- 2026-05-03 / authoring: An identity transducer for an *arbitrary*
  alphabet `a` does not require per-type `Generic`-derived machinery.
  A single-slot phantom register file `'[("payload", a)]` lets us
  define a generic `InCtor a '[("payload", a)]` whose `icMatch`
  packs `a` into the register file and `icBuild` unpacks it. The
  matching `WireCtor a (a, ())` does the same on the wire side. The
  `OPack` structure `OPack idIn idWc (TInpCtorField idIn ZIdx *: oNil)`
  evaluates to the input alphabet's value at every step. The
  identity transducer's *real* register file (the one stored in
  `initialRegs`) remains `RNil` — the phantom slot exists only inside
  the InCtor/WireCtor's wrapping types so the field-tuple math works.
  This eliminates MP-9's IP-3 concern about needing `Generic`-driven
  identity construction. The plan's IP-3 entry should be updated to
  record the phantom-slot resolution.


## Decision Log

Record every decision made while working on the plan.

- Decision: Identity transducer uses a phantom one-slot register
  file `'[("payload", a)]` carried inside the `InCtor`/`WireCtor`,
  *not* a real entry in `initialRegs` (which stays `RNil`).
  Rationale: The phantom slot exists only at the type level for
  field-tuple wiring; no value is ever placed into a real register.
  This makes the identity transducer fully generic in `a` without
  per-type instances, which is what `Category.id`'s
  unconstrained-`a` signature requires.
  Date: 2026-05-03

- Decision: Disjointness in `Cat..` is resolved via **Option (A)**:
  a value-level slot-name overlap check followed by an
  `unsafeCoerce`-fabricated `DictDisjoint` evidence pattern. On
  overlap the operator raises `CategoryOverlapError` carrying the
  colliding slot names. The exception type is exported so users can
  catch it.
  Rationale: Option (A) is the only one of the three candidates
  considered (runtime check, slot renaming, parallel
  `composeUnchecked`) that *catches* an overlap with a clear error
  rather than silently producing a broken composite. It matches
  EP-18's posture for `UCombine` (trust the unsafe path inside
  trusted infrastructure code, with a documented precondition lifted
  to a runtime invariant). It avoids a `Keiki.Composition` refactor.
  Future improvement: a slot-renaming approach (Option B refined
  with proper `KnownSymbol` instance manufacture) would push the
  check back to compile time.
  Date: 2026-05-09

- Decision: The `SomeSymTransducer` wrapper's existential constraint
  set is amended from `()` (no constraints — EP-27 actually shipped
  with no packed constraints, despite MP-9 IP-1's claim that it
  shipped `WeakenR rs`) to `(WeakenR rs, KnownSlotNames rs)`.
  Rationale: `WeakenR rs` is required when the wrapper's
  `Cat..` calls `compose` (which has `WeakenR rs1` as a constraint).
  `KnownSlotNames rs` is required so the runtime overlap check can
  read each transducer's slot names at the value level via
  `slotNames @rs`. Both constraints are structural — every concrete
  `[Slot]` has automatic instances — so the amendment is
  backward-compatible at every existing call site (the existing
  `Profunctor`/`Functor`/`someSymTransducer` use sites all hold a
  concrete `rs` whose instances are already in scope).
  Date: 2026-05-09

- Decision: Add a parallel `DictWrapper` / `unsafeCoerceWrapperDict`
  pair alongside the disjointness one to fabricate
  `(WeakenR (Append rs1 rs2), KnownSlotNames (Append rs1 rs2))` at
  the wrap-back step.
  Rationale: After `compose t1 t2 :: SymTransducer ... (Append rs1
  rs2) ...`, re-wrapping into `SomeSymTransducer` requires both
  classes hold for `Append rs1 rs2`. Both classes have structural
  instances per spine, but GHC cannot reduce `Append rs1 rs2` when
  `rs1` is a skolem. The closure under `Append` is true (provable
  by induction on `rs1`'s spine if we had a value-level witness),
  so the `unsafeCoerce` fabrication is sound. Same posture as the
  disjointness fabrication.
  Date: 2026-05-09

- Decision: Expose `slotNames` from `Keiki.Core` (changed `, KnownSlotNames`
  to `, KnownSlotNames (..)` in the export list) so `Keiki.Profunctor`
  can call `slotNames @rs` at the value level.
  Rationale: `KnownSlotNames` was already exported as an opaque
  class; only its `slotNames` method was hidden. Exposing the method
  is purely additive — every user that already had the class in
  scope gains the method too. No downstream impact.
  Date: 2026-05-09


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This plan extends `Keiki.Profunctor` (the module created by
`docs/plans/27-existential-wrapper-for-symtransducer-plus-profunctor-instance-and-variance-combinators.md`)
with an instance of `Control.Category.Category`. Read EP-27's
"Context and Orientation" section first if you do not have keiki
context — it explains `SymTransducer`, `Edge`, `InCtor`, `WireCtor`,
`OPack`, the variance situation, and the test layout. The summary
below names only the additional concepts this plan needs.

### Existing surface this plan depends on

After EP-27 ships, `src/Keiki/Profunctor.hs` exports:

    data SomeSymTransducer ci co where
      SomeSymTransducer
        :: SymTransducer (HsPred rs ci) rs s ci co
        -> SomeSymTransducer ci co

    someSymTransducer
      :: SymTransducer (HsPred rs ci) rs s ci co
      -> SomeSymTransducer ci co

This plan adds members to that same module. Do not create a new
module; the MasterPlan's IP-2 explicitly names `Keiki.Profunctor`
as the home for *all* typeclass instances introduced under MP-9.

### `Keiki.Composition.compose`

The composition operator we delegate to. Its signature (from
`src/Keiki/Composition.hs`):

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

Three observations relevant to this plan:

1.  The result vertex is `Composite s1 s2` (a strict pair newtype
    defined alongside `compose`). The Category laws hold "up to
    state isomorphism" — `((), s) ≅ s` and `(s, ()) ≅ s` — but the
    *Haskell* types `Composite IdVertex s` and `s` are distinct.
    The wrapper hides the vertex parameter, so the wrapper-level
    type signature `SomeSymTransducer a b` is the *same* before
    and after composing with `id`; that is what makes the Category
    laws statable.

2.  The `WeakenR rs1` constraint has structural instances in
    `Keiki.Composition` for any `rs1`. M1's wrapper has a hidden
    `WeakenR rs` for each packed transducer; the Category instance
    needs to bring it back into scope when calling `compose`.

3.  The `Disjoint` constraint comes from `src/Keiki/Internal/Slots.hs`
    line 66:

        type family Disjoint (xs :: [Symbol]) (ys :: [Symbol]) :: Constraint where
          Disjoint '[]       _  = ()
          Disjoint (x ': xs) ys = (NotMember x ys, Disjoint xs ys)

    `Disjoint '[] _ = ()` and `Disjoint xs '[]` reduces (by walking
    `xs` against `'[]`-membership) to `()`. So both sides of the
    Category-law identity-composition typecheck without trickery —
    only the general `(.)` between two non-`'[]` register files
    needs M1's resolution.

### `OPack` and `OutFields`

Recap from `src/Keiki/Core.hs` lines 380-393. To define the identity
transducer, we need an `OPack` whose structural reads recover the
input value:

    data OutTerm (rs :: [Slot]) (ci :: Type) (co :: Type) where
      OPack :: InCtor ci ifs
            -> WireCtor co fields
            -> OutFields rs ci fields
            -> OutTerm rs ci co

    data WireCtor co fields = WireCtor
      { wcName  :: String
      , wcMatch :: co -> Maybe fields
      , wcBuild :: fields -> co
      }

    data InCtor ci (ifs :: [Slot]) where
      InCtor
        :: (AssembleRegFile ifs, KnownSlotNames ifs)
        => { icName  :: String
           , icMatch :: ci -> Maybe (RegFile ifs)
           , icBuild :: RegFile ifs -> ci
           }
        -> InCtor ci ifs

    data OutFields rs ci fs where
      OFNil  :: OutFields rs ci ()
      OFCons :: Term rs ci f
             -> OutFields rs ci fs
             -> OutFields rs ci (f, fs)

The constraints `AssembleRegFile ifs` and `KnownSlotNames ifs` on
`InCtor` are satisfied by any `[Slot]` whose elements are
`(KnownSymbol s, t)` pairs (no constraints on `t`); see the
`AssembleRegFile '[]` and `AssembleRegFile ('(s, r) ': rs)` instances
in `Keiki.Core`. So `InCtor a '[("payload", a)]` typechecks for any
`a` (the `KnownSymbol "payload"` constraint is free).

`Term rs ci r` reads input via:

    TInpCtorField :: InCtor ci ifs -> Index ifs r -> Term rs ci r

The `Index ifs r` pointer for the head slot is `ZIdx :: Index ('(s,
r) ': rs) r` (defined in `Keiki.Core` lines 132-140). So:

    TInpCtorField identityInCtor ZIdx :: Term rs a a

evaluates to the value of the input's "payload" slot — i.e. the
input itself.

### What `id`'s identity step looks like operationally

The identity transducer has one vertex (an enum `IdVertex` with a
single nullary constructor), one edge from `IdVertex` back to
`IdVertex`, with:

- `guard = PTop` (always fires)
- `update = UKeep` (no register writes)
- `output = Just (OPack identityInCtor identityWireCtor (
    TInpCtorField identityInCtor ZIdx *: oNil ))`
- `target = IdVertex`

Forward processing on input `a` evaluates the OutFields by reading
the `"payload"` slot via the InCtor (which roundtrips `a` through
the phantom register file), then `wcBuild :: (a, ()) -> a` unwraps
the field tuple to produce `a`. Inversion via `solveOutput` does
the opposite: reads the wire `a`, calls `wcMatch` to get `(a, ())`,
walks the `OutFields` to produce `(ZIdx ↦ a)`, calls `assemble` to
get `RCons (Proxy @"payload") a RNil`, then `icBuild` to recover the
original `a`. Both directions roundtrip cleanly — the identity
transducer satisfies the keiki guarantees by construction.

### `IdVertex`'s required derivations

`isSingleValuedSym` (from `Keiki.Symbolic`) requires `Bounded s,
Enum s` on the vertex. `checkHiddenInputs` (from `Keiki.Core`)
requires `Bounded s, Enum s, Show s`. The `Composite s1 s2` enum
math relies on `Bounded`/`Enum` from both halves. `IdVertex` therefore
needs:

    data IdVertex = IdVertex
      deriving stock (Eq, Show, Bounded, Enum)

(GHC2024 + DerivingStrategies handles this; both are already on in
`keiki.cabal`'s `shared-extensions`.)

A `NoThunks` instance is also required because `Keiki.NoThunks`
ships instances for `SymTransducer` and walks the vertex. The
single-constructor enum is trivially thunk-free; a stock
`Generic`-derived `NoThunks` works (mirror what
`Keiki.Examples.EmailDelivery`'s `EmailVertex` does).


## Plan of Work

The work decomposes into two milestones — M0 (prereqs), M1 (identity
transducer + disjointness escape hatch), M2 (Category instance + tests).

### M0 — Verify prerequisites

Scope: confirm EP-27 (`docs/plans/27-...`) has shipped (so
`Keiki.Profunctor`, `SomeSymTransducer`, and `someSymTransducer`
exist) and the test suite is green.

What will exist at the end: a recorded baseline (test count,
build success) in this plan's Surprises & Discoveries section.

Commands to run from `/Users/shinzui/Keikaku/bokuno/keiki/`:

    cabal build all
    cabal test keiki-test --test-show-details=direct 2>&1 | tail -30

Acceptance: both succeed; the test count includes the
`Keiki.Profunctor` describe block (from EP-27). If
`SomeSymTransducer` is not yet defined, this plan blocks until
EP-27 ships.

Verify EP-27 deliverables exist:

    grep -n "data SomeSymTransducer\|^someSymTransducer" src/Keiki/Profunctor.hs

Expected output: at least three matches.

### M1 — Identity transducer and disjointness escape hatch

Scope: settle the disjointness-resolution decision, then add the
identity transducer plus an internal helper that lets the Category
instance in M2 call `compose` with two existentially-packed register
files.

**Decision — disjointness resolution.** Three candidate approaches:

Option (A): **runtime-checked unsafe coerce.** The Category
instance's `(.)` extracts both inner transducers (which carry
`KnownSlotNames` and the slot-name strings via the `Names`/`KnownSymbol`
chain), reads the slot-name lists at the value level, checks for
overlap, and either:

- on success, calls `compose` after `unsafeCoerce`-discharging the
  `Disjoint` type-family constraint;
- on overlap, raises a `KeikiCategoryOverlapError` exception (a
  hand-written exception type) at evaluation time.

Pros: matches keiki's existing posture (the `EP-18` Decision Log
entry for `compose`'s use of raw `UCombine` over the type-checked
`combine` documents the same pattern: trust the unsafe path when
the surrounding context certifies the invariant). Caught at the
first call to `(.)`, not delayed.

Cons: requires `unsafeCoerce` and an exception machinery. The
constraint is "safety-critical" — a missed overlap silently produces
a wrong transducer.

Option (B): **wrapper-level slot renaming.** Before calling
`compose`, walk the second transducer and rewrite every slot
name to a fresh symbol (using a `Symbol`-level naming scheme like
"a_<n>" / "b_<n>"). Slots are referenced by `Index` and `IndexN`,
both of which carry a `KnownSymbol` constraint that needs to
re-resolve to the new symbol — but `Symbol` is a closed type-level
construct in GHC; you cannot mint a *new* symbol at runtime that
satisfies `KnownSymbol`. The renaming therefore requires
`unsafeCoerce` of the slot-name string into a `KnownSymbol`-claiming
type — which is even less safe than (A).

Cons: more complex, no real safety improvement over (A).

Option (C): **avoid the `Disjoint` constraint via a parallel
`composeUnchecked`.** Refactor `Keiki.Composition` to expose a
`composeUnchecked` that drops the `Disjoint` constraint (just like
`UCombine` is the unchecked variant of `combine`) and have the
Category instance call it directly without runtime checks. The
existing `compose` keeps the static check for direct call sites.

Pros: no `unsafeCoerce` in user-facing code; safety story is
"if you use the wrapper Category, you take responsibility for
disjointness; if you call compose directly, GHC checks it for you".

Cons: another helper to maintain in `Keiki.Composition`. Loses
the safety net entirely (no overlap detection, even at runtime).

**Recommendation:** Option (A). Reasons:

1.  It is the only option that *catches* an overlap (at runtime,
    via a clear exception). (B) and (C) silently miss it.

2.  It is consistent with EP-18's posture for `UCombine`: trust
    the unsafe path inside trusted infrastructure code (here, the
    Category instance), with documented preconditions. The
    runtime check lifts the precondition to a runtime invariant.

3.  No refactor of `Keiki.Composition` required.

The Decision Log entry must record the chosen option and the
rationale, plus a future-improvements note pointing at slot
renaming (Option B refined) as the eventual safe resolution.

**Identity transducer.** After the decision, add to
`src/Keiki/Profunctor.hs`:

    -- | One-vertex enum used by the identity transducer.
    data IdVertex = IdVertex
      deriving stock (Eq, Show, Bounded, Enum, Generic)

    -- | NoThunks instance for IdVertex; the constructor is nullary.
    instance NoThunks IdVertex

    -- | A 'WireCtor' for an arbitrary alphabet @a@ that uses a
    -- single-field tuple @(a, ())@ to wrap and unwrap any value.
    -- Used only as the structural skeleton for 'identityTransducer's
    -- 'OPack'; never inspected by user code.
    identityWireCtor :: WireCtor a (a, ())
    identityWireCtor = WireCtor
      { wcName  = "Identity"
      , wcMatch = \a -> Just (a, ())
      , wcBuild = \(a, ()) -> a
      }

    -- | An 'InCtor' for an arbitrary alphabet @a@ that uses a phantom
    -- one-slot register file to wrap and unwrap any value.
    identityInCtor :: InCtor a '[ '("payload", a) ]
    identityInCtor = InCtor
      { icName  = "Identity"
      , icMatch = \a -> Just (RCons (Proxy @"payload") a RNil)
      , icBuild = \(RCons _ a RNil) -> a
      }

    -- | The identity transducer for an arbitrary alphabet @a@. One
    -- vertex; one edge that emits its input as its output.
    identityTransducer
      :: forall a.
         SymTransducer (HsPred '[] a) '[] IdVertex a a
    identityTransducer = SymTransducer
      { edgesOut    = \IdVertex ->
          [ Edge { guard  = PTop
                 , update = UKeep
                 , output = Just identityOutTerm
                 , target = IdVertex
                 }
          ]
      , initial     = IdVertex
      , initialRegs = RNil
      , isFinal     = const True
      }
      where
        identityOutTerm :: OutTerm '[] a a
        identityOutTerm =
          OPack identityInCtor identityWireCtor
                ( OFCons (TInpCtorField identityInCtor ZIdx) OFNil )

The imports needed (added to the `Keiki.Profunctor` import list):

- `Data.Proxy (Proxy (..))` — for `Proxy @"payload"`.
- `GHC.Generics (Generic)` — for `IdVertex`'s `deriving stock`.
- `NoThunks.Class (NoThunks)` — for `IdVertex`'s instance.
- The `Keiki.Core` re-exports already cover `RegFile`, `Edge`,
  `Update`, `HsPred`, `InCtor`, `WireCtor`, `OutFields`, `OutTerm`,
  `Term`, `SymTransducer`, `RCons`, `RNil`, `ZIdx`, `OFCons`,
  `OFNil`, `PTop`, `UKeep`, `TInpCtorField`.

**Disjointness escape hatch.** Add (private; do not export):

    {-# LANGUAGE AllowAmbiguousTypes #-}

    import Data.Typeable (Typeable, typeRep)
    import Unsafe.Coerce (unsafeCoerce)
    import Control.Exception (Exception, throw)

    -- | Exception raised when 'Category.(.)' is invoked on two
    -- 'SomeSymTransducer's whose underlying register files share a
    -- slot name.
    data CategoryOverlapError = CategoryOverlapError
      { coeSlots :: [String]
      } deriving (Show)

    instance Exception CategoryOverlapError

    -- | Unsafe witness that two 'KnownSlotNames' lists are 'Disjoint'.
    -- Use only after a value-level check confirms the lists are
    -- disjoint. Smuggles a 'Dict (Disjoint (Names rs1) (Names rs2))'
    -- into scope via 'unsafeCoerce' on a known-disjoint witness
    -- (the trivially-true @Disjoint '[] '[]@).
    --
    -- The runtime check at the call site is the *only* safety net;
    -- if you call this without checking, you can produce
    -- semantically-broken transducers.
    data DictDisjoint xs ys where
      DictDisjoint :: Disjoint xs ys => DictDisjoint xs ys

    unsafeCoerceDisjointness
      :: forall xs ys.
         DictDisjoint xs ys
    unsafeCoerceDisjointness =
      unsafeCoerce (DictDisjoint @'[] @'[])

The implementation pattern is the standard `Dict`-and-`unsafeCoerce`
approach for fabricating constraint evidence; see e.g. the
`reflection` package's `Reified` machinery.

Note: this requires `KnownSlotNames` (already in `Keiki.Core`) on
each packed transducer so we can read the slot-name strings at the
value level. EP-27's wrapper does *not* currently require
`KnownSlotNames rs` as a packed constraint. M1 must *amend EP-27's
wrapper* to pack the constraint:

    data SomeSymTransducer ci co where
      SomeSymTransducer
        :: ( WeakenR rs
           , KnownSlotNames rs
           )
        => SymTransducer (HsPred rs ci) rs s ci co
        -> SomeSymTransducer ci co

This change is small and backward-compatible at the use-site (any
real `SymTransducer` with a `Slot`-shaped `rs` already satisfies
both constraints — `WeakenR` has structural instances for any
`rs`, and `KnownSlotNames` is satisfied whenever every slot has a
`KnownSymbol` name, which is universally true for keiki transducers).

The amendment is recorded in M1's Decision Log here and propagated
back to EP-27 by an inline note ("EP-28 amended EP-27's wrapper to
also pack `KnownSlotNames rs`; see EP-28 M1 Decision Log").

What will exist at the end of M1:

- The disjointness Decision Log entry recording Option (A) and
  rationale.
- `IdVertex`, `identityInCtor`, `identityWireCtor`, and
  `identityTransducer` defined and exported from
  `Keiki.Profunctor`.
- The internal `unsafeCoerceDisjointness` and `CategoryOverlapError`
  helpers in the same module (private — not exported).
- The wrapper newtype amended to pack `KnownSlotNames rs`.

Acceptance: `cabal build all` succeeds. `grep -n "identityTransducer\|IdVertex" src/Keiki/Profunctor.hs` returns the new definitions. The amendment to EP-27's wrapper is reflected in the file.

### M2 — Category instance + Category-laws test

Scope: add the `Category SomeSymTransducer` instance, write the
test that asserts the laws, and integrate.

What will exist at the end:

1.  In `src/Keiki/Profunctor.hs`:

        import qualified Control.Category as Cat

        instance Cat.Category SomeSymTransducer where
          id = SomeSymTransducer identityTransducer

          SomeSymTransducer t2 . SomeSymTransducer t1 =
            let names1 = slotNamesOf t1
                names2 = slotNamesOf t2
                overlap = filter (`elem` names2) names1
            in if not (null overlap)
                 then throw (CategoryOverlapError overlap)
                 else case unsafeCoerceDisjointness of
                   (DictDisjoint :: DictDisjoint (Names rs1) (Names rs2)) ->
                     SomeSymTransducer (compose t1 t2)

    (Where `slotNamesOf :: KnownSlotNames rs => SymTransducer (HsPred
    rs ci) rs s ci co -> [String]` is a tiny helper that calls
    `Keiki.Core.knownSlotNames @rs`. The exact accessor needs
    confirmation — `KnownSlotNames` exposes a `slotNames` method
    or similar; check `Keiki.Core` line ~249 and use whatever
    accessor exists.)

    The `Prelude.id` and `Prelude.(.)` are masked by the import; users
    must `import Prelude hiding ((.), id)` and `import Control.Category`
    to use the instance. This is the standard `Control.Category` idiom.

2.  In `test/Keiki/CategorySpec.hs`:

    A new spec file that:

    a.  Imports `Keiki.Profunctor`, `Keiki.Examples.EmailDelivery`,
        `Control.Category`, and Hspec.

    b.  Defines a fixture: `someEmail = someSymTransducer
        emailDelivery :: SomeSymTransducer EmailCmd EmailEvent`.

    c.  Defines a small second transducer `emailLogger ::
        SomeSymTransducer EmailEvent ()` that consumes EmailEvent
        and emits `()`. (Define inline; the slot-name disjointness
        is satisfied by giving its register file slot names that
        do not collide with EmailDelivery's `emailRecipient` /
        `emailSubject` / `emailSentAt` slots — pick e.g.
        `loggerCount`.)

    d.  Asserts:

        - **Law L1 (left identity):** `id Cat.. someEmail` produces
          a wrapper whose underlying transducer behaves identically
          to `someEmail` on a representative input. Verify by
          running both through a small forward-evaluation harness
          (or, more directly: pull both transducers' first edges and
          assert their guards/outputs evaluate the same on a sample
          `RegFile` and `EmailCmd`). State-isomorphism means the
          Haskell types are not equal; behaviour is.

        - **Law L2 (right identity):** Same but for `someEmail Cat..
          id`. Same assertion shape.

        - **Law L3 (associativity):** Compose three transducers two
          ways: `(t3 Cat.. t2) Cat.. t1` and `t3 Cat.. (t2 Cat.. t1)`.
          Assert the forward behaviours match. (Use three transducers
          with disjoint slot lists — e.g. EmailDelivery,
          `emailLogger`, and a third inline `emailRedactor`
          consuming `()` and emitting `()`.)

        - **Overlap exception:** Build two `SomeSymTransducer`s
          whose register files share a slot name (e.g. EmailDelivery
          composed with EmailDelivery itself, since both have the
          same slots). Assert that `Cat.. ` raises
          `CategoryOverlapError` when *evaluated* (use Hspec's
          `shouldThrow` matcher).

        - **`isSingleValuedSym` survives `id Cat.. t`:** Pull the
          composite out, run `isSingleValuedSym`, assert `True`.

3.  `keiki.cabal`'s test-suite `other-modules` lists
    `Keiki.CategorySpec` (insertion alphabetically near
    `Keiki.CompositionSpec`).

4.  `test/Spec.hs` imports `Keiki.CategorySpec` qualified and adds
    `describe "Keiki.Profunctor (Category)" Keiki.CategorySpec.spec`
    in `main`.

5.  Update `docs/masterplans/9-profunctor-and-category-instances-on-symtransducer.md`:

    - Mark the EP-28 milestones in Progress as complete.
    - Set EP-28's status in the Exec-Plan Registry to `Complete`.
    - Add a Surprises & Discoveries entry referencing the phantom-
      slot identity-transducer technique (so EP-29 / future plans
      know about it).
    - Update IP-3 ("Identity transducer") to record that the
      `Generic`-vs-explicit-instance trade-off was resolved by the
      phantom-slot technique — neither was needed.

Acceptance for M2: `cabal test keiki-test --test-show-details=direct`
succeeds with the new `Keiki.Profunctor (Category)` describe block
green. The test count is at least 5 higher than the M0 baseline
(L1, L2, L3, overlap, single-valued).


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki/`. Update
this section as you progress.

### M0 commands

    cabal build all
    cabal test keiki-test --test-show-details=direct 2>&1 | tail -30
    grep -n "data SomeSymTransducer\|^someSymTransducer" src/Keiki/Profunctor.hs

Record `N examples, 0 failures` from the test summary in Surprises
& Discoveries before continuing.

### M1 edits

1.  Edit `src/Keiki/Profunctor.hs`:

    - Amend the wrapper newtype declaration to add the
      `KnownSlotNames rs` constraint to the existential.
    - Add the imports listed in the M1 plan-of-work.
    - Add `IdVertex`, `identityInCtor`, `identityWireCtor`,
      `identityTransducer`, `CategoryOverlapError`, `DictDisjoint`,
      and `unsafeCoerceDisjointness` definitions.
    - Update the module's export list to also export
      `identityTransducer` and `IdVertex` (private helpers stay
      hidden).
    - Update the module haddock to mention the Category preview
      and Decision (A) re: disjointness.

2.  Verify M1:

        cabal build all

    Expected: success, possibly with a warning about
    `unsafeCoerceDisjointness` (some GHCs warn on `unsafeCoerce`
    of constraint dictionaries; if so, add a localized
    `{-# OPTIONS_GHC -Wno-... -#}` pragma and document why).

3.  Commit M1:

        git commit -m "$(cat <<'EOF'
        feat(profunctor): EP-28 M1 — identity transducer + disjointness escape hatch

        Add IdVertex, identityInCtor, identityWireCtor, identityTransducer
        for Category.id support. Add private unsafeCoerceDisjointness +
        CategoryOverlapError helpers used by the (still-unwritten)
        Category instance to discharge Disjoint at the wrapper boundary
        with a runtime overlap check.

        Amend EP-27's SomeSymTransducer wrapper to pack KnownSlotNames rs
        so the runtime overlap check has access to the slot names.

        MasterPlan: docs/masterplans/9-profunctor-and-category-instances-on-symtransducer.md
        ExecPlan: docs/plans/28-category-instance-on-the-symtransducer-wrapper.md
        Intention: intention_01knjzws4qezz9w8b0743zfqv8
        EOF
        )"

### M2 edits

1.  Add the `Category SomeSymTransducer` instance to
    `src/Keiki/Profunctor.hs` per the M2 plan-of-work. Re-verify
    `cabal build all` succeeds.

2.  Create `test/Keiki/CategorySpec.hs`. Use
    `test/Keiki/CompositionAlternativeSpec.hs` as a template for
    the spec module structure (imports, fixture-building style).

3.  Edit `keiki.cabal` to register `Keiki.CategorySpec` in the
    test-suite's `other-modules`.

4.  Edit `test/Spec.hs` to import `Keiki.CategorySpec` qualified
    and add the `describe` line.

5.  Verify M2:

        cabal test keiki-test --test-show-details=direct 2>&1 | tail -50

    Expected output: a `Keiki.Profunctor (Category)` describe
    block with at least five "it ..." lines, all green.

6.  Update `docs/masterplans/9-profunctor-and-category-instances-on-symtransducer.md`
    per the M2 plan-of-work.

7.  Commit M2:

        git commit -m "$(cat <<'EOF'
        feat(profunctor): EP-28 M2 — Category instance + laws spec

        Add Control.Category.Category SomeSymTransducer instance
        delegating to identityTransducer for `id` and to
        Keiki.Composition.compose for `(.)`. The (.) operator
        runtime-checks slot-name disjointness and raises
        CategoryOverlapError on overlap.

        Add test/Keiki/CategorySpec.hs covering left identity,
        right identity, associativity, the overlap exception, and
        survival of isSingleValuedSym across `id . t`.

        MasterPlan: docs/masterplans/9-profunctor-and-category-instances-on-symtransducer.md
        ExecPlan: docs/plans/28-category-instance-on-the-symtransducer-wrapper.md
        Intention: intention_01knjzws4qezz9w8b0743zfqv8
        EOF
        )"


## Validation and Acceptance

The user-visible success criterion is:

    cabal test keiki-test --test-show-details=direct

passes with the new `Keiki.Profunctor (Category)` describe block
green (five or more assertions: L1, L2, L3, overlap, single-valued
survival).

A secondary, more demonstrative validation: in `cabal repl keiki` a
user can type:

    > import Keiki.Profunctor
    > import Keiki.Examples.EmailDelivery
    > import qualified Control.Category as Cat

    > :type Cat.id :: SomeSymTransducer EmailCmd EmailCmd
    Cat.id :: SomeSymTransducer EmailCmd EmailCmd :: SomeSymTransducer EmailCmd EmailCmd

    > let t = someSymTransducer emailDelivery :: SomeSymTransducer EmailCmd EmailEvent
    > :type Cat.id Cat.. t
    Cat.id Cat.. t :: SomeSymTransducer EmailCmd EmailEvent

and, if the user composes two transducers with overlapping slots:

    > let collide = t Cat.. ( ... overlapping fixture ... )
    > collide `seq` ()
    *** Exception: CategoryOverlapError {coeSlots = ["emailRecipient", ...]}


## Idempotence and Recovery

All steps are idempotent. `cabal build` and `cabal test` re-run
cleanly. Editing `Keiki/Profunctor.hs`, the cabal file, and the test
files is text-level — no migrations.

If `cabal test` fails at M2 with `CategoryOverlapError` thrown by a
test that didn't expect it, the most likely cause is two test
fixtures having unintended slot-name overlap. Fix by renaming a
slot in the inline fixture (the spec module is the only place that
controls the fixture's slot names).

If `cabal build` fails at M1 with a constraint-discharge error on
the `unsafeCoerceDisjointness` definition, the most likely cause is
a GHC warning escalated to an error by `-Wall`. Add a localized
`{-# OPTIONS_GHC -Wno-... -#}` to `Keiki.Profunctor` (the existing
modules already use this pattern; see `src/Keiki/Composition.hs`
line 11).

If `IdVertex`'s `Bounded`/`Enum` derivation fails (unlikely; the
type is a single nullary constructor), drop the `Generic` derivation
and write the `NoThunks` instance by hand:

    instance NoThunks IdVertex where
      showTypeOf _ = "IdVertex"
      wNoThunks _ IdVertex = pure Nothing

A rollback is `git reset --hard` followed by `cabal clean && cabal
build`. Nothing outside the working tree is touched.


## Interfaces and Dependencies

### New module surface added by this plan

`src/Keiki/Profunctor.hs` gains:

    -- Public:
    data IdVertex = IdVertex
    identityTransducer
      :: forall a.
         SymTransducer (HsPred '[] a) '[] IdVertex a a

    -- Inside the existing instance block:
    instance Control.Category.Category SomeSymTransducer

    -- Public exception type (so user code can catch it):
    data CategoryOverlapError = CategoryOverlapError
      { coeSlots :: [String]
      } deriving (Show)
    instance Exception CategoryOverlapError

    -- Private (not exported):
    identityInCtor    :: InCtor a '[ '("payload", a) ]
    identityWireCtor  :: WireCtor a (a, ())
    DictDisjoint
    unsafeCoerceDisjointness

### Amendment to EP-27's wrapper

`SomeSymTransducer ci co`'s existential constraint set grows from
`(WeakenR rs)` to `(WeakenR rs, KnownSlotNames rs)`. This
amendment is recorded in this plan's Decision Log and as a
backward-pointer note in EP-27's M1 Decision Log entry (added by
this plan when M1 ships).

### External dependencies

No new package dependency. `Control.Category` is in `base`;
`Unsafe.Coerce` is in `base`; `Control.Exception` is in `base`. The
`profunctors` dep added by EP-27 is sufficient for this plan.

### Imported keiki modules

`Keiki.Profunctor` continues to import only from `Keiki.Core` (the
re-exports cover everything the identity transducer needs) plus
`base`. No new `Keiki.Composition` import is needed *because the
amendment* — `Keiki.Composition.compose` is imported in M2 by the
Category instance, but that's a single module.

Wait — `compose` is in `Keiki.Composition`, which means
`Keiki.Profunctor` *does* need to import `Keiki.Composition` for
M2. This makes `Keiki.Profunctor` depend on `Keiki.Composition`,
which is fine (no cycle: `Keiki.Composition` does not import
`Keiki.Profunctor`).

Add to imports in M2:

    import Keiki.Composition (compose)

### Downstream consumers

EP-29 (`docs/plans/29-strong-choice-and-arrow-instances-on-the-symtransducer-wrapper.md`)
adds `Strong` / `Choice` / `Arrow` instances. The `Arrow` instance
delegates to this plan's `Category` instance (`Arrow` extends
`Category`); the runtime overlap check inherits to `Arrow`'s
composition operator. EP-29 should not duplicate the disjointness
machinery; it imports `unsafeCoerceDisjointness` and
`CategoryOverlapError` from `Keiki.Profunctor` — *if those are
exported*. Decision: export `CategoryOverlapError` (users may want
to catch it); keep `unsafeCoerceDisjointness` private (re-export to
EP-29 if needed via an internal sub-module
`Keiki.Profunctor.Internal`).
