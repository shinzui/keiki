---
id: 27
slug: existential-wrapper-for-symtransducer-plus-profunctor-instance-and-variance-combinators
title: "Existential wrapper for SymTransducer plus Profunctor instance and variance combinators"
kind: exec-plan
created_at: 2026-05-03T03:16:24Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/9-profunctor-and-category-instances-on-symtransducer.md"
---

# Existential wrapper for SymTransducer plus Profunctor instance and variance combinators

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this plan ships, a keiki user can write

    -- Pre-compose with a partial command router (filters out
    -- commands not destined for this aggregate):
    routedBilling :: SomeSymTransducer Cmd BillingEvent
    routedBilling = lmapMaybeCi routeToBilling (someSymTransducer billingAggregate)

    -- Post-compose with a wire-event upcaster:
    upcastedRegistration :: SomeSymTransducer RegCmd RegEventV2
    upcastedRegistration = rmapCo upcastV1ToV2 (someSymTransducer registrationAggregate)

    -- Use standard `dimap` from the `profunctors` package:
    adapted :: SomeSymTransducer NewCmd NewEvent
    adapted = dimap newToOld oldToNew (someSymTransducer aggregate)

These three call sites — `lmapMaybeCi`, `rmapCo`, and `dimap` — close the named
"command routing", "event versioning", and "ecosystem profunctor interop" gaps
called out in `docs/research/architecture-comparison-fst-aggregate-vs-crem.md`
(crem ships these; keiki currently does not).

The user-visible deliverables are:

1.  A new module `Keiki.Profunctor` that exports an existential wrapper
    `SomeSymTransducer ci co` hiding the register-file slot list `rs` and
    the control vertex `s`, exposing only the input alphabet `ci` and
    output alphabet `co`.

2.  Standalone variance combinators on the *concrete* `SymTransducer`
    type — `lmapCi`, `rmapCo`, `dimapTransducer`, `lmapMaybeCi` — that work
    even when the user wants to keep `rs` / `s` visible. These live in
    `Keiki.Profunctor` alongside the wrapper.

3.  `Profunctor SomeSymTransducer` and `Functor (SomeSymTransducer ci)`
    instances in the same module, plus a `someSymTransducer` smart
    constructor that lifts a concrete `SymTransducer (HsPred rs ci) rs s ci co`
    into the wrapper.

4.  A test suite `test/Keiki/ProfunctorSpec.hs` that exercises each
    combinator on the existing `Keiki.Examples.EmailDelivery` aggregate
    and asserts that the keiki guarantees (`solveOutput`,
    `checkHiddenInputs`, `isSingleValuedSym`) survive the wrapping where
    they survived without it.

The reader can verify success by running `cabal test keiki-test` and seeing
the `Keiki.Profunctor` describe block pass with at minimum eight assertions:
two for `lmapCi` (round-trip preserved on the structural arm; `solveOutput`
behavior on the lmapped arm documented), two for `rmapCo` (round-trip
preserved both directions when `co -> co'` is bijective; `solveOutput` returns
the round-trip image when the inverse is supplied), two for `dimap`, and two
for `lmapMaybeCi`.

The "big picture" framing for the MasterPlan is: this is the wrapper-and-
foundation plan. EP-28 (Category) and EP-29 (Strong / Choice / Arrow) both
import the wrapper this plan ships and add typeclass instances to the same
module. Decisions about wrapper shape, constraint plumbing, and the
solveOutput-vs-Profunctor tension live here and are referenced by the
downstream plans.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] M0: Verify prereqs — Keiki.Composition builds; full test suite passes; record the GHC version and the keiki.cabal `tested-with`
- [ ] M0: Confirm whether the `profunctors` package is in scope or needs to be added to `keiki.cabal`'s `library` build-depends
- [ ] M1: Pick the wrapper shape — full-existential vs. predicate-parameterised; document trade-off in Decision Log
- [ ] M1: Decide how `lmapCi` interacts with `solveOutput` (lossy, dimap-only, or bijection-required); document in Decision Log
- [ ] M1: Create `src/Keiki/Profunctor.hs` with the wrapper newtype, smart constructor `someSymTransducer`, and a stub `Show`/`NoThunks` story
- [ ] M2: Implement `lmapCi`, `rmapCo`, `dimapTransducer`, `lmapMaybeCi` on the concrete `SymTransducer` type
- [ ] M2: Wire `Keiki.Profunctor` into `keiki.cabal`'s library `exposed-modules`
- [ ] M3: Add `Profunctor` and `Functor (SomeSymTransducer ci)` instances on the wrapper
- [ ] M3: Write `test/Keiki/ProfunctorSpec.hs` and register it in `test/Spec.hs`
- [ ] M3: Run `cabal test keiki-test` end-to-end; capture the passing transcript in this plan
- [ ] M3: Update `docs/research/keiki-generics-design.md`'s "Future improvements" list to point at this EP/MP-9
- [ ] M3: Update MP-9 Progress section, mark this EP Complete in the registry, fill in this EP's Outcomes & Retrospective


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- 2026-05-02 / authoring: `SymTransducer`'s input alphabet `ci` is **not**
  strictly contravariant. The variance argument in
  `docs/research/future-directions-profunctors-effects-and-composition.md` §1
  was written for the v0 (pre-symbolic) `Transducer` whose only `ci`-using
  function was `delta :: s -> ci -> Maybe s` (and `omega`'s second argument).
  The v1 `SymTransducer` adds `solveOutput :: OutTerm rs ci co -> RegFile rs
  -> co -> Maybe ci`, which is *covariant* in `ci`: it builds a `ci` from a
  wire event via `icBuild :: RegFile ifs -> ci` (see `Keiki.Core` line 235's
  `InCtor` data constructor). A naive `lmapCi :: (ci' -> ci) -> SymTransducer
  ... ci ... -> SymTransducer ... ci' ...` cannot rewrite `icBuild` because
  it lacks the inverse direction `ci -> ci'`. M1 must pick from three
  resolutions: (a) lmapCi produces a transducer whose `solveOutput` returns
  values in the *original* `ci`, not `ci'` — which type-checks only by
  forgetting the InCtor's icBuild side; (b) provide only `dimap` (require both
  directions); (c) document that `lmapCi`-produced transducers cannot be used
  with `solveOutput` (the structural inversion guarantee is dropped). The
  futures note's variance sketch did not anticipate this. The MP-9 vision
  also did not — it asserts a `Profunctor` instance "on the existential
  wrapper" without flagging it. This plan's M1 owns the resolution.


