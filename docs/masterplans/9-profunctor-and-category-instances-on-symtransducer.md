---
id: 9
slug: profunctor-and-category-instances-on-symtransducer
title: "Profunctor and Category instances on SymTransducer"
kind: master-plan
created_at: 2026-05-02T23:44:02Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
---

# Profunctor and Category instances on SymTransducer

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

`SymTransducer phi rs s ci co` has a clear variance story:

- `ci` (the input alphabet) appears only in guards (via `HsPred rs
  ci`), update terms (`Term rs ci r`), and output terms (`OutTerm
  rs ci co`). It is **contravariant** — a function `ci' -> ci`
  pre-composes with every reader.
- `co` (the output alphabet) appears only in `output :: Maybe
  (OutTerm rs ci co)`. It is **covariant** — a function
  `co -> co'` post-composes with the wire-event constructor.
- `s` (control vertex) and `rs` (the typed register file) are
  invariant — both read and written.

The futures note
`docs/research/future-directions-profunctors-effects-and-composition.md`
§1 sketches this exact variance story for the pre-symbolic
`Transducer s c e` and lays out the existential wrapper pattern
needed to participate in the standard `profunctors` /
`Control.Category` ecosystem. The crem comparison note
(`docs/research/architecture-comparison-keiki-vs-crem.md`)
documents that crem ships `Category`, `Profunctor`, `Strong`,
`Choice`, `Arrow`, and `ArrowChoice` instances on `StateMachineT`,
and that keiki shipping equivalents would close one of the named
DX gaps relative to crem.

After this MasterPlan, keiki exposes:

- An existential wrapper newtype that hides the `s` and `rs`
  parameters of `SymTransducer`, exposing only `ci` and `co`.
  Multiple shapes are plausible (one full-existential newtype, or
  a family parameterised by predicate carrier); the design
  milestone picks one.
- Standalone `lmapCi`, `rmapCo`, and `dimapTransducer` functions
  on the concrete `SymTransducer` type (no existential needed —
  these are useful even when `s` and `rs` are fixed).
- A `lmapMaybeCi` filter combinator (futures note §1) for
  command routing — pre-compose with a partial function that
  can `Nothing`-out commands not destined for this transducer.
- `Profunctor` and `Functor` (on `co`) instances on the
  existential wrapper.
- A `Category` instance on the existential wrapper, with
  `id` lifted from a stateless identity transducer and `(.)`
  delegating to MP-4's `compose`.
- `Strong` and `Choice` instances on the existential wrapper,
  delegating to MP-8's `parallel` and `alternative` combinators
  *once they ship*. These instances stay in the plan as a
  soft-deferred milestone; if MP-8 declines a combinator, the
  matching instance is dropped.
- `Arrow` (and `ArrowChoice`, conditionally) instances once the
  underlying combinators are in place.

User-visible behaviours enabled:

- **Command routing.** `lmapMaybeCi (routeToBilling :: Cmd ->
  Maybe BillingCmd) billingAggregate` lets a runtime feed a
  union command stream to multiple aggregates without writing
  per-aggregate dispatch glue.
- **Event versioning.** `rmapCo (upcastV1ToV2 :: EventV1 ->
  EventV2) legacyAggregate` adapts an existing aggregate to a
  newer wire schema at the type level.
- **Arrow notation.** With `Category` and (eventually) `Arrow`
  instances, users can compose transducers in standard arrow
  syntax, picked up by ecosystem tooling that expects the
  classes.
- **Profunctor lens / optic interop.** Standard `dimap`-shaped
  combinators from the `profunctors` and `lens` ecosystems
  compose with keiki transducers through the existential
  wrapper.

In scope:

- The existential wrapper newtype and its design rationale.
- `lmapCi`, `rmapCo`, `dimapTransducer`, `lmapMaybeCi` on the
  concrete `SymTransducer` type.
- `Profunctor`, `Functor`, and `Category` instances on the
  existential wrapper.
- A new module `Keiki.Profunctor` (or sibling) that owns the
  wrapper and the instances; `Keiki.Composition` keeps its
  current shape.
