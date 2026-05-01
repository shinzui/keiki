---
id: 2
slug: retire-v1-escape-hatches-in-pure-core-tinpproj-sbv-boolalg
title: "Retire v1 escape hatches in pure core (TInpProj + SBV BoolAlg)"
kind: master-plan
created_at: 2026-05-01T16:14:27Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
---

# Retire v1 escape hatches in pure core (TInpProj + SBV BoolAlg)

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

The keiki library shipped a v1 pure core under MasterPlan 1
(`docs/masterplans/1-validate-symbolic-register-direction-via-haskell-prototype.md`).
That work proved the symbolic-register transducer formalism works on a worked
aggregate (User Registration from synthesis §4) and produced a verdict in
EP-4's Outcomes & Retrospective: **the synthesis holds, with one v1 deviation
that v2 retires.** The v1 deviation is a hand-written `RegFile rs -> co -> Maybe ci`
inverse on the `OPack` output constructor, present because the chosen v1
`Term` constructor set has `TInpField :: (ci -> r) -> Term rs ci r` as the
only input-reading constructor — and `TInpField` wraps an opaque Haskell
function that `solveOutput` cannot mechanically invert.

EP-4's retrospective named two v2 priorities, in order:

1. *Structural input projection (TInpProj or Generic-derived) retiring
   TInpField and removing the OPack hand-written inverse.*
2. *SBV-backed BoolAlg instance for symbolic emptiness/equivalence.*

This MasterPlan delivers both. After both child plans are complete, the
repository contains:

- A new structural input-projection constructor on `Term` in
  `src/Keiki/Core.hs`. The opaque `TInpField` constructor is gone (or
  documented as a hard-deprecated escape hatch, per EP-1's design
  exploration). The `inp` helper is gone or rewritten on top of the
  structural constructor.
- The hand-written inverse field on `OPack` is gone. `solveOutput` walks
  the structural `OutFields` and the new input-projection constructor
  mechanically, producing `Maybe ci` from any structurally-complete edge
  output without per-edge user code.
- An SBV-backed (or z3-haskell-backed; the solver is picked during EP-2's
  design exploration) `BoolAlg` instance. `sat` returns concrete witnesses;
  `isBot` answers symbolically; `isSingleValued` upgrades from the v1
  syntactic conservative approximation to a real symbolic check.
- The `Keiki.Examples.UserRegistration` and `Keiki.Examples.UserRegistrationV0`
  aggregates are migrated to the new structural surface. The V5 aggregate
  no longer carries any hand-written inverse; the V0 aggregate's
  hidden-input demonstration still fires (the check is now narrower and
  more precise).
- Two new design notes in `docs/research/` (`tinpproj-design.md`,
  `sbv-boolalg-design.md`) capturing the v2 decisions for future readers.
- A test suite that demonstrates four things:
  1. `reconstitute userReg canonicalLog == Just (Deleted, expectedRegs)`
     still passes, but with no `OPack` inverse anywhere in the
     `userReg` definition.
  2. The hidden-input check still fires on the unfixed V0 schema, with
     a more precise warning that names the exact missing input field.
  3. `sat` on a hand-constructed satisfiable predicate returns a concrete
     witness `(RegFile rs, ci)`.
  4. `isSingleValued userReg == True` (proved symbolically).

The MasterPlan-level acceptance criterion: **all four test categories pass,
the User Registration aggregate compiles with no per-edge `OPack` inverse,
and `cabal build` succeeds with no warnings about unreachable v1 escape
hatches.**

In scope:

- The new structural input-projection constructor on `Term` and the
  removal of `TInpField`.
- Removal of the hand-written inverse field from `OPack`.
- A new SBV-backed `BoolAlg` instance.
- Smarter `sat`, `isBot`, `isSingleValued`.
- Migration of `Keiki.Examples.UserRegistration` and `UserRegistrationV0`.
- Two short design notes.

Out of scope:

- Retirement of `OFn` (opaque `RegFile rs -> ci -> co` output). This is a
  separate v2 escape hatch for unusual outputs and is not used by the
  User Registration aggregate; not blocking.
- Retirement of `PMatchC` (opaque `ci -> Bool` predicate). The
  per-constructor `isStart`/`isConfirm`/... helpers in
  `Keiki.Examples.UserRegistration` paper over the ergonomic pain. EP-2
  will document how the SBV instance treats `PMatchC` (likely as
  "unknown / give up").
- A static check on `unsafeCombine`'s "distinct targets" invariant.
- `Keiki.Runtime` — a separate future MasterPlan covers the runtime
  layer (event store, queue, subscriptions, timers).
- The Order Fulfillment process manager (synthesis §5) — runtime
  smoke test, deferred to the runtime MasterPlan.
- Any existing v1 cabal flags or dependency surgery beyond adding the
  chosen solver library.


## Decomposition Strategy

The initiative decomposes into **two child ExecPlans**, one per v2
priority named in EP-4's retrospective:

- **EP-1** retires the input-side opacity: `TInpField` becomes structural
  and the `OPack` hand-written inverse goes away.
- **EP-2** retires the predicate-side opacity: a new `BoolAlg` instance
  backed by an SMT solver answers `sat`/`isBot`/`isSingleValued`
  symbolically.

The two changes are mostly orthogonal — `Term` shape is one sub-system,
the `BoolAlg` instance is another — but EP-1 makes EP-2's life easier.
Without EP-1, an SBV translation of `Term` cannot recurse through
`TInpField` (opaque function) and must fall back to "unknown" or a
syntactic over-approximation. With EP-1, the translation walks the
structural input-projection constructor and produces a precise SBV
expression. This is a soft dependency, not a hard one: EP-2 has the
option to carve a separate symbolic-Term variant if EP-1 has not landed
when EP-2 starts. EP-2's design milestone makes that call explicitly.

Sharpening is folded into each ExecPlan as an early "design exploration"
milestone (M1) that produces a focused design note in `docs/research/`.
This deviates from MasterPlan 1's pattern (separate sharpening plans
followed by a separate prototype plan); the rationale is captured below.

**Why two plans, not four:**

MasterPlan 1 split sharpening from implementation because the v1 work
designed the entire pure core from scratch — `Term`, `OutTerm`, `Update`,
`HsPred`, `RegFile`, `Index`, `BoolAlg`, the effects boundary, the
schema-evolution model. Three orthogonal areas, each requiring a
substantial design note before any code could be written.

The v2 work retires two named escape hatches in an existing API. The
shape of each change is constrained by EP-4's verdict and the existing
design notes:

- For EP-1, the v1 DSL note already lists "TInpProj or Generic-derived
  input projection" as the v2 retirement path; the design space is "pick
  one of four candidates and explain why." That is a single-milestone
  decision, not a multi-week design effort.
- For EP-2, the synthesis note (§7) already names SBV as the v2 backend
  and the direction-C note (§5 SMT-backed phase) sketches the curated
  supported subset. The design space is "pick a solver, decide the
  translatable subset, decide how unsupported terms fall back."

A separate sharpening plan would gate impl on a 200-300 line note that
the impl author would have to re-read anyway. Folding the design
milestone into the impl plan keeps the design close to the code that
exercises it.

**Why two plans, not one:**