## Decision Log

Record every decision made while working on the plan.

- Decision: This plan owns the new module `Keiki.Profunctor`; the wrapper
  shape and the standalone combinators ship from the same module.
  Rationale: MP-9's IP-2 names this module as the wrapper's home and says
  EP-28 / EP-29 add their instances to the same module. Splitting standalone
  combinators into a separate module would create unnecessary two-import
  ergonomics for users who want both `lmapCi` and `Profunctor (.)`. The
  combinators are the building blocks the instances delegate to, so they
  belong adjacent in the haddock.
  Date: 2026-05-03

- Decision: The variance-resolution decision (Surprises entry above) is
  kept as a real M1 milestone rather than collapsed into M2's
  implementation. The choice between (a)/(b)/(c) determines the Profunctor
  instance's signature, the haddock contract, and what tests can assert —
  it must be settled before M2 writes the combinators.
  Rationale: PLANS.md's "milestones tell the story" guidance — design
  decisions of this magnitude deserve a milestone of their own with its
  own validation step ("the chosen contract is reflected in the haddock
  and in M3's spec").
  Date: 2026-05-03


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This section gives a complete novice everything they need to know about the
keiki repository to implement this plan without prior familiarity. Read it
end to end before touching any files.

### What keiki is

`keiki` is a Haskell 2024 (GHC 9.12) library that models event-sourced
aggregates and workflow engines as **symbolic-register transducers**. The
canonical type is `SymTransducer phi rs s ci co` defined in
`src/Keiki/Core.hs`:

    data SymTransducer phi rs s ci co = SymTransducer
      { edgesOut    :: s -> [Edge phi rs ci co s]
      , initial     :: s
      , initialRegs :: RegFile rs
      , isFinal     :: s -> Bool
      }

The five type parameters are:

- `phi`  — the **predicate carrier** for edge guards. The two carriers in
  the codebase today are `HsPred rs ci` (defined in `Keiki.Core`, the v1
  best-effort algebra) and `SymPred rs ci` (the SBV-backed v2 wrapper from
  `Keiki.Symbolic`). Most of `Keiki.Composition`'s combinators are pinned
  to `HsPred` for now (see "Composition combinators" below).

- `rs :: [Slot]` — the **register file** schema. A `Slot` is a
  type-level pair `(Symbol, Type)`: a slot name and the value type stored
  in that slot. `RegFile rs` is the value-level register file.

- `s` — the **control vertex** type, typically a small enum (e.g.
  `data EmailVertex = EmailPending | EmailSentVertex`).

- `ci` — the **input alphabet** (commands).

- `co` — the **output alphabet** (events).

`Edge phi rs ci co s` is a GADT defined in `Keiki.Core`:

    data Edge phi rs ci co s where
      Edge
        :: { guard  :: phi
           , update :: Update rs w ci   -- the @w@ slot-list is existential
           , output :: Maybe (OutTerm rs ci co)
           , target :: s
           }
        -> Edge phi rs ci co s

So `ci` appears inside an `Edge` in three places:

1.  In the `guard` (when `phi = HsPred rs ci`, the `PInCtor` constructor
    holds an `InCtor ci ifs`, and `PEq`/`PCmp` can hold `Term rs ci r`
    values that read input fields).

2.  In `update`'s `Term rs ci r` operands (which can be
    `TInpCtorField :: InCtor ci ifs -> Index ifs r -> Term rs ci r`).

3.  In `output`'s `OutTerm rs ci co`, which is constructed by
    `OPack :: InCtor ci ifs -> WireCtor co fields -> OutFields rs ci fields
    -> OutTerm rs ci co`.

In every case, `ci` flows through an `InCtor ci ifs` value. The `InCtor`
data constructor (`Keiki.Core` line 235) is:

    data InCtor ci (ifs :: [Slot]) where
      InCtor
        :: (AssembleRegFile ifs, KnownSlotNames ifs)
        => { icName  :: String
           , icMatch :: ci -> Maybe (RegFile ifs)
           , icBuild :: RegFile ifs -> ci
           }
        -> InCtor ci ifs

Note that `ci` appears **bivariantly** in `InCtor`: contravariantly in
`icMatch :: ci -> Maybe ...` and covariantly in `icBuild :: ... -> ci`.
This is the technical root of the variance surprise documented in
Surprises & Discoveries. `solveOutput` (defined in `Keiki.Core`):

    solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci
    solveOutput (OPack ic@InCtor{} ctor fields) _regs co = do
      ...
      icBuild ic <$> assembled

uses `icBuild` to rebuild a `ci` from an observed `co`. That's the
mechanical inversion guarantee that lets keiki replay events.

`co` appears in `OutTerm` only via `WireCtor co fields` (`Keiki.Core`
line 342), which is also bivariant — `wcMatch :: co -> Maybe fields`
contravariantly and `wcBuild :: fields -> co` covariantly. But `co`
sits on the *output* side: the runtime emits `co` values and the
inversion machinery returns `ci`, so a `co -> co'` post-composition
only needs `wcBuild` to remain `RegFile -> co'` — which is achievable
without an inverse if we route through the original `wcBuild` and apply
`co -> co'` afterward. So `rmapCo` is straightforwardly covariant.

