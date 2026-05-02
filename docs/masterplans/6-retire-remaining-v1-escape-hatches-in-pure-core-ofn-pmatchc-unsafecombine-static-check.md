---
id: 6
slug: retire-remaining-v1-escape-hatches-in-pure-core-ofn-pmatchc-unsafecombine-static-check
title: "Retire remaining v1 escape hatches in pure core (OFn, PMatchC, unsafeCombine static check)"
kind: master-plan
created_at: 2026-05-02T13:04:03Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
---

# Retire remaining v1 escape hatches in pure core (OFn, PMatchC, unsafeCombine static check)

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

The keiki library shipped a v2 pure core under MasterPlan 2
(`docs/masterplans/2-retire-v1-escape-hatches-in-pure-core-tinpproj-sbv-boolalg.md`).
That work retired the two v1 escape hatches named in EP-4's retrospective
(`TInpField` → `TInpCtorField`; the `OPack` hand-written inverse →
mechanical `solveOutput`) and made the `BoolAlg HsPred` instance
symbolically precise via SBV. MP-2's decision log entry dated 2026-05-01
explicitly **deferred three further v1 escape hatches** to "a future
MasterPlan once v2 lands":

1. **`OFn`** — `OutTerm`'s opaque `RegFile rs -> ci -> co` constructor.
   Authored through the `mkOut` helper. `solveOutput` cannot invert it,
   and `checkHiddenInputs` can only flag it. Currently used by the
   `Keiki.Examples.UserRegistration` aggregate's edges whose output
   shape doesn't fit the structural `OPack` form.

2. **`PMatchC`** — `HsPred`'s opaque `ci -> Bool` constructor. Authored
   through the `matchCmd` helper. The SBV-backed `BoolAlg` instance
   added in MP-2 EP-2 cannot translate `PMatchC` and falls back to
   "unknown / give up" (documented in `docs/research/sbv-boolalg-design.md`).
   MP-2 EP-2 added `PInCtor` / `matchInCtor` as a structural alternative
   for the constructor-equality case but kept `PMatchC` for back-compat.

3. **`unsafeCombine`** — the unchecked `UCombine` constructor on `Update`.
   The smart constructor `combine :: Update rs ci -> Update rs ci ->
   Either String (Update rs ci)` enforces "distinct targets" at runtime;
   `unsafeCombine` bypasses it. Used inside the User Registration
   aggregate (where multi-slot updates chain `unsafeCombine` for
   ergonomics) and inside `src/Keiki/Composition.hs` (where the two
   halves are disjoint by construction via `weakenLUpdate` /
   `substUpdate`).

This MasterPlan retires all three. The end-state contains:

- A structural successor to `OFn` covering the cases the User
  Registration and Email Delivery aggregates use today, plus a
  documented strategy for cases the structural form cannot express
  (deletion, formal-only, or kept as a rarely-used escape hatch — the
  design milestone decides). `mkOut` either becomes a structural helper
  or is gone.

- A structural successor to `PMatchC`. `matchInCtor` already covers
  constructor equality; the design milestone determines whether further
  constructors are needed (e.g. payload-pattern guards) or whether the
  PInCtor + first-class AST surface is sufficient. `matchCmd` either
  becomes sugar over the structural form or is gone.

- A static check on `unsafeCombine`'s "distinct targets" invariant. The
  likely shape is `Update (rs :: [Slot]) (written :: [Slot]) ci` (or an
  equivalent type-level set), with `UCombine` requiring a `Disjoint w1
  w2` constraint. The design milestone confirms the encoding and the
  migration story for `Keiki.Composition`'s composition-side use site
  (`src/Keiki/Composition.hs:416`), where the two halves write into
  weakened-disjoint slot ranges and any chosen encoding must admit this
  case ergonomically.

- All call sites in `src/Keiki/Examples/UserRegistration.hs` (V5),
  `src/Keiki/Examples/UserRegistrationV0.hs`, and
  `src/Keiki/Examples/EmailDelivery.hs` migrated. The composition use
  site in `src/Keiki/Composition.hs` continues to type-check (using a
  static-disjointness witness rather than the runtime check).

- `cabal test` green with no warnings about deprecated v1 escape
  hatches; the User Registration `reconstitute` smoke test still passes
  end-to-end and `isSingleValuedSym (withSymPred userReg) == True` is
  proved symbolically (the MP-2 acceptance gates remain green).

- Stale "v2 retires this" comments removed from `src/Keiki/Core.hs` and
  `docs/research/dsl-shape-for-symbolic-register.md`. The retirement
  list in those files is replaced by an "all retired" note pointing at
  this MasterPlan's Outcomes section.