The two changes touch different sub-systems and have different solver
needs. EP-1 is pure type design — no new dependencies, no IO. EP-2
introduces a solver dependency (SBV pulls in z3 at runtime) and a new
class of failure modes (solver timeouts, unsupported terms). Bundling
them into one plan would conflate two distinct validation gates ("is
the new Term shape ergonomic?" vs. "does the symbolic check produce
useful answers on real transducers?") and force one of them to land
without proving anything.

**Alternatives considered:**

- *Single ExecPlan covering both retirements.* Rejected for the reasons
  above: distinct subsystems, distinct failure modes, distinct
  validation gates.
- *Four-plan decomposition (sharpen + impl × 2), mirroring MasterPlan 1.*
  Rejected: the v2 design space is small enough that a separate
  sharpening plan would add coordination overhead without proportional
  design value. The design milestone inside each impl plan does the same
  work without the round-trip.
- *Defer EP-2 until after EP-1's retrospective is reviewed.* Rejected:
  EP-2 has a soft dep on EP-1, so they naturally run in sequence; an
  explicit deferral gate adds nothing. If EP-1 surfaces a surprise that
  changes EP-2's premise, the standard MasterPlan revision protocol
  cascades the change.
- *Include `OFn` and `PMatchC` retirement.* Rejected for v2 scope: the
  EP-4 retrospective named only TInpField/OPack-inverse and SBV BoolAlg.
  Adding two more retirements would balloon the work. They become
  separate items in a future MasterPlan once v2 lands.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Replace TInpField with structural input projection (TInpProj) | docs/plans/5-replace-tinpfield-with-structural-input-projection-tinpproj.md | None | None | Complete |
| 2 | SBV-backed BoolAlg instance for symbolic emptiness | docs/plans/6-sbv-backed-boolalg-instance-for-symbolic-emptiness.md | None | EP-1 | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-1, EP-3).

The plan files are numbered 5 and 6 because plans 1 through 4 belong to
MasterPlan 1 (`docs/masterplans/1-validate-symbolic-register-direction-via-haskell-prototype.md`).
The shared `docs/plans/` directory is single-namespace.


## Dependency Graph

```
       ┌──────────┐
       │  EP-1    │
       │ TInpProj │
       └────┬─────┘
            │  (soft)
            ▼
       ┌──────────┐
       │  EP-2    │
       │   SBV    │
       │ BoolAlg  │
       └──────────┘
```

**EP-1 has no dependencies.** It touches only `src/Keiki/Core.hs`, the two
example modules under `src/Keiki/Examples/`, and the corresponding tests.
No new cabal dependencies. The work is internal to the pure layer; nothing
else in the repository depends on the v1 `TInpField` or the `OPack`
hand-written inverse.

**EP-2 has a soft dependency on EP-1.** The reason is that EP-2's SBV
translation of `Term` benefits from the structural input-projection
constructor EP-1 introduces. With the v1 opaque `TInpField`, an SBV
translation cannot recurse through the input-reading constructor and must
either fall back to "unknown" (returning conservative answers) or carve
a separate symbolic-Term variant that does not include `TInpField`. With
EP-1 done, the SBV translation walks the structural constructor directly
and produces precise answers.

The dependency is soft because EP-2 has a documented fallback (separate
symbolic-Term variant). EP-2's M1 design milestone makes the decision
explicitly: "build SBV translation on EP-1's structural Term" or "build
a separate symbolic-Term variant." If EP-1 has landed by the time EP-2
starts, the choice is the former by default.

**Phasing:**

- *Phase 1 — EP-1.* Design exploration (M1), then implementation
  (M2-M7), then migration of the example aggregates and tests (M8).
- *Phase 2 — EP-2.* Design exploration (M1) with the EP-1 status check,
  then dependency setup and translation (M2-M5), then symbolic
  analyses (M6-M7), then verdict (M8).

A single contributor implementing both plans in sequence is the
expected mode. Parallel implementation by two contributors is possible
but introduces the EP-2 fallback question explicitly; in that case
EP-2's M1 should pick the separate-symbolic-Term variant unless it can
synchronize with EP-1's design milestone.


## Integration Points

The two plans share four artifacts that this section names explicitly so
that later decisions made in either plan don't violate the other's
assumptions.

### IP-1: The `Term` constructor set in `src/Keiki/Core.hs`