- A test suite (`test/Keiki/ProfunctorSpec.hs`) that exercises
  each combinator on at least one of the existing example
  aggregates and asserts that the keiki guarantees
  (`solveOutput`, `checkHiddenInputs`, `isSingleValuedSym`)
  survive the wrapping where they survive without it.
- Updates to `docs/research/keiki-generics-design.md`'s "Future
  improvements" list (item that maps to crem-parity instances)
  pointing at MP-9.

Out of scope:

- The combinators themselves (`parallel`, `alternative`,
  `feedback`, `Kleisli`) — those are MP-8's deliverable. MP-9
  ships the typeclass *instances* that delegate to them, gated
  on MP-8's progress.
- Effectful composition (an `EffTransducer m ci co` family per
  futures note §6). Effects stay at the runtime boundary; the
  existential wrapper here is pure.
- A `Decider`-side profunctor / contravariant story. The futures
  note §1 explains why the Decider is *not* a profunctor in
  events (events serve double duty in `decide` and `evolve`);
  out of scope.
- `Costrong`, `Cochoice`, `Closed` from the wider profunctors
  hierarchy. Defer until a real authoring need surfaces; the
  design milestone may or may not pull them in.


## Decomposition Strategy

Three child ExecPlans, ordered by load-bearing-ness:

1. **EP A (existential wrapper + standalone variance combinators
   + `Profunctor` instance).** This is the foundation; no other
   plan can land before the wrapper exists. It also delivers the
   most user-visible value standalone (`lmapCi`, `rmapCo`,
   `lmapMaybeCi`, `dimapTransducer`).
2. **EP B (`Category` instance + identity transducer).** Depends
   on EP A's wrapper. The identity transducer is a one-vertex
   `SymTransducer` that passes its input through as output via a
   single edge with `OPack` of an identity `WireCtor`. `(.)`
   delegates to MP-4's existing `compose`.
3. **EP C (`Strong` / `Choice` / `Arrow` instances).** Depends
   on EP A's wrapper *and* on MP-8's `parallel` / `alternative`
   combinators. Held as Not Started until MP-8 ships at least
   one of those combinators; lands incrementally as each
   combinator becomes available.

Decomposing this way matches the dependency structure: the
wrapper is a one-time decision that everything else builds on,
the `Category` instance only needs the existing `compose`, and
the richer instances need MP-8.

Three EPs is at the lower end of MASTERPLAN.md's "two to seven"
guidance and matches the genuine independent-verifiability
boundaries: each EP delivers a concrete, testable behaviour
(EP A — variance combinators work on real aggregates; EP B —
`Category` law-tests pass; EP C — `Strong` / `Choice` /`Arrow`
law-tests pass).

**Why a MasterPlan and not a single ExecPlan:** the wrapper
choice in EP A is consequential enough to deserve its own
milestone with its own validation pass, and EP C's progress is
gated on MP-8 — packing all three into one ExecPlan would
either freeze EP A's choices behind MP-8's timeline or force EP
C to live in limbo within a partially-complete plan.

**Alternatives considered:**

- *Single ExecPlan covering all three.* Rejected: the gate on
  MP-8 for EP C would leave a single ExecPlan partially
  complete for an unknown duration, which violates PLANS.md's
  "Every ExecPlan must produce a demonstrably working
  behavior" principle (a partially-complete plan is not a
  working behaviour).
- *Bundle into MP-8 (combinators).* Rejected: the wrapper
  decision is independent of every individual combinator; the
  `Category` instance only needs the *existing* `compose`. MP-8
  doesn't need to wait for the wrapper to ship its combinators,
  and the wrapper doesn't need to wait for MP-8's combinators
  to ship `Profunctor`. Coupling them would slow both.
