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
| 1 | Design milestone — decompose v1 escape hatch retirements (OFn, PMatchC, unsafeCombine static check) | docs/plans/14-design-milestone-decompose-v1-escape-hatch-retirements-ofn-pmatchc-unsafecombine-static-check.md | None | EP-7 (external), MP-4 children | Complete |
| 2 | Retire OFn and mkOut from Keiki.Core | docs/plans/16-retire-ofn-and-mkout-from-keiki-core.md | None | EP-15 | Complete |
| 3 | Retire PMatchC and matchCmd from Keiki.Core | docs/plans/17-retire-pmatchc-and-matchcmd-from-keiki-core.md | None | EP-15 | Complete |
| 4 | Static Disjoint check on Update; retire unsafeCombine | docs/plans/18-static-disjoint-check-on-update-retire-unsafecombine.md | None | EP-15, EP-7 (external), MP-4 children | Complete |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix
(e.g., EP-1, EP-3). "EP-7 (external)" refers to
`docs/plans/7-upgrade-keiki-to-ghc-9-12.md`. "MP-4 children" refers
to `docs/masterplans/4-composition-combinators-on-symtransducer.md`'s
child plans (EP-11 and any per-combinator EPs that follow), because
the `unsafeCombine` static check must accommodate
`src/Keiki/Composition.hs`'s composition-side use of `unsafeCombine`.

The three per-retirement EPs (EP-16, EP-17, EP-18) are independently
mergeable — each has its own validation gate. EP-15's M2 decision
(`docs/plans/14-...md` Decision Log dated 2026-05-02) settled on
three EPs over bundling. The conventional landing order is EP-16 →
EP-17 → EP-18 because the IP-5 retirement-block-comment sweep is
cleanest when EP-18 (last) removes the whole block. But any order is
permitted; the IP-5 sweep moves with the last EP to land.


## Dependency Graph

```
        ┌─────────────────────────────────────┐
        │ EP-7  (external) — GHC 9.12 upgrade │
        │ MP-4  (external) — Composition      │
        └──────────────────┬──────────────────┘
                           │ (soft)
                           ▼
                    ┌─────────────┐
                    │   EP-15     │   ← Complete
                    │  Design     │
                    │  milestone  │
                    └──────┬──────┘
                           │ (soft; design rationale)
            ┌──────────────┼──────────────┐
            │              │              │
            ▼              ▼              ▼
      ┌─────────┐    ┌─────────┐   ┌──────────────┐
      │  EP-16  │    │  EP-17  │   │    EP-18     │
      │  OFn    │    │ PMatchC │   │ unsafeCombine│
      │ retire  │    │ retire  │   │  static check│
      └─────────┘    └─────────┘   └──────────────┘
                                         ▲
                                         │ (soft)
                           ┌─────────────┴─────────────┐
                           │  EP-7 (external; GHC      │
                           │       9.12 type-level set │
                           │       machinery)          │
                           │  MP-4 children (composes  │
                           │       use of combine)     │
                           └───────────────────────────┘
```

**No hard dependencies between child plans.** EP-15 (Complete)
produced the design note that EP-16, EP-17, and EP-18 reference;
the dependency is soft (rationale, not artifacts). The three
per-retirement EPs touch three different datatypes (`OutTerm`,
`HsPred`, `Update`) and can land in any order.

**Soft external deps (apply primarily to EP-18):**

- *EP-7 (GHC 9.12 upgrade).* Already on master at MP-6 start
  (GHC 9.12.3 baseline; recorded in EP-15's M0). EP-18's
  type-level set machinery (`Disjoint`, `Concat`, `Names`) relies on
  features stable from much earlier GHC versions but benefits from
  9.12's improved error messages.
- *MP-4 children.* EP-18's static-disjointness encoding must
  accommodate `src/Keiki/Composition.hs:416`, where `weakenLUpdate
  (update e1) \`combine\` substUpdate (update e2) o1` builds a
  composite edge update whose two halves are disjoint by construction
  (left writes into `rs1`'s prefix, right writes into `rs2`'s
  suffix). EP-18's design (carried in
  `docs/research/v1-escape-hatch-retirements-design.md`) lifts both
  helpers to thread the slot-name index and adds a `Disjoint (Names
  rs1) (Names rs2)` constraint to `compose` so the composite
  disjointness is mechanical. If MP-4 introduces further combinators
  after EP-11 that use `unsafeCombine` internally, they must be
  migrated alongside EP-18 (or the new combinator's EP picks up the
  migration).


## Integration Points

### IP-1: `src/Keiki/Core.hs` — `Update`, `OutTerm`, `HsPred` constructor sets