**Plans involved:** EP-1 (defines new structural constructor, retires
`TInpField`), EP-2 (translates `Term` to SBV symbolic values).

**Owner:** EP-1.

**Coordination:** EP-2's M1 design milestone reads the new constructor
set before deciding whether to build the SBV translation on it. Two
outcomes are valid:

- *Build SBV on the new structural `Term`.* Requires EP-1 to be Complete
  (or at least M3 done — when the new constructor exists alongside the
  retiring `TInpField`). EP-2's translation walks the structural
  constructor directly. Precision is high.
- *Build SBV on a separate symbolic-Term variant.* Used only if EP-2 must
  run before EP-1 lands, or if EP-1's chosen shape turns out to be
  hostile to SBV (a discovery that goes in this MasterPlan's Surprises &
  Discoveries). The variant lives in `Keiki.Core` (or a new
  `Keiki.Symbolic` module) and is documented in EP-2's design note.

**Coordination rule:** if EP-1's design milestone discovers a shape that
would force EP-2 to take the separate-variant fallback, document the
finding in EP-1's Surprises & Discoveries and cascade to this MasterPlan.

### IP-2: The `OPack` constructor signature in `src/Keiki/Core.hs`

**Plans involved:** EP-1 (drops the hand-written inverse field), EP-2 (no
direct touch).

**Owner:** EP-1.

**Coordination:** EP-1's M4 milestone removes the
`(RegFile rs -> co -> Maybe ci)` field from `OPack`. After M4, every
construction site in `Keiki.Examples.UserRegistration` and
`UserRegistrationV0` must change. EP-1 is responsible for both the
constructor change and the example migration; the change is atomic in
one milestone (M5 for V5, M6 for V0).

EP-2 does not touch `OPack`. The connection is one-way: `solveOutput`'s
mechanical inversion (post-EP-1) means the `BoolAlg` instance can rely
on `Term` being structural without worrying about edge-by-edge inverses.

### IP-3: The `BoolAlg` class methods (`sat`, `isBot`, `isSingleValued`)

**Plans involved:** EP-2 (replaces or adds an instance with non-trivial
implementations).

**Owner:** EP-2.

**Coordination:** EP-1 does not touch `BoolAlg`. The dependency direction
is `BoolAlg` → `Term`, not the reverse: a `BoolAlg` instance for `HsPred`
must translate the `Term`s inside `PEq`, but `Term` itself does not know
about `BoolAlg`. EP-2 must read EP-1's chosen `Term` constructor set
before writing the translation; EP-1 does not need to read anything from
EP-2.

`isSingleValued :: SymTransducer phi rs s ci co -> Bool` (currently
exposed but best-effort in v1, per `docs/research/effects-boundary.md`)
is upgraded by EP-2 from "any two outgoing edges' guards have a
non-trivially-bot conjunction" syntactic check to a symbolic
`isBot (conj g₁ g₂)` over the new SBV-backed instance.

### IP-4: User Registration smoke test

**Plans involved:** EP-1 (migrates DSL surface usage), EP-2 (adds
symbolic `isSingleValued` test).

**Files:**

- `src/Keiki/Examples/UserRegistration.hs` — the V5 (fixed-schema)
  aggregate. Currently uses `TInpField` via `inpStart`/`inpConfirm`
  /`inpResend`/`inpGdpr` helpers and supplies a hand-written inverse on
  every `OPack`. After EP-1: structural input reads, no hand-written
  inverses.
- `src/Keiki/Examples/UserRegistrationV0.hs` — the V0 (unfixed) aggregate
  that demonstrates the hidden-input check firing. After EP-1: same
  structural surface, but the V0 inversion is no longer "hand-written
  returns Nothing"; it is now structurally observable that the
  `AccountConfirmed` event lacks a field that the update or guard reads.
- `test/Keiki/Examples/UserRegistrationSpec.hs` — the V5 smoke test.
  After EP-1: same assertions, no inverse-related code paths.