- *Skip the existential wrapper; ship typeclass instances on
  `forall s rs. SymTransducer phi rs s ci co` via constraint
  trickery.* Rejected: the futures note (§1) explains that the
  state parameter must be hidden for `(.)` to typecheck without
  leaking `(s1, s2)` into every composition; the wrapper is
  load-bearing.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Existential wrapper for SymTransducer + Profunctor instance + variance combinators | docs/plans/27-existential-wrapper-for-symtransducer-plus-profunctor-instance-and-variance-combinators.md | None | EP-11 (external) | Complete |
| 2 | Category instance on the SymTransducer wrapper | docs/plans/28-category-instance-on-the-symtransducer-wrapper.md | EP-1 | EP-11 (external) | Complete |
| 3 | Strong / Choice / Arrow instances on the SymTransducer wrapper | docs/plans/29-strong-choice-and-arrow-instances-on-the-symtransducer-wrapper.md | EP-1, EP-2 | MP-8 children (alternative shipped; parallel/Kleisli declined — see EP-29 Decision Log) | In Progress |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix.
"EP-11 (external)" is MP-4's child plan
`docs/plans/11-composition-combinators-on-symtransducer.md`,
which delivered the existing `compose`. "MP-8 children" refers to
`docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md`'s
per-combinator EPs (EP-25 `alternative` Complete, EP-26 `feedback1`
Complete, `parallel` and `Kleisli` re-deferred by EP-24's design
milestone — EP-29 ships `Strong` from primitives rather than
delegating to the absent `parallel`).

The actual plan paths in the table above were assigned by
`bun agents/skills/exec-plan/init-plan.ts` when the EPs were
created on 2026-05-03 (the next free plan numbers were 27, 28,
29 — MP-8's children took 25 and 26).


## Dependency Graph

```
        ┌──────────────────────────────────────────┐
        │ EP-11 (external) — existing `compose`    │
        └─────────────────────┬────────────────────┘
                              │ (soft)
                              ▼
                       ┌──────────────┐
                       │   EP-27      │
                       │  Wrapper +   │
                       │  Profunctor  │
                       └──────┬───────┘
                              │ (hard)
                ┌─────────────┼─────────────┐
                ▼                           ▼
         ┌──────────────┐           ┌──────────────┐
         │   EP-28      │           │   EP-29      │
         │  Category    │◀──(hard)──│  Strong /    │
         │              │           │  Choice /    │
         │              │           │  Arrow       │
         └──────────────┘           └──────┬───────┘
                                           │ (soft, partial)
                                           ▼
                                  ┌────────────────────┐
                                  │ MP-8 (alternative  │
                                  │ shipped; parallel  │
                                  │ declined)          │
                                  └────────────────────┘
```

EP-28 (`Category`) is independent of EP-29 (`Strong` / `Choice`)
in the sense that EP-28's `Category` instance does not depend on
EP-29's instances. However EP-29 *does* hard-depend on EP-28: the
`Arrow` instance extends `Category`, and `(>>>)` delegates to the
Category instance. So the order is EP-27 → EP-28 → EP-29.

EP-29's soft dependency on MP-8 reduced in scope when MP-8's
design milestone (EP-24) declined `parallel`. The `Choice`
instance still delegates to MP-8's `alternative` (already
shipped). The `Strong` instance is implemented from primitives in
EP-29 rather than waiting for `parallel`. The `ArrowChoice`
instance is dropped from scope (see EP-29 Decision Log).


## Integration Points

### IP-1: Existential wrapper newtype

**Plans involved:** EP-25 (defines), EP-26 / EP-27 (consume).