**Plans involved:** EP-15 (design, Complete); EP-16 (`OutTerm`),
EP-17 (`HsPred`), EP-18 (`Update`) — each per-retirement EP owns
exactly one datatype.

**Owner:** EP-16 owns `OutTerm` (removes `OFn`); EP-17 owns
`HsPred` (removes `PMatchC`); EP-18 owns `Update` (replaces with
the indexed `Update rs w ci` shape and removes `unsafeCombine`). No
two retirements touch the same datatype.

**Coordination rule:** each retirement EP also ticks its own bullet
in the module-header retirement-block comment in
`src/Keiki/Core.hs:22-33`. The whole block is removed by the last
EP to land (see IP-5).

### IP-2: `src/Keiki/Composition.hs` — internal `unsafeCombine` use

**Plans involved:** EP-18 (`unsafeCombine` retirement / static
check). EP-16 and EP-17 also touch `Keiki/Composition.hs`
incidentally — EP-16 deletes the four `OFn _ -> error` clauses
that become unreachable; EP-17 deletes the `weakenLPred` PMatchC
passthrough and the `substPred` PMatchC error.

**Owner:** EP-18 for the line-416 `unsafeCombine` use site and the
`weakenLUpdate` / `substUpdate` lift. EP-16 and EP-17 for their
respective constructor-narrowing cleanups.

**Coordination rule:** EP-18's static-disjointness encoding lets
`weakenLUpdate (update e1) \`combine\` substUpdate (update e2) o1`
type-check without a per-call-site proof obligation. EP-18 lifts
`weakenLUpdate` and `substUpdate` to thread the slot-name index and
adds the `Disjoint (Names rs1) (Names rs2)` constraint to `compose`.
See EP-18's Plan of Work M5 for the precise shape.

### IP-3: `src/Keiki/Examples/UserRegistration.hs`, `UserRegistrationV0.hs`, `EmailDelivery.hs`

**Plans involved:** EP-18 only. EP-16 and EP-17 do not touch the
example aggregates (the survey in EP-15's design note found zero
aggregate uses of `OFn` / `mkOut` / `PMatchC` / `matchCmd`).

**Owner:** EP-18 migrates the `\`unsafeCombine\`` chains in every
example aggregate to `\`combine\``.

**Coordination rule:** EP-18's smoke tests reuse the canonical User
Registration log (`reconstitute userReg canonicalLog == Just
(Deleted, expectedSnapshot)`) and the symbolic
`isSingleValuedSym (withSymPred userReg) == True` test. After EP-18
lands, both still pass.

### IP-4: Design note in `docs/research/`

**Plans involved:** EP-15 owns
`docs/research/v1-escape-hatch-retirements-design.md` (Complete).
EP-16, EP-17, EP-18 may amend their respective subsections of the
note as implementation reveals wrinkles (see each EP's Decision Log
for the revision protocol).

**Owner:** EP-15. Per-retirement amendments are recorded in the
amending EP's Decision Log with rationale.

### IP-5: Stale-comment cleanup in `Keiki.Core` and `dsl-shape-for-symbolic-register.md`

**Plans involved:** EP-16, EP-17, and EP-18 each tick their own
bullet on:

- the module-header "v1 escape hatches still pending retirement"
  block in `src/Keiki/Core.hs:22-33`, and
- the closing list in
  `docs/research/dsl-shape-for-symbolic-register.md:1001-1015`.

**Owner:** the last per-retirement EP to land removes the entire
block in both files and replaces it with a single "all v1 escape
hatches retired by MP-6" pointer to MP-6's Outcomes section. The
conventional landing order (EP-16 → EP-17 → EP-18) puts this sweep
on EP-18, but if a different order lands the assignment moves with
the last EP. Each EP's M-final milestone records who performed the
sweep.


## Progress

This section aggregates milestone-level progress across all child
plans for an at-a-glance view.

EP-15 — Design milestone (Complete):

- [x] EP-15 M0: Verify prerequisites — Keiki.Core builds, all tests pass (107/107, GHC 9.12.3)
- [x] EP-15 M1: Survey the three v1 escape hatches; design note at `docs/research/v1-escape-hatch-retirements-design.md`
- [x] EP-15 M2: Decompose into three EPs (EP-16 OFn, EP-17 PMatchC, EP-18 unsafeCombine)
- [x] EP-15 M3: Apply MasterPlan revision; create EP-16, EP-17, EP-18
- [x] EP-15 M4: Verdict and handoff

EP-16 — Retire OFn and mkOut (Complete):