- `test/Keiki/Examples/UserRegistrationV0Spec.hs` — the V0 hidden-input
  test. After EP-1: stricter assertion on the warning's content (it now
  names the exact missing field).
- After EP-2: a new test asserting `isSingleValued userReg == True`
  (symbolically proved).

**Owner:** EP-1 owns the DSL migration; EP-2 owns the new symbolic test.

**Coordination rule:** EP-2's symbolic-`isSingleValued` test runs against
the EP-1-migrated aggregate, not the v1 form. If EP-2 starts before EP-1
finishes, the test runs against whatever form `userReg` is in at that
point and is rewritten in EP-1's M8 to the final form.

### IP-5: New design notes in `docs/research/`

**Plans involved:** EP-1 produces `docs/research/tinpproj-design.md`;
EP-2 produces `docs/research/sbv-boolalg-design.md`.

**Owner:** each plan owns its own note.

**Coordination:** EP-2's note should cite EP-1's chosen `Term` shape
explicitly (filename + section anchor) and document the fallback if EP-1
has not produced its note yet. The two notes are intended to be readable
side-by-side as the v2 design record.


## Progress

This section aggregates milestone-level progress across all child plans
for an at-a-glance view.

- [x] EP-1: Verify prerequisites — Keiki.Core builds, all tests pass (M0)
- [x] EP-1: Survey TInpProj shapes; pick one; write design note (M1)
- [x] EP-1: Add new structural input-projection constructor to `Term` (M2)
- [x] EP-1: Update evaluator and analyses to handle the new constructor (M3)
- [x] EP-1: Drop hand-written inverse field from `OPack`; mechanically
      derive `solveOutput` (M4)
- [x] EP-1: Migrate `Keiki.Examples.UserRegistration` (V5) (M5)
- [x] EP-1: Migrate `Keiki.Examples.UserRegistrationV0` (V0) (M6)
- [x] EP-1: Remove `TInpField` constructor and `inp` helper from public API (M7)
- [x] EP-1: Update DSL design note; capture verdict (M8)
- [ ] EP-2: Verify prerequisites — record EP-1 status; build passes (M0)
- [ ] EP-2: Survey solvers; pick one; decide translation subset; write
      design note (M1)
- [ ] EP-2: Add solver dependency to `keiki.cabal` (M2)
- [ ] EP-2: Implement `Term`-to-symbolic translation (M3)
- [ ] EP-2: Implement new `BoolAlg` instance (`top`, `bot`, conj/disj/neg) (M4)
- [ ] EP-2: Implement symbolic `models`, `sat`, `isBot` (M5)
- [ ] EP-2: Implement symbolic `isSingleValued` (M6)
- [ ] EP-2: Add tests; verify `isSingleValued userReg == True` (M7)
- [ ] EP-2: Update DSL note's BoolAlg section; capture verdict (M8)


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments, or
unexpected interactions between child plans. Provide concise evidence.

- *2026-05-01 (during EP-1 M6).* The original M1 design pinned
  `OPack :: WireCtor co fields -> OutFields rs ci fields -> OutTerm rs
  ci co`, expecting `solveOutput` to discover the `InCtor` from
  `TInpCtorField` reads inside `OutFields`. This breaks for edges
  whose input has no payload — notably `Continue` in the User
  Registration aggregate, which has no fields and therefore cannot
  appear inside any `OutFields` (`Index '[] r` is uninhabited). The
  redesign adds an explicit `InCtor ci ifs` first argument to `OPack`;
  `solveOutput` walks the structural `OutFields` against the named
  `InCtor`, which means an empty-payload constructor recovers
  trivially as `icBuild ic RNil`. EP-2 should treat `OPack`'s shape
  as "InCtor + WireCtor + OutFields"; the design note
  `docs/research/tinpproj-design.md` is updated in EP-1's M8 to match.


## Decision Log