The MasterPlan-level acceptance criterion: **`OFn`, `PMatchC`, and
`unsafeCombine` are removed from `Keiki.Core`'s exported surface (or
documented as hard-deprecated, per the design milestone's call); every
example aggregate compiles without them; the User Registration smoke
test and the symbolic `isSingleValuedSym` test both pass.**

In scope:

- A retirement strategy and successor surface for each of `OFn`,
  `PMatchC`, and `unsafeCombine`, decided in the design milestone (EP-15).
- The implementation work that follows from the design milestone's
  decomposition. Likely shape: one ExecPlan per retirement (EP-16 OFn,
  EP-17 PMatchC, EP-18 unsafeCombine static check), but the exact
  fan-out is the design milestone's output.
- Migration of `Keiki.Examples.UserRegistration` (V5),
  `UserRegistrationV0`, and `EmailDelivery` to the new surfaces.
- Static-disjointness reconciliation with `src/Keiki/Composition.hs`'s
  internal `unsafeCombine` use.
- A short retirement design note in `docs/research/` (one or
  per-retirement, design milestone decides).
- Stale-comment cleanup in `Keiki.Core` and the DSL design note.

Out of scope:

- **Item G of `keiki-generics-design.md`** — compile-time topology
  safety via a `SymTransducerStrict` parameterized over a type-level
  topology. The design note explicitly says this "is a separate
  MasterPlan-sized initiative" appropriate as a v3 direction. MP-3's
  Decomposition Strategy section repeats the deferral. This MasterPlan
  retires named v1 escape hatches; topology safety is orthogonal.
- `Keiki.Runtime` — a separate future MasterPlan covers the runtime
  layer (event store, queue, subscriptions, timers).
- The Order Fulfillment process manager (synthesis §5) — runtime
  smoke test, deferred to the runtime MasterPlan.
- New combinators on `SymTransducer`. MP-4 owns composition; further
  combinators (`feedback`, `alternative`, ...) follow MP-4's revision
  protocol, not this MasterPlan's.
- Acceptor projections / `genView` TH splice. MP-5 owns those.


## Decomposition Strategy

This MasterPlan starts with **one child ExecPlan**: EP-15, the *design
milestone*. EP-15's terminal output is a design note (or a set of
notes) plus a recommendation that either:

(a) Decomposes the work into per-retirement child ExecPlans (EP-16
    `OFn`, EP-17 `PMatchC`, EP-18 `unsafeCombine` static check), in
    which case this MasterPlan is updated via the standard revision
    protocol to add the new rows to the Exec-Plan Registry; or