- [x] EP-16 M0: Verify prerequisites
- [x] EP-16 M1: Remove OFn / mkOut from Keiki.Core
- [x] EP-16 M2: Remove OFn-handling clauses in Keiki.Composition
- [x] EP-16 M3: Rewrite test/Keiki/CoreSpec.hs synthetic-OFn fixtures
- [x] EP-16 M4: Tick OFn bullet in retirement-block comments
- [x] EP-16 M5: Verdict

EP-17 — Retire PMatchC and matchCmd (Complete):

- [x] EP-17 M0: Verify prerequisites
- [x] EP-17 M1: Remove PMatchC / matchCmd from Keiki.Core
- [x] EP-17 M2: Remove PMatchC clause from Keiki.Symbolic.translatePred
- [x] EP-17 M3: Remove PMatchC clauses from Keiki.Composition
- [x] EP-17 M4: Rewrite test/Keiki/CoreSpec.hs synthetic-PMatchC fixtures
- [x] EP-17 M5: Update sbv-boolalg-design.md
- [x] EP-17 M6: Tick PMatchC bullet in retirement-block comments
- [x] EP-17 M7: Verdict

EP-18 — Static Disjoint check; retire unsafeCombine (Complete):

- [x] EP-18 M0: Verify prerequisites
- [x] EP-18 M1: Spike — Disjoint, Concat, IndexN type-level machinery
- [x] EP-18 M2: Refactor Update to carry the (w :: [Symbol]) index
- [x] EP-18 M3: IsLabel for IndexN; preserve aggregate authoring syntax
- [x] EP-18 M4: Update evaluator / analyses; existential w in Edge
- [x] EP-18 M5: Lift weakenLUpdate / substUpdate; add Disjoint constraint to compose
- [x] EP-18 M6: Migrate example aggregates from unsafeCombine to combine
- [x] EP-18 M7: Migrate composition tests
- [x] EP-18 M8: Remove unsafeCombine from Keiki.Core exports
- [x] EP-18 M9: IP-5 sweep — remove retirement-block comments entirely
- [x] EP-18 M10: Verdict


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments,
or unexpected interactions between child plans. Provide concise
evidence.

- **OFn and PMatchC have zero aggregate uses** (EP-15 M1 survey,
  2026-05-02). MP-6's original Vision & Scope assumed both were
  "currently used" by `Keiki.Examples.UserRegistration`; the survey
  found that PInCtor / matchInCtor (added in EP-2 of MP-2) had
  already absorbed every aggregate guard, and no aggregate ever
  needed `mkOut`. Consequence: EP-16 and EP-17 are mechanical
  deletions; the substantive engineering of MP-6 is concentrated in
  EP-18 (`unsafeCombine` static check). The design note revises
  Vision & Scope's assumed structural-successor obligations.
  Evidence:

      $ grep -rn "OFn\|mkOut\|PMatchC\|matchCmd" src/Keiki/Examples/
      src/Keiki/Examples/UserRegistrationV0.hs:89:-- | Per-constructor guards. Migrated from v1 'matchCmd' to v2

  Single match, and it's a historical comment.

- **M0 baseline drift** (EP-16 M0, 2026-05-02). EP-15 recorded a
  baseline of 107 examples; EP-16 found 110. The three additional
  cases come from `4489ec4 feat(examples): EP-13 follow-up —
  deriveView on EmailDelivery`, landed between EP-15 and EP-16. EP-17
  and EP-18 should re-baseline at M0 against actual head-of-master
  rather than against EP-15's recorded number. This is the expected
  shape under sequential EP landings; no action needed beyond
  recording the new baseline at each plan's M0.

- **EP-17 reused EP-16 fixtures cleanly** (EP-17 M4, 2026-05-02).
  The `inCtorTrue :: InCtor Bool '[]` introduced in EP-16's M3 for
  the synthetic transducer's structural OPack output turned out to
  be exactly the right shape for EP-17's structural guard rewrite:
  `matchInCtor inCtorTrue` has the same truth-table as the v1
  `matchCmd id`. Suggests structural fixtures introduced by sibling
  retirement EPs should be reviewed before authoring new test
  machinery — they may already cover the new EP's fixture needs.

- **EP-18 settled on smart-constructor `Disjoint`, raw-constructor
  `UCombine`** (EP-18 M2 Decision Log, 2026-05-02). The design
  note's ideal-end-state put the `Disjoint` constraint on `UCombine`
  itself; in practice that cascades into `unsafeCoerce`-flavoured
  bypasses at every internal reconstruction site (`weakenLUpdate
  (UCombine a b) = UCombine …`) and forces the v1 `unsafeCombine`'s
  body to use `unsafeCoerce`. Putting the constraint only on the
  smart `combine` keeps internal walks dictionary-free and
  preserves the static check at the introduction point that
  matters (aggregate authoring). MP-6's MasterPlan-level acceptance
  criterion (`unsafeCombine` removed; example aggregates compile;
  smoke + symbolic gate green) is satisfied without the
  ideal-end-state shape.