**Owner:** EP-27. The final shape (after EP-28's amendments) has
two constructors and a richer existential constraint set:

    data SomeSymTransducer ci co where
      SomeSymTransducer
        :: ( WeakenR rs
           , KnownSlotNames rs
           , Bounded s
           , Enum s
           )
        => SymTransducer (HsPred rs ci) rs s ci co
        -> SomeSymTransducer ci co
      SomeSymIdentity :: SomeSymTransducer a a

EP-27 actually shipped with **no** packed constraints (the body
of `data SomeSymTransducer ci co where SomeSymTransducer :: ... ->
SomeSymTransducer ci co`); the original IP-1 description's claim
that EP-27 ships with `WeakenR rs` was aspirational. EP-28's M1
added `(WeakenR rs, KnownSlotNames rs)`; EP-28's M2 added
`(Bounded s, Enum s)` and the second `SomeSymIdentity` constructor
(see Surprises & Discoveries for why the sentinel was needed).
All four constraints have automatic instances on every keiki
vertex / register-file shape, so each amendment was
backward-compatible at every existing call site.

**Coordination rule:** EP-28 and EP-29 use this wrapper. If
EP-29 discovers a missing constraint that's not already packed in
the existential, the responsible EP amends the wrapper (with a
backward-pointing note in EP-27's Decision Log). EP-28 has
already exercised this protocol three times: `KnownSlotNames`,
`WeakenR`, and `(Bounded, Enum)`. The pattern is well-trodden;
EP-29 should not hesitate.

**Pattern-match consumers must handle both constructors:** any
code that pulls a transducer out of the wrapper via
`case s of SomeSymTransducer t -> ...` is now non-exhaustive and
must add a `SomeSymIdentity -> ...` arm. The sentinel can be
materialised into a concrete identity transducer via
`SomeSymTransducer identityTransducer` if the consumer needs a
real `SymTransducer`.

### IP-2: `Keiki.Profunctor` (or sibling) module

**Plans involved:** all three EPs.

**Owner:** EP-25 creates the module and decides the export
surface. EP-26 and EP-27 add their instances to the same module
(or sibling files within the same `Keiki.Profunctor.*`
namespace). `Keiki.Composition` stays focused on standalone
combinator functions.

### IP-3: Identity transducer

**Plans involved:** EP-26 (defines, since `Category.id` needs
it).

**Owner:** EP-28. EP-28 ships **two** identity-related artefacts:

1.  `identityTransducer :: forall a. SymTransducer (HsPred '[] a)
    '[] IdVertex a a` — a concrete-form identity transducer using
    the **phantom-slot technique** (`InCtor a '[ '("payload", a) ]`
    + `WireCtor a (a, ())`; the real `initialRegs` stays `RNil`).
    Exported for users who need a real `SymTransducer`-shaped
    identity (e.g. for non-Category contexts, testing, or
    comparison fixtures).
2.  `SomeSymIdentity :: SomeSymTransducer a a` — a *sentinel
    constructor* on the wrapper GADT. `Cat.id` returns the sentinel;
    `Cat..` short-circuits when either operand is the sentinel.
    The sentinel exists because `Keiki.Composition.compose`'s
    substitution algorithm cannot accept a generic identity
    transducer — see EP-28's Surprises & Discoveries for the
    discovery and rationale.

**Coordination rule:** EP-29's `Arrow` instance reuses
`identityTransducer` directly when it needs a concrete identity
shape (e.g. for `arr`'s construction with the only difference
being `wcBuild = \(a, ()) -> f a` instead of `\(a, ()) -> a`).
The private helpers `identityInCtor` / `identityWireCtor` stay
private in EP-28; if EP-29 needs them, EP-29 promotes them via
a sub-module like `Keiki.Profunctor.Internal`. EP-29's `(>>>)`
inherits `Cat..`'s sentinel short-circuit automatically because
`(>>>)` defaults to `flip Cat..`.

### IP-4: MP-8 combinators (`parallel`, `alternative`)

**Plans involved:** EP-29.

**Owner:** MP-8. Status (as of MP-8's EP-24 design milestone,
Complete on 2026-05-03):

- `alternative` — **shipped** by MP-8's EP-25 (Complete).
  EP-29's `Choice` instance imports and delegates to it.
- `parallel` — **declined** by EP-24's design milestone.
  EP-29's `Strong` instance is implemented from primitives in
  EP-29 M2 (a one-off `firstSym`).
- `feedback1` — shipped by MP-8's EP-26 (Complete). Not used by
  MP-9.
- `Kleisli` — declined. Out of scope for MP-9.

**Coordination rule:** the original rule ("if MP-8 declines a
combinator, EP-29 drops the matching instance") was triggered for
`parallel` but EP-29 chose to *implement* `Strong` from primitives
rather than drop it. The implementation is small enough (~40 LoC)
that the in-house cost is preferred over losing the instance.
`ArrowChoice` is dropped (out of scope).


## Progress

Track milestone-level progress across all child plans. Each
entry names the child plan and the milestone.

- [x] EP-27: Verify prerequisites — Keiki.Composition builds, all tests pass; recorded GHC 9.12.3, baseline 185 examples 0 failures (M0, 2026-05-03)
- [x] EP-27: Picked Shape A (full-existential, HsPred-baked-in); documented in Decision Log (M1, 2026-05-03)
- [x] EP-27: Picked Option (c) — ship `lmapCi` with documented `solveOutput` loss; documented in Decision Log (M1, 2026-05-03)
- [x] EP-27: Created `Keiki.Profunctor`; shipped `lmapCi`, `rmapCo`, `dimapTransducer`, `lmapMaybeCi` on concrete SymTransducer (M2, 2026-05-03)
- [x] EP-27: Added `Profunctor` and `Functor` instances on the wrapper; 11 new tests assert variance contract; total 196/0 (M3, 2026-05-03)
- [x] EP-28 (2026-05-09): Settled disjointness via Option (A) — runtime overlap check + `unsafeCoerce`-fabricated `DictDisjoint`; raises `CategoryOverlapError` on collision (M1)
- [x] EP-28 (2026-05-09): Defined identity transducer via the phantom-slot technique; `identityTransducer` exported. `Cat.id` ultimately uses a sentinel constructor instead — see Surprises &amp; Discoveries (M1+M2)
- [x] EP-28 (2026-05-09): Amended EP-27's wrapper to pack `(WeakenR rs, KnownSlotNames rs, Bounded s, Enum s)` — adding `Bounded s, Enum s` beyond the originally-projected `KnownSlotNames` so symbolic analyses can run on unwrapped transducers (M1+M2)
- [x] EP-28 (2026-05-09): Added `Cat.Category SomeSymTransducer` with `SomeSymIdentity` sentinel constructor for `Cat.id`; `(.)` short-circuits on the sentinel and otherwise runs through a runtime overlap check + `compose`. `test/Keiki/CategorySpec.hs` covers L1/L2/L3 behaviourally, plus `CategoryOverlapError` and `isSingleValuedSym` survival; total 156/0 (baseline 146 + 10 CategorySpec) (M2)
- [ ] EP-29: Add `Choice` instance via `Keiki.Composition.alternative` (M1)
- [ ] EP-29: Implement `firstSym` from primitives (since MP-8 declined `parallel`); add `Strong` instance (M2)
- [ ] EP-29: Add `Arrow` instance with `arr` via stateless one-edge transducer (M3)
- [ ] EP-29: `ArrowChoice` declared out of scope (deferred to a future plan) (M3)


## Surprises & Discoveries

- 2026-05-03 / EP-27 authoring: `SymTransducer`'s input alphabet `ci`
  is **not** strictly contravariant. `Keiki.Core.solveOutput` calls
  `InCtor`'s `icBuild :: RegFile ifs -> ci`, which is *covariant* in
  `ci`. A naive `lmapCi :: (ci' -> ci) -> ...` cannot rewrite
  `icBuild` because it lacks the inverse direction. The futures note
  `docs/research/future-directions-profunctors-effects-and-composition.md`
  §1's variance argument was written for the v0 (pre-symbolic)
  Transducer that had no `solveOutput`; the v1 SymTransducer broke
  that variance story. EP-27's M1 owns the resolution (recommended
  option: lossy `lmapCi` with documented `solveOutput` caveat).
  Cross-EP impact: EP-29's `Choice` and `Strong` instances inherit
  the same lossy contract.

- 2026-05-03 / EP-28 authoring: `Keiki.Composition.compose` requires
  `Disjoint (Names rs1) (Names rs2)`. The wrapper hides `rs`, so the
  Category instance's general `(.)` cannot statically discharge this
  constraint. EP-28 chose the runtime-checked `unsafeCoerce` path:
  the instance reads each transducer's `KnownSlotNames` at the value
  level, checks for overlap, and either raises `CategoryOverlapError`
  or coerces the missing constraint into scope. EP-28 also amended
  EP-27's wrapper to pack `KnownSlotNames rs` so the runtime check
  has the slot-name strings available. Cross-EP impact: the same
  mechanism is reused by EP-29 for `Choice`'s `(+++)` operator.

- 2026-05-03 / EP-28 authoring: An identity transducer for an
  *arbitrary* alphabet `a` does **not** require `Generic`-driven or
  per-type machinery. A phantom one-slot register file
  `'[("payload", a)]` carried inside the `InCtor` and `WireCtor`
  lets a generic identity transducer roundtrip any value. The
  *real* `initialRegs` stays `RNil`. This resolves IP-3 ("Identity
  transducer") more cleanly than either of the originally-proposed
  options (`Generic`-derived or explicit per-type instances).

- 2026-05-03 / EP-29 authoring: MP-8's design milestone (EP-24,
  Complete on 2026-05-03) **declined `parallel`** as a separate
  combinator. MP-9's original vision assumed `Strong` would
  delegate to `parallel`. EP-29 ships `Strong` by implementing a
  one-off `firstSym` from primitives; the implementation is
  ~40 LoC. Cross-EP impact: this is the most novel work in MP-9;
  the implementation is described in EP-29 M2 with field-tuple
  math walkthroughs.

- 2026-05-03 / EP-29 authoring: The Arrow class's `arr :: (b -> c)
  -> arr b c` requires lifting an arbitrary Haskell function. The
  `Term` AST in `Keiki.Core` deliberately has no `TPure` /
  `TApply` constructor (so symbolic analysis remains tractable).
  Workaround: place the Haskell function inside the `WireCtor`'s
  `wcBuild` field, which is invoked only at runtime. The forward
  path works; `solveOutput` returns `Nothing` (no inverse). Same
  lossy contract as `lmapCi`/`rmapCo`/`first'`.

- 2026-05-09 / EP-28 implementation pivot:
  `Keiki.Composition.compose`'s substitution algorithm
  (`src/Keiki/Composition.hs:344` `substTerm` over
  `TInpCtorField`) requires `icName ic2 == wcName wc1`, raising a
  runtime "structural mismatch" error otherwise. A *generic*
  identity transducer's `InCtor` is named `"Identity"`; real
  upstream transducers emit differently-named wires (e.g.
  `"EmailSent"`). The substitution *cannot* succeed for
  `(SomeSymTransducer identityTransducer) Cat.. someEmail`. EP-28's
  M2 plan-of-work assumed `compose` would Just Work on the identity
  transducer; it does not.
  Resolution: EP-28 ships a sentinel constructor
  `SomeSymIdentity :: SomeSymTransducer a a` and short-circuits
  `Cat..` when either operand is the sentinel. The concrete
  `identityTransducer` stays exported (for non-Category use), but
  `Cat.id` returns the sentinel. Category laws hold by definition
  rather than by behavioural equivalence to a real identity
  transducer. The `Profunctor`/`Functor` instances materialise the
  sentinel into `identityTransducer` before applying their
  variance combinators, keeping `dimap`/`fmap` uniform across
  both wrapper shapes.
  Cross-EP impact for EP-29: the `Arrow` instance's `(>>>)` and
  `(<<<)` will inherit the same short-circuit (they delegate to
  `Cat..`). EP-29's `arr` should also produce a sentinel-shaped
  wrapper when the lifted function is the identity — or, more
  pragmatically, just delegate to `Cat.id` when the function is
  observably `id` (rare to detect; usually `arr id` will go
  through the regular `arr` path and that's fine).

- 2026-05-09 / EP-28 wrapper amendment expanded beyond M1's
  projection: the wrapper's existential constraint set grew from
  `()` (EP-27's actual ship) to
  `(WeakenR rs, KnownSlotNames rs, Bounded s, Enum s)`. M1
  projected `(WeakenR rs, KnownSlotNames rs)` only; `Bounded s,
  Enum s` were added in M2 so `isSingleValuedSym` and
  `checkHiddenInputs` can run on transducers pulled out of the
  wrapper. All four constraints have automatic instances on
  every keiki vertex / register-file shape, so the amendment is
  backward-compatible at every existing call site.
  Cross-EP impact: IP-1's wrapper-shape description (below) now
  reflects the final shape; EP-29 should expect to add further
  constraints if its `Strong`/`Choice`/`Arrow` instances need
  them, following IP-1's "Coordination rule".


## Decision Log

- Decision: Ship a separate module (`Keiki.Profunctor`) rather
  than extending `Keiki.Composition`.
  Rationale: Keeps `Keiki.Composition` focused on standalone
  combinator functions (the user-facing API for explicit
  composition). The existential wrapper and its typeclass
  instances are a different audience — users who want ecosystem
  interop and arrow notation. Splitting also lets us add a
  dependency on the `profunctors` package (if EP-25 chooses to)
  without forcing it onto every keiki user.
  Date: 2026-05-02

- Decision: EP C (`Strong` / `Choice` / `Arrow`) is a soft
  dependency on MP-8, not a hard one. The plan stays in the
  registry as Not Started; individual instances unlock as the
  underlying combinators ship.
  Rationale: MP-8 may decline a combinator (e.g. `alternative`
  may be re-deferred for a non-trivial mutual-exclusion check).
  A soft dep lets EP-27 ship whichever instances are
  unlockable; a hard dep would freeze EP-27 entirely if any
  combinator slips.
  Date: 2026-05-02

- Decision: No effectful (`EffTransducer m`) variant in scope.
  Rationale: `docs/research/effects-boundary.md` pins effects
  to the runtime layer. Effectful profunctor instances would
  cross that boundary and tie this MasterPlan's deliverable to
  decisions that haven't been made yet about runtime adapter
  shape.
  Date: 2026-05-02

- Decision: Wrapper shape is `data SomeSymTransducer ci co
  where SomeSymTransducer :: ... => SymTransducer (HsPred rs ci)
  rs s ci co -> SomeSymTransducer ci co` — i.e. `phi` is baked
  in as `HsPred rs ci`, not a free parameter.
  Rationale: `Keiki.Composition`'s `compose` / `alternative` /
  `feedback1` are all pinned to `HsPred` today. A `phi`-free
  parameter on the wrapper would expose a degree of freedom
  the composition combinators cannot consume. If a future plan
  generalises the combinators over `phi`, the wrapper grows a
  `phi` parameter then; the migration is straightforward.
  Date: 2026-05-03

- Decision: Profunctor's `lmapCi` (and by extension `dimapTransducer`,
  `Strong.first'`, `Choice.left'`/`right'`, `Arrow.arr`) ship with
  a documented loss: `solveOutput` returns `Nothing` on transducers
  produced by these combinators. Forward processing
  (`delta`/`omega` evaluation, `evalPred`, `evalTerm`) is unaffected.
  Rationale: `solveOutput` requires `InCtor.icBuild :: RegFile ifs
  -> ci`, which is covariant in `ci`. A contravariant `lmap` cannot
  produce a non-`undefined` `icBuild` for the new `ci'` without an
  `ci -> ci'` (which doesn't exist in general). Documenting the
  loss preserves ecosystem interop (standard `Profunctor` /
  `Strong` / `Arrow` typeclass shapes) at the cost of a guarantee
  that's primarily used for replay-from-events. Replay-on-lmapped
  transducers is a niche use case; users who need it can construct
  their transducers without going through the wrapper's
  combinators. Cross-cuts EP-27, EP-29.
  Date: 2026-05-03

- Decision: Disjointness in the `Category` and `Choice` instances'
  composition operators is enforced by a **runtime check**
  followed by `unsafeCoerce`-discharged constraint evidence; on
  overlap, raise a `CategoryOverlapError` exception. Documented in
  EP-28 M1.
  Rationale: the wrapper hides `rs`, so GHC has no static
  visibility for `Disjoint (Names rs1) (Names rs2)`. Three
  candidates (runtime-check + unsafeCoerce, slot renaming,
  unchecked compose) were considered; the runtime-check option is
  the only one that *catches* an overlap (with a clear exception),
  matches keiki's existing pattern (EP-18's raw `UCombine`), and
  doesn't require refactoring `Keiki.Composition`. Cross-cuts
  EP-28, EP-29.
  Date: 2026-05-03

- Decision: `ArrowChoice` is **out of scope** for MP-9.
  Rationale: declined during EP-29 authoring. `ArrowChoice`'s
  surface interacts with `arr`'s lossy contract in ways that
  complicate the test surface; defer to a future MasterPlan that
  wants the full Arrow-tower at once.
  Date: 2026-05-03

- Decision: `Strong` is **implemented from primitives** in EP-29
  rather than waiting for or reviving MP-8's declined `parallel`
  combinator.
  Rationale: MP-8's EP-24 design milestone declined `parallel`
  on the grounds that `alternative` covers keiki's runtime model.
  Reviving `parallel` would re-open MP-8's design decision; a
  one-off `firstSym` (~40 LoC) keeps the work contained in MP-9.
  See EP-29 M2 for the implementation walkthrough.
  Date: 2026-05-03

- Decision: Identity transducer for arbitrary alphabet uses the
  **phantom-slot technique** — a `'[("payload", a)]` slot list
  carried inside the `InCtor` and `WireCtor`, with the actual
  `initialRegs = RNil`.
  Rationale: settled during EP-28 authoring. Avoids both
  candidate strategies originally listed in IP-3 (`Generic`-driven
  derivation; per-type `IdentityWireCtor` instance). See EP-28's
  Decision Log for the worked example.
  Date: 2026-05-03

- Decision: `Cat.id` is a **sentinel constructor**
  (`SomeSymIdentity :: SomeSymTransducer a a`) on the wrapper
  GADT, not a wrap of `identityTransducer`. `Cat..` short-circuits
  on the sentinel.
  Rationale: discovered during EP-28 M2 implementation that
  `Keiki.Composition.compose`'s substitution algorithm
  (`substTerm` / `substPred`) requires `icName ic2 == wcName wc1`
  — the InCtor name on t2's reads must match the WireCtor name on
  t1's emissions. The generic identity transducer's InCtor is
  named `"Identity"`, which can never match an upstream wire's
  name (e.g. `"EmailSent"`); evaluating
  `(SomeSymTransducer identityTransducer) Cat.. someEmail` raises
  a runtime "structural mismatch" error. The sentinel sidesteps
  the substitution. The concrete `identityTransducer` stays
  exported for non-Category use (testing, composition with itself,
  etc.). Cross-cuts EP-28 (ships) and EP-29 (`Arrow` inherits the
  short-circuit via `(>>>) = flip Cat..`).
  Date: 2026-05-09

- Decision: Wrapper existential constraints final shape is
  `(WeakenR rs, KnownSlotNames rs, Bounded s, Enum s)` — three
  amendments over EP-27's actual ship of `()`.
  Rationale: each amendment was discovered as required by an
  EP-28 instance: `WeakenR` for `compose`'s constraint discharge,
  `KnownSlotNames` for the runtime slot-overlap check, and
  `(Bounded s, Enum s)` for symbolic analyses
  (`isSingleValuedSym`, `checkHiddenInputs`) that enumerate the
  vertex via `[minBound .. maxBound]`. All four are universally
  satisfied by keiki vertex / register-file shapes, so each
  amendment was backward-compatible. Future child plans (EP-29)
  may amend further per IP-1's coordination rule.
  Date: 2026-05-09


## Outcomes & Retrospective

(To be filled during and after implementation.)