(b) Concludes that one or more retirements are small enough to fold
    into EP-15 itself, or that two retirements should be bundled
    (e.g. `OFn` and `PMatchC` share a "structural successor for an
    opaque-function constructor" theme), in which case EP-15 either
    implements them directly or fans out into a smaller set of EPs.

The two-stage shape — design milestone first, fan-out afterwards —
follows the same pattern MP-4 used for composition combinators
(`docs/masterplans/4-composition-combinators-on-symtransducer.md`).
The pattern is appropriate when the right number of work units is not
yet knowable: enumerating per-retirement EPs upfront would force
premature decisions about whether retirements share design machinery
or remain orthogonal.

**Why a MasterPlan and not a single ExecPlan:**

Each of the three retirements has a distinct validation gate:

- `OFn` retirement: a green build with `Keiki.Examples` migrated to
  the new structural output form (or a documented decision that some
  edges keep the escape hatch).
- `PMatchC` retirement: a green build with all guards expressed
  structurally; the SBV instance no longer falls back to "unknown" on
  any guard in the example aggregates.
- `unsafeCombine` static check: the runtime "distinct targets" check
  in `combine` becomes redundant (or removed); `unsafeCombine` is
  removed; `Keiki.Composition`'s use site type-checks under the new
  disjointness witness.

A single ExecPlan covering all three would conflate three distinct
gates and force one to land without proving anything. The design
milestone determines whether some gates are bundled (e.g. if the OFn
and PMatchC successors share a typeclass or AST piece) and how the
implementation work is split.

**Why this is its own MasterPlan, not a child of MP-2, MP-3, MP-4, or MP-5:**

- *MP-2.* Closed; its 2026-05-01 retrospective marked it complete and
  its decision log explicitly excludes these three retirements.
  Reopening MP-2 violates the living-document protocol (which records
  what shipped, not what was punted on).
- *MP-3 (Generics DX follow-ups).* Closed; its scope is explicitly
  tied to items A/B/D/E from `keiki-generics-design.md`. The three
  retirements here are not "DX follow-ups" — they retire formal escape
  hatches in the DSL surface, not boilerplate at the example layer.
- *MP-4 (composition combinators).* In flight (EP-11 complete; further
  combinators may follow); the composition design touches
  `unsafeCombine` only at the use site in `src/Keiki/Composition.hs`,
  which the static check must accommodate. The static check is a
  consumer of MP-4's structural decisions, not a sibling of them. Soft
  dep, not bundle.
- *MP-5 (acceptor projections + genView).* Planned; orthogonal axis
  (projections out of `SymTransducer`, not changes to the DSL surface).

**Alternatives considered:**

- *Single ExecPlan covering the three retirements directly.* Rejected:
  three distinct validation gates and at least one (the static check)
  with non-trivial encoding decisions. A single EP cannot hold three
  design+impl pairs without exceeding the ExecPlan size guideline.
- *Three independent MasterPlans, one per retirement.* Rejected: the
  retirements share enough thematic coherence ("retire remaining v1
  escape hatches in the pure core") that a single MasterPlan provides
  better Decision Log and Surprises continuity. They also share
  coordination concerns (the composition use site of `unsafeCombine`,
  the User Registration migration burden) that a single MasterPlan
  manages cleanly.
- *Bundle the three with item G (topology safety) into a single "v3
  pure core" MasterPlan.* Rejected: item G is MasterPlan-sized on its
  own (per `keiki-generics-design.md` and MP-3's Decomposition
  Strategy). Bundling would balloon scope and conflate "retire named
  v1 escape hatches" with "redesign the transducer envelope for
  type-level topology."
- *Three EPs upfront (no design milestone).* Rejected: the encoding
  question for the static check, and the question of whether OFn and
  PMatchC share design machinery, both warrant a single design pass
  that produces a recommendation. Going straight to three EPs
  presupposes the decomposition.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Design milestone — decompose v1 escape hatch retirements (OFn, PMatchC, unsafeCombine static check) | docs/plans/14-design-milestone-decompose-v1-escape-hatch-retirements-ofn-pmatchc-unsafecombine-static-check.md | None | EP-7 (external), MP-4 children | In Progress |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix
(e.g., EP-1, EP-3). "EP-7 (external)" refers to
`docs/plans/7-upgrade-keiki-to-ghc-9-12.md`. "MP-4 children" refers
to `docs/masterplans/4-composition-combinators-on-symtransducer.md`'s
child plans (EP-11 and any per-combinator EPs that follow), because
the `unsafeCombine` static check must accommodate
`src/Keiki/Composition.hs`'s composition-side use of `unsafeCombine`.

This registry will grow when EP-15's design milestone fans out into
per-retirement EPs (see the Vision & Scope and Decomposition Strategy
sections above). EP-15's revision step appends rows for each
retirement that survives the design milestone.


## Dependency Graph

```
        ┌─────────────────────────────────────┐
        │ EP-7  (external) — GHC 9.12 upgrade │
        │ MP-4  (external) — Composition      │
        └──────────────────┬──────────────────┘
                           │ (soft)
                           ▼
                    ┌─────────────┐
                    │   EP-15     │
                    │  Design     │
                    │  milestone  │
                    └──────┬──────┘
                           │
                           │ (after design milestone)
                           ▼
              ┌────────────┴─────────────┐
              │  Per-retirement EPs      │
              │  (added by MP revision)  │
              └──────────────────────────┘
```

**EP-15 has no hard dependencies.** Its design milestone reads
`Keiki.Core`, `Keiki.Symbolic`, `Keiki.Composition`, and the example
aggregates; it produces a design note and a recommendation. No code
in the design milestone touches the user-facing API.

**Soft external deps:**

- *EP-7 (GHC 9.12 upgrade).* Recommended-soft-dep: type-level set
  manipulation (likely needed for the `unsafeCombine` static check)
  benefits from boot-library bumps, and CI alignment with sibling
  projects reduces friction. Each child EP's M0 milestone records
  the GHC version it was implemented under.
- *MP-4 children.* The `unsafeCombine` static check must accommodate
  `src/Keiki/Composition.hs:416`, where `weakenLUpdate (update e1)
  \`unsafeCombine\` substUpdate (update e2) o1` builds a composite
  edge update whose two halves are disjoint by construction (left
  writes into `rs1`'s prefix, right writes into `rs2`'s suffix). Any
  static encoding must admit this case without per-call-site proof
  obligations. If MP-4 introduces further combinators that use
  `unsafeCombine` internally, the static encoding must accommodate
  those too. The dependency is soft: EP-15's design milestone may
  proceed before further MP-4 combinators land, but its
  recommendation should anticipate them.


## Integration Points

### IP-1: `src/Keiki/Core.hs` — `Update`, `OutTerm`, `HsPred` constructor sets

**Plans involved:** EP-15 (design); per-retirement EPs (impl).

**Owner:** EP-15's design milestone owns the constructor-set
decisions. Each per-retirement EP owns its constructor-set change.

**Coordination rule:** if two retirements affect the same datatype
(none expected — `OFn` is in `OutTerm`, `PMatchC` is in `HsPred`,
`unsafeCombine` is in `Update`), the design milestone names which EP
owns the datatype during the migration window.

### IP-2: `src/Keiki/Composition.hs` — internal `unsafeCombine` use

**Plans involved:** the `unsafeCombine` retirement EP (per-retirement
EP-18 or whatever the design milestone names).

**Owner:** the `unsafeCombine` retirement EP.

**Coordination rule:** the new static-disjointness encoding must let
`weakenLUpdate (update e1) \`combine\` substUpdate (update e2) o1` (or
the renamed-static-`combine`) type-check without a per-call-site proof
obligation. The likely shape is that `weakenLUpdate` and `substUpdate`
each carry a `Disjoint`-friendly written-slot index, so the composite
disjointness witness is mechanical.

### IP-3: `src/Keiki/Examples/UserRegistration.hs`, `UserRegistrationV0.hs`, `EmailDelivery.hs`

**Plans involved:** every per-retirement EP (each owns its own DSL
migration; the example aggregates are the smoke test for each
retirement).

**Owner:** each retirement EP migrates the constructs it retires; the
last EP to land sweeps any remaining mixed-form usage.

**Coordination rule:** each EP's smoke test reuses the canonical User
Registration log (`reconstitute userReg canonicalLog == Just (Deleted,
expectedSnapshot)`) and the symbolic `isSingleValuedSym (withSymPred
userReg) == True` test. After all retirements land, both still pass.

### IP-4: New design notes in `docs/research/`

**Plans involved:** EP-15 (creates the design note(s)); per-retirement
EPs (amend their entry as the impl confirms or revises the design).

**Owner:** EP-15 owns the file structure. The design milestone may
decide to write one combined retirement note or one per retirement;
either is valid as long as the rationale is captured.

### IP-5: Stale-comment cleanup in `Keiki.Core` and `dsl-shape-for-symbolic-register.md`

**Plans involved:** every per-retirement EP that lands a retirement
removes its corresponding "future MasterPlan retires this" comment.

**Owner:** the last per-retirement EP to land sweeps the module-header
"v1 escape hatches still pending retirement" block in
`src/Keiki/Core.hs:22-33` and the closing list in
`docs/research/dsl-shape-for-symbolic-register.md:997-1006`.


## Progress

This section aggregates milestone-level progress across all child
plans for an at-a-glance view.

- [ ] EP-15: Verify prerequisites — Keiki.Core builds, all tests pass; record GHC version (M0)
- [ ] EP-15: Survey the three v1 escape hatches against the current Keiki.Core surface; pick retirement strategies; write design note(s) (M1)
- [ ] EP-15: Decide decomposition; if fan-out is needed, revise this MasterPlan to add per-retirement EPs (M2)
- [ ] EP-15: Verdict and handoff (M3)


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments,
or unexpected interactions between child plans. Provide concise
evidence.

(None yet.)


## Decision Log

- Decision: Item G of `keiki-generics-design.md` (compile-time topology
  safety via `SymTransducerStrict`) is out of scope for this
  MasterPlan.
  Rationale: The design note explicitly says item G "is a separate
  MasterPlan-sized initiative" appropriate as a v3 direction; MP-3's
  Decomposition Strategy repeats the deferral. Bundling it here would
  conflate "retire named v1 escape hatches" with a redesign of the
  transducer envelope.
  Date: 2026-05-02

- Decision: Two-stage shape — single design-milestone EP (EP-15)
  followed by MasterPlan revision into per-retirement EPs.
  Rationale: Same shape MP-4 used for composition combinators. The
  encoding question for the `unsafeCombine` static check, and the
  question of whether `OFn` and `PMatchC` share design machinery, both
  warrant a single design pass before fan-out. Going straight to three
  EPs presupposes the decomposition.
  Date: 2026-05-02

- Decision: Standalone MasterPlan rather than reopening MP-2 or
  bundling into MP-3/MP-4/MP-5.
  Rationale: MP-2 is closed; its decision log explicitly defers these
  three items to "a future MasterPlan once v2 lands." MP-3's scope is
  Generics DX follow-ups (items A/B/D/E from
  `keiki-generics-design.md`). MP-4 owns composition combinators. MP-5
  owns acceptor projections and genView. The three retirements share a
  thematic coherence (named v1 escape hatches in the pure-core DSL
  surface) that warrants a dedicated MasterPlan.
  Date: 2026-05-02


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at
completion. Compare the result against the original vision.

(To be filled during and after implementation.)