- Decision: Decompose into two ExecPlans (EP-1 TInpProj, EP-2 SBV) with
  sharpening folded into each as a single design milestone.
  Rationale: The v2 design space is small (each item is a named
  retirement of a single named v1 escape hatch), so MasterPlan 1's
  separate-sharpening pattern would add coordination overhead without
  proportional design value. Two plans are the right grain because the
  changes touch distinct subsystems with distinct failure modes.
  Date: 2026-05-01

- Decision: EP-2 has a soft dependency on EP-1, not a hard one.
  Rationale: EP-2 has a documented fallback (separate symbolic-Term
  variant). Marking the dependency as hard would force EP-2 to wait for
  EP-1 to complete; soft means EP-2's design milestone makes the
  build-on-structural-Term-vs-separate-variant call explicitly. Default
  (when EP-1 is done) is to build on EP-1's structural Term.
  Date: 2026-05-01

- Decision: `OFn`, `PMatchC`, and the `unsafeCombine` static check are
  out of scope for this MasterPlan.
  Rationale: EP-4's retrospective named only TInpField/OPack-inverse and
  SBV BoolAlg as v2 priorities. Adding more retirements would balloon
  the work. They become separate items in a future MasterPlan once v2
  lands.
  Date: 2026-05-01

- Decision: Each ExecPlan produces a focused design note in
  `docs/research/` as part of its M1 milestone, rather than as a
  separate sharpening plan.
  Rationale: The v2 design space is constrained enough that a 200-300
  line note is sufficient. Separating impl from design adds a re-read
  round-trip that the design milestone-inside-impl pattern avoids.
  Date: 2026-05-01

- Decision: User Registration is the smoke test for both EPs.
  Rationale: It is the canonical worked example from EP-4 and from
  synthesis §4. The same five-event canonical log that demonstrated v1
  end-to-end demonstrates v2 end-to-end (with the structural surface)
  and provides the symbolic-`isSingleValued` test fixture (a known-good
  single-valued transducer). No additional smoke-test scaffolding is
  needed.
  Date: 2026-05-01


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at
completion. Compare the result against the original vision.

**EP-1 complete (2026-05-01).** EP-1 retired the v1 `TInpField`
constructor and the `OPack` hand-written inverse field. After EP-1
the `Keiki.Core` `Term` constructor set is `TLit`, `TReg`,
`TInpCtorField`, `TApp1`, `TApp2`; the `OutTerm` constructor set is
`OPack` (now carrying an `InCtor ci ifs` first argument so empty-
payload input constructors recover trivially) plus the v1 `OFn`
escape hatch. `solveOutput` is purely structural — no per-edge
hand-written inverse code anywhere. The `Keiki.Examples.UserRegistration`
(V5) and `Keiki.Examples.UserRegistrationV0` aggregates were
migrated end-to-end. `cabal test` reports 32 examples, 0 failures,
including:

- `reconstitute userReg canonicalLog == Just (Deleted,
  expectedSnapshot)` — the v1 verdict's "synthesis holds" gate is
  honored mechanically.
- `reconstitute userRegV0 canonicalLogV0 == Nothing` — the V0
  hidden-input bug surfaces structurally.
- `checkHiddenInputs userRegV0` produces a field-precise warning
  (`OPack walk for InCtor "ConfirmAccount" leaves field
  {"confirmCode"} unrecovered`).

EP-1 took 8 commits across M0-M7 plus an M7 progress fix. The largest
deviation from the M1 design note was the OPack-carries-InCtor
redesign discovered during M6 (see Surprises & Discoveries).

**EP-2 not yet started.** The MasterPlan-level acceptance criterion
("all four test categories pass, the User Registration aggregate
compiles with no per-edge `OPack` inverse, and `cabal build` succeeds
with no warnings about unreachable v1 escape hatches") is partially
met by EP-1: three of the four categories are green; the fourth
(`isSingleValued userReg == True` proved symbolically) is EP-2's
deliverable.