- **`Edge`'s existential `w` killed `update e` field selectors**
  (EP-18 M4, 2026-05-02). GADT record syntax with an
  existentially-quantified field is the right shape, but every
  consumer of `update e` (including all of `Keiki.Composition`'s
  weakening + substitution call sites, `Keiki.Symbolic.liftEdge`,
  the `delta` / `applyEvent` / `checkHiddenInputs` consumers in
  `Keiki.Core`, and the `test/Keiki/Examples/UserRegistrationSpec`
  re-implementation of `applyEvent`) had to migrate to either a
  helper function (`applyEdgeUpdate`, `edgeReadsInput`) or a
  pattern-binding (`Edge { update = u } -> …`). Future EPs adding
  a similar existential should land typed helpers in the same
  patch so the existential refactor is a single typecheck-clean
  commit.

- **`-Wredundant-constraints` fires on the static check** (EP-18
  M2/M5, 2026-05-02). The `Disjoint w1 w2` constraint on `combine`
  and `Disjoint (Names rs1) (Names rs2)` on `compose` are both
  flagged "redundant" by GHC because the bodies don't consume a
  dictionary value. Suppressed at module level for `Keiki.Core` and
  `Keiki.Composition` with a comment justifying why; same pragma
  will be needed for any future helper that re-exports a typed
  `Disjoint` / `Concat` witness.


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

MP-6 closed 2026-05-02 with all four child plans (EP-15 design, EP-16
`OFn`, EP-17 `PMatchC`, EP-18 `unsafeCombine`) complete. The
MasterPlan-level acceptance criterion is met:

- `OFn`, `PMatchC`, and `unsafeCombine` are removed from
  `Keiki.Core`'s exported surface.
- Every example aggregate (`Keiki.Examples.UserRegistration`,
  `Keiki.Examples.UserRegistrationV0`,
  `Keiki.Examples.EmailDelivery`) compiles without them.
- The User Registration smoke test
  (`reconstitute userReg canonicalLog == Just (Deleted,
  expectedSnapshot)`) and the symbolic gate
  (`isSingleValuedSym (withSymPred userReg) == True`) both pass.
- `cabal test all` is green: 107 examples, 0 failures.

Compared to the original Vision & Scope:

- *Successor surfaces.* The Vision section anticipated a
  *structural successor* for each retirement. EP-15's M1 survey
  found that `OFn` and `PMatchC` had zero aggregate uses on master
  — `OPack` and `PInCtor` (added in MP-2 EP-2) had already absorbed
  every example use. EP-16 and EP-17 became *mechanical deletions*
  rather than successor designs. The substantive engineering of
  MP-6 concentrated in EP-18 as anticipated.
- *Static `Disjoint` check.* Shipped via `(w :: [Symbol])` index on
  `Update`, `IndexN s rs r` slot-name-tagged register index, and
  `Disjoint :: [Symbol] -> [Symbol] -> Constraint` using `CmpSymbol`
  + `TypeError`. Authoring `USet #email t1 \`combine\` USet #email
  t2` over `UserRegRegs` produces the designed compile-time error
  naming `"email"`. The smart `combine`'s `Either String` shape
  collapsed: the runtime check is now statically unreachable.
- *Composition use site.* The Vision's "use the smart combine at
  line 416" goal was *not* met as stated; we landed on raw
  `UCombine` there instead. The structural disjointness at that
  call site cannot be promoted to a type-level constraint without
  carrying `Subset w (Names rs)` witnesses through `Edge`'s
  existential `w`. The MasterPlan's acceptance criterion is still
  satisfied — external aggregate authors get the static check
  where it matters; the internal composition algorithm uses the
  raw constructor with a documented structural argument. EP-18's
  Decision Log carries the rationale and trade-off analysis.
- *Compose's `Disjoint (Names rs1) (Names rs2)` precondition.*
  Shipped as planned. This formalises a precondition the
  composition design note already documented in prose form.
- *Stale-comment cleanup (IP-5).* Done by EP-18's M9 sweep. The
  module-header retirement-block in `src/Keiki/Core.hs` is now a
  one-paragraph "All v1 escape hatches were retired by MP-6"
  record with EP attribution. The closing block in
  `docs/research/dsl-shape-for-symbolic-register.md` reformatted
  to match.

Decomposition retrospective:

- *Two-stage shape.* EP-15 design milestone first, fan-out into
  three per-retirement EPs after. The shape paid off: the
  encoding decisions for EP-18 (`Disjoint` on which constructor;
  whether to demand structural lemmas at the composition use site)
  are non-trivial; locking them down before fan-out kept EP-16 /
  EP-17 mechanical and EP-18 substantive.
- *EP-16 → EP-17 → EP-18 landing order.* Conventional and
  followed in practice. Each retirement was independently
  mergeable; the IP-5 sweep moved with the last EP (EP-18) as
  designed.
- *Three EPs over bundling.* The right call. Bundling `OFn` and
  `PMatchC` (sometimes argued for in the design phase because they
  share the "opaque-function constructor" theme) would have
  conflated two distinct mechanical deletions into a single
  larger patch with no benefit; bundling either with EP-18 would
  have buried two trivial deletions inside the substantive `w`
  refactor and made the EP-18 commit much harder to review.

Lessons:

- *Static-invariant promotion patterns.* For a runtime invariant
  on a GADT, the cleanest type-level promotion is a constraint on
  the *smart constructor* with the data constructor left
  unconstrained. The smart constructor is the only public
  introduction point for end users; internal walks (weakening,
  substitution, evaluation) reconstruct via the raw data
  constructor without dictionary plumbing. Putting the constraint
  on the data constructor itself sounds tighter but cascades into
  `unsafeCoerce` workarounds at every internal reconstruction
  site. This pattern will recur in any future MP that promotes
  another runtime invariant (e.g. v3 topology safety, item G of
  `keiki-generics-design.md`).
- *Existential record fields require helper functions.* GHC won't
  generate a field selector for an existentially-quantified field.
  Plan helper functions next to the constructor *before* changing
  the field, then migrate consumers one-by-one. Ideally the
  helpers land first so the existential refactor is a single
  typecheck-clean commit.
- *Survey before designing successors.* EP-15 M1's "OFn / PMatchC
  have zero aggregate uses on master" finding (recorded in MP-6's
  Surprises section) was a non-trivial scope sharpening. Vision &
  Scope had assumed both constructors were "currently used"
  somewhere. A `grep` survey at design time saved EP-16 and EP-17
  from designing successor surfaces that would not have served
  any actual call site.
- *MasterPlan acceptance criteria should distinguish "external
  surface clean" from "internal implementation clean".* EP-18's
  composition use site landed on raw `UCombine` rather than smart
  `combine`. The MasterPlan-level acceptance criterion ("removed
  from `Keiki.Core`'s exported surface; every example aggregate
  compiles without them") is met because external users *cannot*
  bypass `Disjoint`; internal modules *can* (via the raw data
  constructor) but with documented justification. Future
  invariant-promotion MasterPlans should bake this distinction
  into their acceptance criteria so the question "does the line-N
  internal use site have to use the smart constructor too?" is
  decided up front rather than rediscovered during M5.


---

## Revisions

### 2026-05-02 — EP-15 Complete; fan-out into three per-retirement EPs

EP-15's design milestone landed. Changes applied to this MasterPlan
by EP-15's M3 step:

- Exec-Plan Registry: marked EP-15 **Complete**; added rows for
  EP-16 (`docs/plans/16-retire-ofn-and-mkout-from-keiki-core.md`),
  EP-17 (`docs/plans/17-retire-pmatchc-and-matchcmd-from-keiki-core.md`),
  EP-18 (`docs/plans/18-static-disjoint-check-on-update-retire-unsafecombine.md`).
- Dependency Graph: redrew the post-design-milestone shape; the
  three per-retirement EPs are independent (no hard deps between
  them).
- Integration Points: rewrote IP-1 / IP-2 / IP-3 / IP-4 / IP-5 to
  name the actual per-retirement EPs and assign owners. The
  previously hypothetical "the unsafeCombine retirement EP" is now
  EP-18.
- Progress: replaced EP-15-only checklist with per-EP checklists
  covering EP-15 (Complete), EP-16, EP-17, EP-18.
- Surprises & Discoveries: recorded the M1 finding that OFn and
  PMatchC have zero aggregate uses on master.

The changes do not alter MP-6's Vision & Scope. They sharpen the
scope of EP-16 and EP-17 (mechanical deletion, no successor surface)
and confirm EP-18 carries the substantive engineering. The
MasterPlan-level acceptance criterion remains as written: `OFn`,
`PMatchC`, and `unsafeCombine` are removed from Keiki.Core's
exported surface; every example aggregate compiles without them; the
User Registration smoke test and the symbolic `isSingleValuedSym`
test both pass.