### Composition combinators (`Keiki.Composition`)

`src/Keiki/Composition.hs` exports today:

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

    alternative -- Either-typed dispatch (EP-25 of MP-8)
    feedback1   -- single-step feedback (EP-26 of MP-8)

Three observations relevant to this plan:

1.  All three are pinned to `HsPred` predicate carriers, not phi-polymorphic.
    The wrapper this plan ships is therefore parameterised with the
    `HsPred` carrier baked in — see M1 below.

2.  `compose` requires `Disjoint (Names rs1) (Names rs2)`: the two
    transducers' slot-name domains must be disjoint. This constraint
    cannot be expressed through a `Category`-style `(.)` because that
    interface erases the slot lists. EP-28 (Category) inherits this
    problem; this plan only needs to acknowledge it in the wrapper's
    haddock.

3.  `compose` produces a transducer over `Append rs1 rs2`. Both register
    files survive after composition. The wrapper hides the slot list, so
    composing-via-wrapper still works at the value level — both sub-
    register-files are present at runtime — they're just hidden from the
    type signature.

`Composite s1 s2` is a strict pair newtype with derived `Eq`/`Show` and
hand-rolled `Bounded`/`Enum`/`NoThunks` instances. It's used to make the
post-composition vertex satisfy `Bounded`/`Enum` (required by
`isSingleValuedSym` and `checkHiddenInputs`).

### The keiki guarantees

Three functions defined elsewhere validate transducers; tests rely on them:

- `solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci`
  (in `Keiki.Core`). Inverts an `OPack` to recover the originating `ci`.

- `checkHiddenInputs :: (Bounded s, Enum s, Show s) => SymTransducer phi
  rs s ci co -> [HiddenInputWarning]` (in `Keiki.Core`). Returns a list
  of warnings about `ci` fields that an edge consumes but cannot rebuild
  via its `OPack` — the warning surfaces "data went into the register file
  but not back to the wire".

- `isSingleValuedSym :: (BoolAlg phi (RegFile rs, ci), Bounded s, Enum s)
  => SymTransducer phi rs s ci co -> Bool` (in `Keiki.Symbolic`). Returns
  `True` when no two edges out of the same vertex have overlapping guards
  (the symbolic single-valuedness check).

The wrapper preserves `rs` and `s` at the value level, so these functions
remain callable on the underlying transducer even when the wrapper hides
the indices. The test suite must demonstrate this: pull the underlying
transducer back out (via pattern match on the existential) and feed it to
`checkHiddenInputs` / `isSingleValuedSym`.

### The crem comparison

`docs/research/architecture-comparison-fst-aggregate-vs-crem.md` documents
that crem (a comparable Haskell library) ships `Category`, `Profunctor`,
`Strong`, `Choice`, `Arrow`, and `ArrowChoice` instances on its
`StateMachineT` type, and that keiki shipping equivalents would close one
of the named DX gaps. This plan ships `Profunctor` (the foundation); EP-28
ships `Category`; EP-29 ships the rest.

### Where the existing tests live

`test/Spec.hs` is the single test entrypoint. It hspec-imports each module
under `test/Keiki/` and calls each module's `spec :: Spec` function inside
a top-level `describe`. New test modules must be added in two places:

1.  Listed in `keiki.cabal`'s `test-suite keiki-test` `other-modules`
    field (alphabetical order; the file is at the repo root).

2.  Imported `qualified` in `test/Spec.hs` and added to the `main`
    function with a `describe "..." ModuleName.spec` line.

`test/Keiki/CompositionAlternativeSpec.hs` is the most recent example
(added under EP-25 of MP-8) and is the recommended template — it imports
an existing example aggregate, builds a small inline second aggregate to
compose it with, and asserts that single-valuedness survives the
composition.

### Where to put the new module

`Keiki.Profunctor` is the new module name. It ships at
`src/Keiki/Profunctor.hs`. It is added to `keiki.cabal`'s `library`
`exposed-modules` (alphabetical insertion: between `Keiki.NoThunks` and
`Keiki.Symbolic`).

### The MasterPlan and the futures note

The parent MasterPlan
`docs/masterplans/9-profunctor-and-category-instances-on-symtransducer.md`
contains the high-level vision. Section IP-1 of that file documents the
likely wrapper shape (full-existential `data SomeSymTransducer phi ci co
= forall rs s. SomeSymTransducer (...)`); this plan picks the actual
shape in M1.

`docs/research/future-directions-profunctors-effects-and-composition.md`
§1 is the design sketch this plan implements. It was written before the
v1 symbolic upgrade and uses the v0 `Transducer s c e` shape; the
variance argument in §1 does not anticipate the `solveOutput` /
`icBuild` complication. M1 must reconcile that.


## Plan of Work

The work decomposes into four milestones — M0 (prereqs), M1 (wrapper
shape and variance-resolution decision), M2 (standalone combinators), M3
(Profunctor / Functor instances on the wrapper plus the test suite).

### M0 — Verify prerequisites

Scope: prove the codebase is in a buildable, test-green state before
adding code. Confirm whether the `profunctors` package is already
available or needs to be pulled in.

What will exist at the end: a recorded baseline (GHC version, current
test count, current `cabal build` output) captured in the Surprises &
Discoveries section so a future contributor can confirm we're starting
from the same point. The cabal file's library `build-depends` lists
either confirms `profunctors` is present or notes it must be added.

Commands to run from `/Users/shinzui/Keikaku/bokuno/keiki/`:

    cabal build all
    cabal test keiki-test --test-show-details=direct

Acceptance: both commands exit 0; the test suite reports
`X examples, 0 failures` (record `X` in Surprises & Discoveries).

Then:

    grep -E '^\s*,?\s*profunctors' keiki.cabal

If this returns no matches, M0 records that `profunctors` is not
currently in `build-depends` and M3 must add it; otherwise M3 simply
imports from it.

### M1 — Pick the wrapper shape and the variance contract

Scope: settle two consequential design decisions before any code lands.

**Decision 1 — wrapper shape.** Two candidate shapes:

Shape A (full-existential, the futures note's sketch):

    data SomeSymTransducer ci co where
      SomeSymTransducer
        :: SymTransducer (HsPred rs ci) rs s ci co
        -> SomeSymTransducer ci co

Shape B (predicate-parameterised; phi visible):

    data SomeSymTransducer phi ci co where
      SomeSymTransducer
        :: SymTransducer phi rs s ci co
        -> SomeSymTransducer phi ci co

Trade-off: Shape A keeps the `Profunctor` and `Category` instances
parameterless on `phi` (one instance covers all transducers). Shape B
keeps the door open for symbolic-pred transducers (`SymPred`) to flow
through the wrapper without being demoted back to `HsPred`. The
composition combinators in `Keiki.Composition` are pinned to `HsPred`
today, so Shape B's flexibility is unused. Recommendation: Shape A,
with a Decision Log entry noting the trade-off and the migration path
(if a future plan generalises `compose` over phi, the wrapper grows a
phi parameter).

**Decision 2 — Profunctor variance contract.** The variance issue
recorded in Surprises & Discoveries demands a choice. Three options:

Option (a): **lossy lmapCi.** Provide `lmapCi :: (ci' -> ci) ->
SymTransducer (HsPred rs ci) rs s ci co -> SymTransducer (HsPred rs
ci') rs s ci' co`, but document that on the result transducer,
`solveOutput` always returns `Nothing` for any edge that contains an
`InCtor`. Rationale: the InCtor's `icBuild :: RegFile ifs -> ci'`
requires a `ci -> ci'` we don't have, so we substitute `\_ -> error`
for `icBuild` and have `solveOutput` short-circuit to `Nothing`
whenever it would call `icBuild`. The InCtor's `icName` and `icMatch
. f` are valid; only `icBuild` is poisoned.

Option (b): **dimap-only.** Drop standalone `lmapCi` from the public
API. Provide only `dimapTransducer :: (ci' -> ci) -> (ci -> ci') ->
(co -> co') -> ...` (note the bidirectional ci component) and define
`lmapCi f = dimapTransducer f (error "...") id` only as an internal
helper. Rationale: this honestly reflects the variance — keiki
transducers have a covariant ci-side (icBuild) and need both
directions for the lmap to remain semantically meaningful.

Option (c): **document the loss; ship `lmapCi` anyway.** Same
implementation as (a), but the haddock for the wrapper's `Profunctor`
instance makes a one-line statement that "`lmap` over the wrapper
preserves `delta`/`omega` semantics but does not preserve
`solveOutput`'s round-trip on lmapped edges". This matches crem's
posture (crem's `Profunctor` instance loses its history-recovery
function on lmap; documented in its haddock).

Recommendation: **(c)** — ship `lmapCi` with the documented
caveat. The standard Haskell `Profunctor` typeclass interface
(`lmap :: (a -> b) -> p b c -> p a c`) is what users expect; choosing
(b) would force keiki users to write a non-standard `dimap` and lose
ecosystem interop. Option (a) is identical in behavior to (c); the
distinction is purely about how loudly the haddock advertises the
semantic loss. Choosing (c) keeps the wrapper Profunctor-compatible
and surfaces the loss at the right place (the InCtor / solveOutput
contract).

The Decision Log entry must record which option was chosen and why,
and must include a `solveOutput` test case in M3 that demonstrates the
documented behavior.

**Output of M1:** the Decision Log has two new entries (wrapper shape
and variance contract). `src/Keiki/Profunctor.hs` exists with:

- The `SomeSymTransducer ci co` newtype (or GADT) per Decision 1.
- A smart constructor `someSymTransducer :: SymTransducer (HsPred rs
  ci) rs s ci co -> SomeSymTransducer ci co`.
- Pattern-synonym or record-accessor surface for unpacking when needed
  (e.g. for tests). Use a GADT-style constructor with an explicit
  pattern match in tests (no pattern synonyms required).
- A module haddock that names this plan, the parent MasterPlan, and
  the variance caveat in one paragraph.

Acceptance for M1: `cabal build all` succeeds with the new module.
`grep -n SomeSymTransducer src/Keiki/Profunctor.hs` returns the
constructor and smart-constructor definitions. The Decision Log in
this plan has both decisions recorded with rationale.

### M2 — Standalone variance combinators on the concrete type

Scope: implement `lmapCi`, `rmapCo`, `dimapTransducer`, `lmapMaybeCi`
on the concrete `SymTransducer (HsPred rs ci) rs s ci co` type. These
are useful even when the user wants to keep `rs` and `s` visible
(e.g., when chaining with `compose` afterward).

What will exist at the end:

    -- All four in src/Keiki/Profunctor.hs.

    lmapCi
      :: (ci' -> ci)
      -> SymTransducer (HsPred rs ci)  rs s ci  co
      -> SymTransducer (HsPred rs ci') rs s ci' co

    lmapMaybeCi
      :: (ci' -> Maybe ci)
      -> SymTransducer (HsPred rs ci)  rs s ci  co
      -> SymTransducer (HsPred rs ci') rs s ci' co

    rmapCo
      :: (co -> co')
      -> SymTransducer (HsPred rs ci) rs s ci co
      -> SymTransducer (HsPred rs ci) rs s ci co'

    dimapTransducer
      :: (ci' -> ci)
      -> (co  -> co')
      -> SymTransducer (HsPred rs ci)  rs s ci  co
      -> SymTransducer (HsPred rs ci') rs s ci' co'

Implementation approach (concrete, not narrative — these are the
edits to make):

For `lmapCi f t` (and `lmapMaybeCi f t`, which differs only in the
contramap function shape):

1.  Rewrite each edge by walking `edgesOut t s` and producing a new
    edge with the same `target`, but with `guard`, `update`, and
    `output` rewritten through `f`.

2.  `guard :: HsPred rs ci` is rewritten by walking the `HsPred` AST
    (`PTop`/`PBot`/`PAnd`/`POr`/`PNot`/`PEq`/`PCmp`/`PInCtor`) and
    replacing every `InCtor ci ifs` it carries (in `PInCtor` and
    inside `PEq`/`PCmp`'s `Term`s) with the contramapped InCtor (see
    helper below).

3.  `update :: Update rs w ci` is rewritten by walking the `Update`
    AST and rewriting any embedded `Term`s through the same Term
    rewriter.

4.  `output :: Maybe (OutTerm rs ci co)` is rewritten by walking the
    `OutTerm` (only `OPack` constructor) and rewriting its `InCtor`
    and the `OutFields`' `Term`s.

5.  The InCtor rewriter is the central helper:

        contraInCtor :: (ci' -> ci) -> InCtor ci ifs -> InCtor ci' ifs
        contraInCtor f InCtor { icName = n, icMatch = m, icBuild = b } =
          InCtor
            { icName  = n
            , icMatch = m . f
            , icBuild = poison  -- per Decision 2 (option c)
            }
          where
            poison = error
              ( "Keiki.Profunctor.lmapCi: icBuild on a contramapped \
                \InCtor was invoked. lmapped transducers cannot \
                \rebuild ci from a wire event via solveOutput. See \
                \the haddock for Keiki.Profunctor.lmapCi."
              )

    The poisoning is acceptable because keiki only calls `icBuild`
    from `solveOutput` (`Keiki.Core` line 731). `solveOutput` is the
    inverse-mechanism for replay; it is *not* called during the
    forward `delta`/`omega` evaluation paths
    (`Keiki.Core.evalPred`, `Keiki.Core.evalTerm`, etc., use
    `icMatch` only). So `lmapped` transducers remain fully usable
    for forward command processing; they just don't support
    `solveOutput`-based replay. This matches the haddock contract.

    Variant for `lmapMaybeCi`:

        contraMaybeInCtor :: (ci' -> Maybe ci) -> InCtor ci ifs -> InCtor ci' ifs
        contraMaybeInCtor f InCtor { icName = n, icMatch = m, icBuild = _ } =
          InCtor
            { icName  = n
            , icMatch = \ci' -> f ci' >>= m
            , icBuild = poison
            }

6.  Term rewriter (signature):

        contraTerm
          :: (ci' -> ci) -> Term rs ci r -> Term rs ci' r

    Recurses through `Term`'s constructors. The interesting case is
    `TInpCtorField :: InCtor ci ifs -> Index ifs r -> Term rs ci r`
    which becomes `TInpCtorField (contraInCtor f ic) ix`. The other
    constructors (`TLit`, `TReg`, binary ops) carry no `ci`.

7.  HsPred rewriter:

        contraPred
          :: (ci' -> ci) -> HsPred rs ci -> HsPred rs ci'

    Walks `PTop`/`PBot` (return as-is, just retype), `PAnd`/`POr`
    (recurse), `PNot` (recurse), `PEq`/`PCmp` (recurse into both
    `Term` operands via `contraTerm`), and `PInCtor ic` (rewrite via
    `contraInCtor`).

8.  Update rewriter:

        contraUpdate
          :: (ci' -> ci) -> Update rs w ci -> Update rs w ci'

    Walks `UKeep`, `UCombine` (recurse), `UWrite ix term` (rewrite
    `term` via `contraTerm`).

9.  OutTerm rewriter:

        contraOutTerm
          :: (ci' -> ci) -> OutTerm rs ci co -> OutTerm rs ci' co

        contraOutTerm f (OPack ic wc fields) =
          OPack (contraInCtor f ic) wc (contraOutFields f fields)

        contraOutFields
          :: (ci' -> ci) -> OutFields rs ci fs -> OutFields rs ci' fs

    Walks `OFNil` (return as-is, just retype) and `OFCons t rest`
    (recurse).

For `rmapCo g t`: only `output :: Maybe (OutTerm rs ci co)` mentions
`co`. Rewrite:

    coOutTerm :: (co -> co') -> OutTerm rs ci co -> OutTerm rs ci co'
    coOutTerm g (OPack ic wc fields) = OPack ic (coWireCtor g wc) fields

    coWireCtor :: (co -> co') -> WireCtor co fs -> WireCtor co' fs
    coWireCtor g WireCtor { wcName = n, wcMatch = m, wcBuild = b } =
      WireCtor
        { wcName  = n
        , wcMatch = \_co' -> Nothing  -- documented loss, see below
        , wcBuild = g . b
        }

The `wcMatch` covariance situation mirrors `icBuild`: `wcMatch :: co
-> Maybe fs` becomes covariant after the post-compose, requiring an
inverse `co' -> co`. The `wcMatch` is consulted only by `solveOutput`
(when the runtime sees a `co` and asks "which OPack edge did it come
from?"). Set `wcMatch` to `\_ -> Nothing` and document that
`solveOutput` returns `Nothing` for `rmapCo`-rewritten transducers
(symmetric to the `lmapCi` story). Forward processing
(`delta`/`omega` + `evalOut` through `wcBuild`) is unaffected.

The `dimapTransducer` is just `rmapCo g . lmapCi f`.

Implementation notes:

- The four combinators sit *below* the wrapper in `Keiki.Profunctor`.
  The wrapper's `Profunctor` instance in M3 delegates to them.

- Test-side: M3 will add a small spec for each combinator. M2 itself
  doesn't need new tests (combinators are a pure rewrite; M3's spec
  exercises both layers).

- Cabal: `Keiki.Profunctor` is added to `keiki.cabal`'s
  `exposed-modules` in M2. The library does not yet depend on the
  `profunctors` package — that is added in M3 only if the M0 check
  showed it's missing.

Acceptance for M2: `cabal build all` succeeds. `grep -n
"^lmapCi\|^rmapCo\|^dimapTransducer\|^lmapMaybeCi"
src/Keiki/Profunctor.hs` returns four matches with the exact
signatures above. A small one-shot smoke check:

    cabal repl keiki
    > :type Keiki.Profunctor.lmapCi
    > :type Keiki.Profunctor.rmapCo

returns the expected types.

### M3 — Profunctor and Functor instances on the wrapper, plus tests

Scope: add the typeclass instances and the comprehensive test
suite. Update the keiki-generics-design future-improvements list.
Update the parent MasterPlan.

What will exist at the end:

1.  `Keiki.Profunctor` exports `Profunctor SomeSymTransducer` and
    `Functor (SomeSymTransducer ci)` instances. The `Profunctor`
    instance comes from the `profunctors` package (`Data.Profunctor`).
    If M0 found `profunctors` was not yet a build-dep, add it to
    `keiki.cabal`'s library `build-depends` (use a tight version
    bound: `profunctors >= 5.6 && < 6` is the current LTS-aligned
    bound).

2.  The instances delegate trivially:

        instance Profunctor SomeSymTransducer where
          dimap f g (SomeSymTransducer t) =
            SomeSymTransducer (dimapTransducer f g t)
          lmap  f   (SomeSymTransducer t) =
            SomeSymTransducer (lmapCi f t)
          rmap    g (SomeSymTransducer t) =
            SomeSymTransducer (rmapCo g t)

        instance Functor (SomeSymTransducer ci) where
          fmap = rmap

3.  `test/Keiki/ProfunctorSpec.hs` exists, registered in
    `keiki.cabal`'s test-suite `other-modules` and imported in
    `test/Spec.hs`. Spec coverage outline (concrete; M3 must
    implement every assertion):

    a.  **Round-trip preservation under `rmapCo` with bijection.**
        Use the `Keiki.Examples.EmailDelivery` aggregate (input
        alphabet `EmailCmd`, output alphabet `EmailEvent`). Define a
        bijection `EmailEvent <-> EmailEventV2` (e.g., a thin newtype
        wrapper). Apply `rmapCo (toV2)` to get a wrapped transducer.
        Assert: forward processing produces `EmailEventV2` values
        whose unwrap gives the same `EmailEvent` as the un-wrapped
        transducer. (Requires building a small forward-evaluation
        harness; or, more cheaply, just inspect the AST of an edge
        and assert the `wcBuild` chain produces the right value.)

    b.  **`solveOutput` returns `Nothing` on rmapped transducers,
        per the documented contract.** Use the same
        `EmailDelivery` aggregate; pull one edge from the rmapped
        transducer; manually invoke `solveOutput` on it with a
        synthetic `co'` value; assert `Nothing`.

    c.  **Forward processing under `lmapCi` works.** Define a
        `WrappedEmailCmd` newtype around `EmailCmd`. Apply `lmapCi
        unwrap`. Assert that `evalPred` and `evalTerm` on rewritten
        edges produce the same booleans / values as on the
        original edges (using a synthetic `WrappedEmailCmd` input).

    d.  **`solveOutput` returns `Nothing` on lmapped transducers
        with a non-trivial `OPack`.** Symmetric to (b).

    e.  **`lmapMaybeCi` filters as documented.** Define a sum
        command type `data WhichCmd = ToEmail EmailCmd | ToOther
        Text`. Apply `lmapMaybeCi (\case ToEmail c -> Just c; _ ->
        Nothing)`. Assert that a `ToOther` input causes
        `evalPred` on the rewritten guard to return `False` (no
        edge fires).

    f.  **`dimap` agrees with `rmapCo . lmapCi`.** Build a
        transducer two ways — once through `dimap f g` and once
        through `rmapCo g . lmapCi f` — and assert they have the
        same `edgesOut` shape (compare via reading representative
        edges).

    g.  **`isSingleValuedSym` survives `lmapCi`.** Run
        `isSingleValuedSym` on the lmapped transducer, assert
        `True`. This validates that wrapping does not invalidate the
        symbolic single-valuedness guarantee.

    h.  **`checkHiddenInputs` survives `lmapCi`.** Run
        `checkHiddenInputs` on the lmapped transducer, assert it
        returns `[]` (matching the un-lmapped EmailDelivery
        baseline, which has no hidden inputs).

4.  `docs/research/keiki-generics-design.md`'s "Future improvements"
    section gets a one-line entry pointing at MP-9 / EP-27
    (this plan) for the crem-parity wrapper.

5.  `docs/masterplans/9-profunctor-and-category-instances-on-symtransducer.md`'s
    Progress section has the four EP-27 milestone bullets (M0..M3)
    checked off, the Exec-Plan Registry has EP-1's status set to
    `Complete`, and the EP-27 row now references this file's actual
    path (`docs/plans/27-...`) instead of the placeholder
    `docs/plans/25-...`.

Acceptance for M3: `cabal test keiki-test --test-show-details=direct`
succeeds. The output includes the new `Keiki.Profunctor` describe
block with at least eight assertions (a-h above), all passing. The
total test count is greater than the M0 baseline by at least 8. The
keiki-generics-design future-improvements update is committed (a
one-line addition; verify with `git diff
docs/research/keiki-generics-design.md`).


## Concrete Steps

The exact sequence of shell commands and edits, in order. Every
command runs from `/Users/shinzui/Keikaku/bokuno/keiki/`. Update this
section as work proceeds with timestamps and observed output.

### M0 commands

    cabal build all
    cabal test keiki-test --test-show-details=direct 2>&1 | tail -30
    grep -E '^\s*,?\s*profunctors' keiki.cabal || echo "profunctors not present"

Expected output for the test suite: lines like `Finished in X
seconds, N examples, 0 failures` with a non-zero `N`. Record `N` in
Surprises & Discoveries.

### M1 edits

Create `src/Keiki/Profunctor.hs`. The module skeleton (after Decision
1 picks Shape A and Decision 2 picks option (c)):

    {-# LANGUAGE GADTs #-}
    {-# LANGUAGE PolyKinds #-}

    -- | Existential wrapper for 'SymTransducer' enabling participation in
    -- the standard 'Profunctor' / 'Category' ecosystem, plus standalone
    -- variance combinators on the concrete 'SymTransducer' type.
    --
    -- See 'docs/plans/27-...' for the design rationale and the
    -- documented variance caveat (lmap'd transducers do not preserve
    -- 'solveOutput's round-trip; see 'lmapCi's haddock).
    module Keiki.Profunctor
      ( -- * Existential wrapper
        SomeSymTransducer (..)
      , someSymTransducer
        -- * Standalone variance combinators
      , lmapCi
      , rmapCo
      , dimapTransducer
      , lmapMaybeCi
      ) where

    import Data.Profunctor (Profunctor (..))

    import Keiki.Core

    data SomeSymTransducer ci co where
      SomeSymTransducer
        :: SymTransducer (HsPred rs ci) rs s ci co
        -> SomeSymTransducer ci co

    someSymTransducer
      :: SymTransducer (HsPred rs ci) rs s ci co
      -> SomeSymTransducer ci co
    someSymTransducer = SomeSymTransducer

Keep `lmapCi` etc. as `undefined` placeholders for M1; M2 fills them in.

Add `Keiki.Profunctor` to `keiki.cabal`'s library `exposed-modules`
list (alphabetically between `Keiki.NoThunks` and `Keiki.Symbolic`).
If M0 found `profunctors` is missing, also add `profunctors >= 5.6 &&
< 6` to the library `build-depends`.

Verify M1:

    cabal build keiki

Expected: success, with warnings about `lmapCi`/`rmapCo`/`dimapTransducer`/
`lmapMaybeCi` being defined as `undefined`. Those go away in M2.

Commit M1:

    git add src/Keiki/Profunctor.hs keiki.cabal docs/plans/27-... docs/masterplans/9-...
    git commit  # see "Commit message format" below

### M2 edits

Replace each `undefined` in `src/Keiki/Profunctor.hs` with the actual
implementations described in the M2 milestone above. The InCtor
rewriter, Term rewriter, HsPred rewriter, Update rewriter, OutTerm
rewriter, and OutFields rewriter are private helpers in the same
module (do not export them; the Profunctor instance and the four
public combinators are the only public surface).

Verify M2:

    cabal build all
    # Smoke check that the types resolve:
    cabal repl keiki <<EOF
    :type Keiki.Profunctor.lmapCi
    :type Keiki.Profunctor.rmapCo
    :type Keiki.Profunctor.dimapTransducer
    :type Keiki.Profunctor.lmapMaybeCi
    EOF

Expected output: each `:type` returns the signature given in the M2
milestone. No build errors.

Commit M2.

### M3 edits

Add the `Profunctor` and `Functor` instances at the bottom of
`src/Keiki/Profunctor.hs` (the import of `Data.Profunctor.Profunctor`
was added in M1).

Create `test/Keiki/ProfunctorSpec.hs` per the M3 outline (eight
assertions a-h). Register it in `keiki.cabal`'s test-suite
`other-modules` (alphabetically after `Keiki.NoThunksSpec`) and import
+ describe-call it in `test/Spec.hs`.

Update `docs/research/keiki-generics-design.md` "Future improvements"
to add a sub-bullet (under the existing list) noting that the
crem-parity Profunctor / Category / Strong / Choice / Arrow instances
are tracked under MP-9 (with this plan being the wrapper foundation).

Update `docs/masterplans/9-profunctor-and-category-instances-on-symtransducer.md`:

- Replace the placeholder paths (`docs/plans/25-...`, `26-...`,
  `27-...`) with the real paths (`docs/plans/27-...`, `28-...`,
  `29-...`) in the Exec-Plan Registry.
- Set the registry status of EP-1 (this plan) to `Complete`.
- Check off the four EP-1 (now EP-27) milestones in the Progress
  section.
- Add a Surprises & Discoveries entry for the icBuild covariance
  finding (cross-reference this plan).

Verify M3:

    cabal test keiki-test --test-show-details=direct 2>&1 | tail -50

Expected output: a `Keiki.Profunctor` describe block with eight
"it ..." lines, all green. Total examples increased by at least 8.

Commit M3.

### Commit message format

Each commit on this plan must include both the `MasterPlan:` and
`ExecPlan:` and `Intention:` git trailers. Use Conventional Commits
prefix `feat(profunctor):` or `docs(profunctor):` as appropriate. A
concrete first-commit example for M0 + M1:

    feat(profunctor): EP-27 M0+M1 — wrapper newtype + module skeleton

    Introduce Keiki.Profunctor with SomeSymTransducer existential
    wrapper and a smart constructor. Add to library exposed-modules
    and pull in the profunctors package. Standalone variance
    combinators are stubbed; M2 fills them in.

    MasterPlan: docs/masterplans/9-profunctor-and-category-instances-on-symtransducer.md
    ExecPlan: docs/plans/27-existential-wrapper-for-symtransducer-plus-profunctor-instance-and-variance-combinators.md
    Intention: intention_01knjzws4qezz9w8b0743zfqv8


## Validation and Acceptance

The user-visible success criterion for the entire plan is:

    cabal test keiki-test --test-show-details=direct

passes with the new `Keiki.Profunctor` describe block green and the
total assertion count increased by at least eight.

A secondary, more demonstrative validation: in `cabal repl keiki` a
user can type:

    > import Keiki.Profunctor
    > import Keiki.Examples.EmailDelivery
    > import Data.Profunctor

    > :type someSymTransducer emailDelivery
    someSymTransducer emailDelivery :: SomeSymTransducer EmailCmd EmailEvent

    > newtype Wrap a = Wrap { unwrap :: a }
    > :type rmap Wrap (someSymTransducer emailDelivery)
    rmap Wrap (someSymTransducer emailDelivery) :: SomeSymTransducer EmailCmd (Wrap EmailEvent)

and have the type signatures resolve as shown.

The keiki guarantees survive in the obvious sense:

- `isSingleValuedSym` returns the same boolean before and after
  `lmapCi` / `rmapCo` / `dimap` (the rewrite is structural and
  preserves guard satisfiability).
- `checkHiddenInputs` returns the same warnings before and after
  (the rewrite preserves OPack structure).
- `solveOutput` returns `Nothing` instead of `Just _` on
  lmap/rmap-rewritten transducers, *as documented*. This is a
  designed loss, not a bug; the test suite asserts the documented
  behavior in cases (b) and (d) above.


## Idempotence and Recovery

Every step in this plan is idempotent. `cabal build` and `cabal test`
re-run cleanly after partial changes. Editing
`src/Keiki/Profunctor.hs`, the cabal file, or the test files is
text-level — no migrations, no destructive operations.

If `cabal test` fails at M3, the failure mode is most likely:

1.  A test assertion in `Keiki.ProfunctorSpec` not matching the
    documented contract — fix the test or the implementation
    depending on which is wrong; record in Surprises & Discoveries.

2.  The InCtor / WireCtor rewriter triggering the `error` poison from
    a forward path that wasn't supposed to call `icBuild` /
    `wcMatch`. If this happens, it means `Keiki.Core`'s evaluation
    machinery does in fact call those functions on a forward path —
    which would be a finding worth recording in Surprises &
    Discoveries and resolving by either (i) finding the actual
    forward call site and adding a guard, or (ii) escalating the M1
    Decision 2 choice (option c is wrong; revisit options a/b).

3.  GHC complaining about missing `KnownInCtors` or `ExtractRegFile`
    constraints. Both are tied to `ci`'s identity (the dictionary
    types for the symbolic witness extractor). When `ci` changes,
    those instances need to be re-derivable for the new `ci`. The
    standalone combinators in this plan don't depend on those
    instances (only `Keiki.Symbolic`'s witness extractors do); but
    if M3's tests use `isSingleValuedSym` on a rewritten transducer,
    the test fixture must provide a `KnownInCtors` instance for the
    new `ci`. Add `deriving stock (Generic)` and a `KnownInCtors`
    instance for the test newtype.

A rollback is `git reset --hard` followed by `cabal clean` and `cabal
build`; nothing outside the working tree is touched by this plan.


## Interfaces and Dependencies

### New module surface

`src/Keiki/Profunctor.hs` exports:

    SomeSymTransducer (..)
    someSymTransducer
      :: SymTransducer (HsPred rs ci) rs s ci co
      -> SomeSymTransducer ci co
    lmapCi
      :: (ci' -> ci)
      -> SymTransducer (HsPred rs ci)  rs s ci  co
      -> SymTransducer (HsPred rs ci') rs s ci' co
    lmapMaybeCi
      :: (ci' -> Maybe ci)
      -> SymTransducer (HsPred rs ci)  rs s ci  co
      -> SymTransducer (HsPred rs ci') rs s ci' co
    rmapCo
      :: (co -> co')
      -> SymTransducer (HsPred rs ci) rs s ci co
      -> SymTransducer (HsPred rs ci) rs s ci co'
    dimapTransducer
      :: (ci' -> ci)
      -> (co  -> co')
      -> SymTransducer (HsPred rs ci)  rs s ci  co
      -> SymTransducer (HsPred rs ci') rs s ci' co'

Plus the typeclass instances:

    instance Profunctor SomeSymTransducer
    instance Functor    (SomeSymTransducer ci)

### External dependencies

`profunctors >= 5.6 && < 6` must be in `keiki.cabal`'s library
`build-depends` after this plan ships. M0 records whether it's
already there.

The `profunctors` package is a small, foundational, no-transitive-
dependency-explosion library. It's the canonical home for
`Data.Profunctor.Profunctor` and is already used by every other
Haskell library that ships profunctor instances. No risk in adding
it.

### Imported keiki modules

`Keiki.Profunctor` imports from `Keiki.Core` only. It does not import
`Keiki.Composition`, `Keiki.Symbolic`, `Keiki.Generics`, or any of
the example modules. This keeps the wrapper a leaf module
dependency-wise.

### Downstream consumers

EP-28 (`docs/plans/28-category-instance-on-the-symtransducer-wrapper.md`)
and EP-29 (`docs/plans/29-strong-choice-and-arrow-instances-on-the-
symtransducer-wrapper.md`) both add their typeclass instances to
`Keiki.Profunctor`. They depend on this plan's `SomeSymTransducer`
type and its smart constructor; they do not need the standalone
combinators (Category's `id` and `(.)` build their own primitives,
and Strong/Choice/Arrow delegate to MP-8's `parallel` / `alternative`
combinators).

The downstream plans also assume the variance contract chosen in M1
Decision 2 — specifically, that lmap/rmap loses `solveOutput`
round-trip. EP-29's `Choice` instance, which delegates to
`alternative`, will inherit the same caveat for its `right` /
`left` wrappers (they apply `lmapCi (Either ci1 ci2 -> ci_i)`-shaped
rewrites at the boundary). EP-29's haddock should cite this plan's
M1 Decision 2.
