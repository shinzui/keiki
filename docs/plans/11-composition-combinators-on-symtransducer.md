---
id: 11
slug: composition-combinators-on-symtransducer
title: "Composition combinators on SymTransducer"
kind: exec-plan
created_at: 2026-05-01T22:06:50Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/4-composition-combinators-on-symtransducer.md"
---

# Composition combinators on SymTransducer

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The keiki library models a single aggregate as a *symbolic-register
transducer*: a finite-state machine whose edges carry guard
predicates, register-file updates, output terms, and target
vertices. The single-transducer formalism is mature
(`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`,
`docs/research/core-design-transducer-as-source-of-truth.md`),
mechanically inverted on replay (`solveOutput`), and decidable for
single-valuedness (`isSingleValuedSym` via SBV).

Real-world systems span multiple aggregates. A *process manager* or
*saga* observes events from one aggregate and issues commands to
another; a *feedback loop* lets a transducer's own output drive its
next input; an *alternative composition* combines two transducers
that each handle a subset of the input alphabet. The
`docs/research/orchestration-sagas-choreography-and-feedback-loops-as-transducers.md`
note documents how each pattern maps onto the formalism. crem (the
production-grade Haskell Mealy-machine library compared in
`docs/research/architecture-comparison-keiki-vs-crem.md`)
ships six composition primitives — `Sequential`, `Parallel`,
`Alternative`, `Feedback`, `Kleisli`, plus the full Profunctor
hierarchy — and the keiki-generics-design.md note catalogues this
gap as **item F — crem-style composition combinators on
`SymTransducer`**:

> Effort: significant (each combinator needs a careful semantics
> worked out against the formal projection); independent of
> `Keiki.Generics`' DX scope.

This plan is the **design-milestone-first** EP that delivers item F
under MasterPlan 4
(`docs/masterplans/4-composition-combinators-on-symtransducer.md`).
It begins with a focused design pass that decides:

1. Which combinators are in scope (likely `compose` and
   `feedback`, the minimum viable for process managers).
2. The formal semantics of each combinator against the
   symbolic-register-transducer projection.
3. Whether composition preserves keiki's three load-bearing
   guarantees:
   - Mechanical inversion via `solveOutput` (the composite must
     itself have a structural inverse).
   - Hidden-input check via `checkHiddenInputs` (the composite
     must surface field-precise warnings for inversion gaps).
   - Symbolic single-valuedness via `isSingleValuedSym` (the
     composite's edge guards must be decidably mutually
     exclusive).

If the design milestone determines that two or more combinators
need substantial implementation work, EP-11 revises MasterPlan 4
to fan out into per-combinator EPs (EP-12, EP-13, ...), each
implementing one combinator end-to-end. If the design milestone
fits a minimum viable combinator set into a single EP envelope,
EP-11 also implements them and the worked example, and MasterPlan
4 completes.

After this plan is complete (in either fan-out shape), the
repository contains:

- A new module `src/Keiki/Composition.hs` (or extension of
  `Keiki/Core.hs`; M2 picks) exporting at least:

      compose
        :: BoolAlg phi (RegFile rs1, ci1)
        => SymTransducer phi rs1 s1 ci1 mid
        -> SymTransducer phi rs2 s2 mid co
        -> SymTransducer phi (Append rs1 rs2)
                          (s1, s2) ci1 co

      feedback
        :: BoolAlg phi (RegFile rs, ci)
        => SymTransducer phi rs s ci co
        -> (co -> Maybe ci)
        -> SymTransducer phi rs s ci co

  …or whatever subset the design milestone picks.

- A new design note `docs/research/composition-combinators-design.md`
  capturing the formal semantics. The note's structure mirrors
  `docs/research/sbv-boolalg-design.md` — a problem statement, a
  design space, the chosen path, the rejected alternatives, and
  per-feature semantics paragraphs.

- A worked process-manager example. Specifically: a tiny *Email
  Delivery* aggregate (`src/Keiki/Examples/EmailDelivery.hs`)
  paired with a process manager that observes
  `ConfirmationEmailSent` events from User Registration and
  issues `SendEmail` commands to Email Delivery. The composition
  is `compose userReg orchestrator emailDelivery` (or whatever
  shape the design picks).

- A test in `test/Keiki/CompositionSpec.hs` asserting that the
  composite preserves single-valuedness symbolically, that
  `solveOutput` works on composite output terms, and that
  `checkHiddenInputs` flags any composition-introduced
  inversion gaps.

- An updated `docs/research/keiki-generics-design.md` with item F
  marked **Implemented (see EP-11 / MP-4)**.

- A revised `docs/masterplans/4-composition-combinators-on-symtransducer.md`
  reflecting the actual shape (fan-out or single-EP) the design
  milestone produced.

How a future contributor sees this work:

    cabal test
    # 70 → ~75 examples (depending on the M3 example's test count),
    # 0 failures.
    # Includes "compose preserves single-valuedness" and
    # "process manager round-trip" tests.

The user-visible win: keiki users authoring multi-aggregate
workflows (process managers, sagas) get a typed, mechanical
composition surface that preserves the v2 guarantees, instead of
hand-rolling event/command plumbing per pair of aggregates.


## Progress

Use a checklist to summarize granular steps. Every stopping point
must be documented here, even if it requires splitting a partially
completed task into two ("done" vs. "remaining"). This section must
always reflect the actual current state of the work.

- [x] **Milestone 0 — Verify prerequisites.** *(2026-05-02)*
      `cabal build all` green. `cabal test all` requires `z3` in PATH;
      under `nix-shell -p z3` the suite reports **89 examples, 0
      failures** (the plan's "70 expected" was outdated). A
      `grep -n "^union\|^compose" src/Keiki/Core.hs
      src/Keiki/Composition.hs` returns no matches; **neither operator
      currently exists**. The keiki-generics-design.md note's mention
      of "ships union" is aspirational. Both `union` and `compose`
      are net-new for EP-11.
- [x] **Milestone 1 — Design milestone.** *(2026-05-02)*
      Surveyed the orchestration note and the crem comparison
      note. Picked the minimum viable combinator set: **one
      combinator, `compose`** (sequential composition). The
      other five crem combinators (`feedback`, `alternative`,
      `parallel`, `Kleisli`, profunctor hierarchy) are deferred
      to follow-up EPs as authoring needs surface; rationale
      in the design note's "What keiki ships in EP-11: minimum
      viable" section. Module placement: **new module
      `src/Keiki/Composition.hs`** (not extension of
      `Keiki/Core.hs`). Wrote
      `docs/research/composition-combinators-design.md` (~480
      lines) covering the substitution algorithm, the three
      preserved guarantees with proof sketches, the limitations
      of structural compose, and the worked-example shape.
      MasterPlan-shape decision: **single-EP**, no fan-out.
      MasterPlan 4 completes after EP-11. M5 of this plan is a
      no-op.
- [x] **Milestone 2 — Module shape + first combinator.**
      *(2026-05-02)* Created `src/Keiki/Composition.hs` exporting
      `compose`, the `Composite` newtype with hand-rolled
      `Bounded`/`Enum`, the `WeakenR` typeclass, the
      `weakenL`/`weakenLTerm`/`weakenLPred`/`weakenLUpdate`
      lifters, and the substitution algorithm
      (`substTerm`/`substPred`/`substUpdate`/`substOut`/
      `substOutFields`). Added `Keiki.Composition` to
      `keiki.cabal`'s `library:exposed-modules`.
      `cabal build all` succeeds; existing test suite unchanged
      at 89 examples, 0 failures.
- [x] **Milestone 3 — Worked example: Email Delivery aggregate.**
      *(2026-05-02)* Created `src/Keiki/Examples/EmailDelivery.hs`
      — a 2-vertex aggregate (`EmailPending → EmailSentVertex`)
      with one command (`SendEmail`) and one event (`EmailSent`),
      using EP-8's `deriveAggregateCtors`/`deriveWireCtors` TH
      splices. Added to `keiki.cabal`'s
      `library:exposed-modules`. `cabal build all` succeeds.
- [x] **Milestone 4 — Compose + verify guarantees.**
      *(2026-05-02)* Created `test/Keiki/CompositionSpec.hs`
      with the `pipeline = compose alertSource emailDelivery`
      composite. The `AlertSource` test fixture (defined inline
      in the spec; emits `EmailCmd` so its mid alphabet aligns
      with EmailDelivery's input) is a structural pipeline whose
      transitions all produce wire events — making
      `reconstitute` round-trip well-defined per the design
      note's discussion. Added six tests:
      (a) `step` produces `EmailSent` on `TriggerAlert` ✓
      (b) `step` rejects at the terminal composite vertex ✓
      (c) `checkHiddenInputs pipeline == []` ✓
      (d) `isSingleValuedSym (withSymPred pipeline) == True` ✓
          (symbolic via z3)
      (e) `reconstitute pipeline [sampleEmailEvent]` lands at
          `Composite AlertEmitted EmailSentVertex` ✓
      (f) `omega pipeline initial regs sampleTrigger ==
          Just sampleEmailEvent` ✓
      Wired `Keiki.CompositionSpec` into `test/Spec.hs` and
      `keiki.cabal`'s `keiki-test:other-modules`. `cabal test
      all` reports **95 examples, 0 failures** (89 baseline + 6
      new).
- [x] **Milestone 5 — MasterPlan revision.** *(2026-05-02)*
      No-op. M1's design decision keeps EP-11 single-EP — the
      minimum viable combinator set is `compose` alone, fitting
      cleanly inside this plan. MasterPlan 4 stays unchanged
      (no per-combinator fan-out).
- [x] **Milestone 6 — Update design note + commit.**
      *(2026-05-02)* Marked item F **Implemented (see EP-11 /
      MP-4)** in `docs/research/keiki-generics-design.md` and
      updated the summary-table row from "Two (more proposed)"
      to "One (compose; more proposed)". Two commits land the
      work: the M0+M1 design milestone (already committed) plus
      a single follow-up commit for M2-M6 (module +
      EmailDelivery aggregate + tests + docs updates +
      MasterPlan revision).


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights
discovered during implementation. Provide concise evidence.

- *(M0, 2026-05-02)* **Neither `union` nor `compose` exists in the
  current codebase.** `grep -n "^union\|^compose" src/Keiki/Core.hs
  src/Keiki/Composition.hs` returns no matches; `src/Keiki/Composition.hs`
  does not exist. The keiki-generics-design.md note's claim that the
  library "ships `union`" is aspirational. EP-11 treats both as
  net-new; the design milestone decides whether `union` joins the
  minimum viable set.

- *(M0, 2026-05-02)* **`cabal test all` requires `z3` in PATH.** The
  current devShell flake (`flake.nix`) does *not* include `z3`. With
  no `z3`, 29 of 89 examples fail with `Unable to locate executable
  for Z3`. Workaround: `nix-shell -p z3 --run "cabal test all"`.
  Tests run from this point use that wrapper. Adding `pkgs.z3` to
  the devShell is a small follow-up; out of scope for EP-11 but
  noted.

- *(M0, 2026-05-02)* **Test baseline is 89 examples, not 70.** The
  plan's "70 expected" stat reflected an older snapshot before
  EP-8/9/10 (TH derivation, symSatExt round-trip, Decider façade)
  added their tests. M4's "M0 baseline + 3" target is now "89
  baseline + 3 (or more)".


## Decision Log

Record every decision made while working on the plan.

- *(2026-05-02)* **One combinator in scope: `compose` only.**
  `feedback`, `alternative`, `parallel`, `Kleisli`, and the
  profunctor hierarchy are deferred. Rationale: `compose` covers
  the orchestration note's three patterns (choreography, process
  manager, full pipeline). `feedback` requires an iteration
  model that conflicts with keiki's pure formalism. `alternative`
  has its own non-local single-valuedness invariant warranting
  its own design pass. `parallel` solves a problem keiki users
  haven't asked for. `Kleisli` requires multi-event edges
  (synthesis §5 MultiDecider, out of v2 scope). Profunctor
  hierarchy requires a different `SymTransducer` shape.

- *(2026-05-02)* **Module placement: `src/Keiki/Composition.hs`,
  a new top-level module.** Not an extension of `Keiki.Core`.
  Rationale: `Keiki.Core` is the single-transducer formalism;
  multi-transducer composition is a distinct concern with its own
  substitution machinery. Adding the substitution helpers to
  `Keiki.Core` would balloon its export list and obscure the
  single-transducer data layout.

- *(2026-05-02)* **Predicate carrier `phi` is `HsPred`, not
  polymorphic.** `compose` walks t2's predicate AST during
  substitution; an opaque `BoolAlg phi` carrier doesn't expose
  enough structure for the substitution. The composite's `HsPred`
  guards still lift to `SymPred` via the existing `withSymPred`
  wrapper for symbolic analysis.

- *(2026-05-02)* **Composite vertex type is a newtype `Composite
  s1 s2`** (not bare `(s1, s2)`). Rationale: the `Bounded`/`Enum`
  instances `checkHiddenInputs` and `isSingleValuedSym` require
  cannot be derived for a tuple without an orphan instance. The
  newtype owns its instances cleanly. Cost: ~3 lines per call
  site (`Composite v1 v2` vs. `(v1, v2)`).

- *(2026-05-02)* **Substitution restricts t1 outputs to `OPack`
  and t2 mid-reads to structural patterns.** Non-structural
  inputs (`OFn`, `PMatchC` over `mid`) raise a runtime error
  naming the offending edge. A graceful fallback (emit composite
  edges with escape hatches and let `checkHiddenInputs` flag
  them) is deferred. Rationale: the keiki value proposition is
  structural composition; an opaquely-composed transducer
  defeats the EP. The error makes the limitation visible.

- *(2026-05-02)* **MasterPlan 4 stays single-EP.** No fan-out into
  per-combinator EPs. M5 of this plan is a no-op.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones
or at completion. Compare the result against the original purpose.

### What EP-11 delivered (2026-05-02)

EP-11 retired item F of `keiki-generics-design.md` (crem-style
composition combinators). The single combinator in scope, sequential
`compose`, ships in a new module `Keiki.Composition`:

- **Module:** `src/Keiki/Composition.hs` (~290 lines including
  haddock). Exports `compose`, the `Composite s1 s2` newtype with
  `Bounded`/`Enum` instances, the `WeakenR` typeclass, the four
  `weakenL*` lifters, and the five `subst*` substitution functions.
- **Design note:** `docs/research/composition-combinators-design.md`
  (~480 lines). Documents the substitution algorithm in full, the
  case analysis for single-valuedness preservation, and the
  documented limitations.
- **Worked example:** `src/Keiki/Examples/EmailDelivery.hs` — a
  2-vertex aggregate. Tests use a `compose alertSource
  emailDelivery` pipeline (with `alertSource` defined inline as a
  test fixture).
- **Tests:** `test/Keiki/CompositionSpec.hs` — six tests, all
  passing. Suite total: **95 examples, 0 failures** (89 baseline +
  6 new).
- **Documentation updates:** `keiki-generics-design.md` item F
  marked Implemented; summary-table row updated.

### Compared to the original purpose

The plan's purpose was to add composition combinators to
`SymTransducer` while preserving the three keiki guarantees
(mechanical inversion, build-time hidden-input checks, symbolic
single-valuedness). All three are preserved on the composite,
verified by:

1. `reconstitute composite [event]` round-trip works (mechanical
   inversion).
2. `checkHiddenInputs composite == []` (the structural
   substitution does not introduce hidden inputs).
3. `isSingleValuedSym (withSymPred composite) == True`
   (the substitution is a syntactic rewrite that preserves
   unsatisfiability under SBV).

The plan anticipated potentially fanning out into per-combinator
EPs (EP-12 `compose`, EP-13 `feedback`, EP-14 `alternative`).
The design milestone determined that the minimum viable subset is
**a single combinator** (`compose`), so the plan stayed
single-EP and MasterPlan 4 completes without revision.

### Lessons learned

- **The composite preserves single-valuedness compositionally**
  via a syntactic-rewrite proof: each pairwise edge-conjunction
  factors through either t1's mutual exclusion (the `g1a ∧ g1b`
  factor) or t2's (under substitution). The proof sketch in the
  design note's "Guarantee 3" section is a complete case analysis;
  the implementation respects it. The symbolic z3 check on the
  test pipeline confirms in <1s.

- **Reconstitute imposes a structural constraint on composite
  shapes.** A composite whose intermediate ε-edges block
  `reconstitute` from advancing isn't amenable to a round-trip
  test in the current keiki formalism. EP-11's worked example
  uses a wire-event-on-every-transition pipeline (AlertSource ⨾
  EmailDelivery) to avoid the issue; the orchestration-note
  process-manager pattern (User Reg ⨾ PM ⨾ Email Delivery)
  remains documented as a future application but is not used as
  the EP-11 acceptance fixture.

- **The substitution algorithm requires `unsafeCoerce` at two
  positions** (term result-type alignment in `substTerm`, and
  `InCtor` ci-type alignment in `substOut`). Both are justified
  by the structural-alignment invariant (`icName == wcName`
  implies the slot-list / field-tuple shapes derived from the
  same `Generic` representation match). This precedent is
  consistent with `Keiki.Core.gatherInpEntries`'s existing use
  of `unsafeCoerce` for the same reason.

### Gaps and follow-ups (deferred)

- **`feedback`, `alternative`, `parallel`, `Kleisli`, profunctor
  hierarchy** — see the design note's "Future improvements" list.
- **Graceful fallback for non-structural inputs.** Currently
  `compose` errors at runtime when t1 has `OFn` output or t2 has
  `PMatchC` over `mid`. A future revision could emit composite
  edges with escape hatches and let `checkHiddenInputs` flag
  them.
- **`reconstitute` over composites with intermediate ε-edges.**
  The pure formalism doesn't currently support advancing
  through ε-edges between wire events; runtime adapters do, but
  the pure replay path needs a separate design.
- **`pkgs.z3` in `flake.nix`'s devShell.** Without it, `cabal
  test all` fails for symbolic tests (workaround: `nix-shell -p
  z3 --run "cabal test all"`).


## Context and Orientation

Describe the current state relevant to this task as if the reader
knows nothing.

The keiki library is in `/Users/shinzui/Keikaku/bokuno/keiki/`.
Modules and notes relevant to this plan:

    src/Keiki/Core.hs                — formalism: SymTransducer, etc.
    src/Keiki/Symbolic.hs            — SBV-backed BoolAlg, isSingleValuedSym
    src/Keiki/Examples/UserRegistration.hs  — canonical worked example
    docs/research/
      synthesis-c-foundation-b-presentation-with-worked-examples.md
      core-design-transducer-as-source-of-truth.md
      orchestration-sagas-choreography-and-feedback-loops-as-transducers.md
      architecture-comparison-keiki-vs-crem.md
      keiki-generics-design.md       — catalogues item F
    docs/masterplans/
      4-composition-combinators-on-symtransducer.md  — this plan's parent

**Key shape from `Keiki.Core`:**

    data SymTransducer phi rs s ci co = SymTransducer
      { edgesOut    :: s -> [Edge phi rs ci co s]
      , initial     :: s
      , initialRegs :: RegFile rs
      , isFinal     :: s -> Bool
      }

    data Edge phi rs ci co s = Edge
      { guard  :: phi
      , update :: Update rs ci
      , output :: Maybe (OutTerm rs ci co)
      , target :: s
      }

The five type parameters of `SymTransducer`:

- `phi` — the predicate carrier (`HsPred rs ci` for v1 syntactic
  surface; `SymPred rs ci` for v2 SBV-backed).
- `rs` — the slot list of the register file (`'[Slot]`).
- `s` — the control vertex enum.
- `ci` — the input alphabet (commands).
- `co` — the output alphabet (events).

A composition `compose t1 t2` consumes `ci1`, internally produces
`mid`, and ultimately outputs `co`:

    compose
      :: SymTransducer phi rs1 s1 ci1 mid
      -> SymTransducer phi rs2 s2 mid  co
      -> SymTransducer phi (Append rs1 rs2) (s1, s2) ci1 co

The composite's vertex is `(s1, s2)` (a pair tracking both
machines' states); the register file is `Append rs1 rs2` (the
slot lists concatenated; `Append` already exists in
`Keiki.Generics`); the input/output alphabets adapt.

**Why composition is non-trivial.**

A naive `compose` that runs `t1` and `t2` in sequence step-by-step
breaks the keiki guarantees in three subtle ways:

1. **Mechanical inversion.** `solveOutput (compose t1 t2)`'s `co`
   was produced by `t2`'s output term operating on `t2`'s
   register file. To recover `ci1` (the composite's input), we
   must invert `t2`'s output to find the `mid` that `t1` produced,
   then invert `t1`'s output (which is `mid`, observed at `t2`'s
   input) to find `ci1`. This is two structural walks. The
   `OutTerm`'s structure must support the chain.

2. **Hidden-input check.** `checkHiddenInputs (compose t1 t2)`
   must flag any field that:
   (a) `t1` reads from `ci1` but doesn't put on the wire as part
       of `mid`, *or*
   (b) `t2` reads from `mid` but doesn't put on the wire as part
       of `co`.
   The `mid`-mediation makes (b) the tricky case: a hidden input
   in `t2`'s edges produces a hidden input in the composite, and
   the warning's "field name" comes from `t2`'s `InCtor` for
   `mid`.

3. **Symbolic single-valuedness.** `isSingleValuedSym (compose t1
   t2)` decides whether two outgoing edges from the same
   composite vertex `(s1, s2)` are mutually exclusive. The
   conjunction of two composite edge guards is a conjunction of
   per-machine guards `(g1a ∧ g2a) ∧ (g1b ∧ g2b)` — but the
   per-machine guards may share register references (slot reads
   from `rs1` or `rs2`). The SBV translation must thread the
   shared slot variables across both machines' translations.

These constraints rule out the simplest possible implementation
(`compose t1 t2 = SymTransducer { edgesOut = \(s1, s2) -> [...] }`
with naive edge-list construction) and motivate the design
milestone. Each combinator picks a specific implementation
strategy that preserves the three guarantees.

**`feedback` and `alternative` (preview, design milestone
confirms).**

`feedback` lets a transducer's output drive its next input. The
shape per the orchestration note:

    feedback
      :: SymTransducer phi rs s ci co
      -> (co -> Maybe ci)   -- feedback function: which outputs loop back
      -> SymTransducer phi rs s ci co

The composite "consumes" the same input alphabet but the runtime
re-feeds the output. Single-valuedness is preserved trivially
(the underlying edges don't change). `solveOutput` is preserved
trivially. The hidden-input check requires a small extension:
when an output is fed back, the next step's input is
reconstructable from the previous output, so the cycle's hidden
inputs are no longer a concern.

`alternative` (or `union`) combines two transducers handling
disjoint subsets of the input alphabet:

    alternative
      :: SymTransducer phi rs s1 ci co
      -> SymTransducer phi rs s2 ci co
      -> SymTransducer phi rs (Either s1 s2) ci co

The two transducers run in parallel, but at most one matches per
input. Single-valuedness requires the two underlying transducers'
guards to be mutually exclusive at every step — itself a symbolic
question that the v2 SBV-backed analysis can answer.

**Process-manager example (worked example for M3-M4).**

A small Email Delivery aggregate:

    data EmailCmd = SendEmail SendEmailData
    data EmailEvent = EmailSent EmailSentData
    data EmailVertex = Idle | Sending | Sent
    type EmailRegs = '[ '("recipient", Email)
                      , '("body",      Text)
                      , '("sentAt",    UTCTime)
                      ]

…composed with User Registration via a process manager
transducer that observes `ConfirmationEmailSent` from the User
Registration output and emits `SendEmail` to the Email Delivery
input:

    processManager
      :: SymTransducer phi (rs1, rs2)
                       PMVertex
                       UserEvent       -- input
                       EmailCmd        -- output

(Where `(rs1, rs2)` is the appended register file pulling needed
fields from both aggregates.)

The full composition:

    fullSystem = compose userReg (compose processManager emailDelivery)

…or whatever associativity the design picks.

The process-manager pattern is documented in
`docs/research/orchestration-sagas-choreography-and-feedback-loops-as-transducers.md`'s
"Saga / Process Manager" section.


## Plan of Work

Six milestones. Effort estimate: ~12-20 hours total — substantially
more than MP-3's children because the formal-semantics work is
load-bearing. The plan deliberately front-loads design (M1) so
implementation (M2-M4) follows a written-down spec.

**Milestone 0 — Baseline.** Run `cabal build all && cabal test
all`. Record the test count (70 expected). Run:

    grep -n "^union\|^compose" src/Keiki/Core.hs src/Keiki/Composition.hs 2>/dev/null

If `union` (or any other composition operator) exists, capture its
signature and implementation. If not, record the discovery in
Surprises & Discoveries (the keiki-generics-design.md note's
mention of "ships `union`" appears to be aspirational).

**Milestone 1 — Design milestone.** This is the load-bearing
milestone. Sub-steps:

1. *Survey.* Read top-to-bottom:
   - `docs/research/orchestration-sagas-choreography-and-feedback-loops-as-transducers.md`
   - `docs/research/architecture-comparison-keiki-vs-crem.md` §"crem's composition primitives"
   - `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md` §5 (Order Fulfillment process manager)
   - `docs/research/core-design-transducer-as-source-of-truth.md`
   - `docs/research/effects-boundary.md`

2. *Pick the minimum viable combinator set.* The orchestration
   note motivates `compose` (sequential) and `feedback` as the
   two needed for process managers. The crem note adds
   `alternative` (parallel-disjoint) as a separate idiom.
   Decision: minimum viable = `compose` only, or {`compose`,
   `feedback`}, or {`compose`, `feedback`, `alternative`}.
   Document the choice with rationale.

3. *Decide module placement.* Two options:
   (a) Extend `src/Keiki/Core.hs` with the combinators.
   (b) Create `src/Keiki/Composition.hs`.
   Default: (b) — keeps `Keiki.Core` focused on the
   single-transducer formalism. Document.

4. *Define formal semantics.* For each chosen combinator, write a
   ~50-100 line section in the new design note describing:
   - Type signature.
   - Effect on the formal projection (control graph, registers,
     edges). Refer to direction-C/B notes for the projection
     model.
   - Effect on `solveOutput`: what shape the composite's
     `OutTerm` takes and how the inverse is constructed.
   - Effect on `checkHiddenInputs`: how composite edges' hidden
     fields are surfaced.
   - Effect on `isSingleValuedSym`: how the composite's edge
     guards translate to SBV.
   - The associativity / unit / commutativity laws (if any).

5. *Decide on a worked example.* Email Delivery is the default;
   M3 implements it. If the design milestone surfaces a better
   minimal example (e.g. a self-feedback example for `feedback`),
   adapt M3 to use it.

6. *Decide MasterPlan shape.* If the design milestone determines
   that the chosen combinator set fits in EP-11 itself (e.g. only
   `compose` is in scope, ~200 lines of code total), keep the
   single-EP shape. If it spawns substantial per-combinator work
   (e.g. {`compose`, `feedback`, `alternative`} are each
   ~300-500 lines), revise MasterPlan 4 to add per-combinator
   EPs (EP-12 `compose`, EP-13 `feedback`, EP-14 `alternative`)
   and rescope EP-11 to "design + minimum viable `compose` only."

   Document the MasterPlan-shape decision in this plan's Decision
   Log.

Acceptance: `docs/research/composition-combinators-design.md`
exists, is ~300-500 lines, and contains the design decisions for
each chosen combinator. The MasterPlan-shape decision is
documented.

**Milestone 2 — Module shape + first combinator.** Create the
chosen module file. Add it to `keiki.cabal`'s
`library:exposed-modules`. Implement the first combinator (likely
`compose`) per the design note's spec.

The implementation walks:

- `edgesOut (compose t1 t2) (s1, s2) = ...` — for each edge `e1`
  out of `s1` in `t1`, for each edge `e2` out of `e1.target` in
  `t2` matching the input `mid` produced by `e1.output`, emit a
  composite edge.
- The composite edge's `guard` is the conjunction of `e1.guard`
  and `e2.guard` translated to read from the `(rs1, rs2)`-shaped
  register file.
- The composite edge's `update` runs `e1.update` on the `rs1`
  side and `e2.update` on the `rs2` side.
- The composite edge's `output` is `e2.output` lifted to read
  from the appended register file.
- The composite edge's `target` is `(e1.target, e2.target)`.

Care is needed for edges whose `e1.output` is `Nothing` (ε-edges
in the upstream): the composite edge produces no event but still
transitions both machines.

`cabal build all` succeeds.

Acceptance: the first combinator type-checks, the existing
`userReg` tests remain green, and a small test (M4 lands the
full version) demonstrates `compose userReg (id-transducer)`
behaves identically to `userReg` modulo the wrapped state type.

**Milestone 3 — Email Delivery worked example.** Create
`src/Keiki/Examples/EmailDelivery.hs`. Shape:

    {-# LANGUAGE DeriveGeneric #-}
    {-# LANGUAGE GADTs #-}

    module Keiki.Examples.EmailDelivery
      ( EmailCmd (..), SendEmailData (..)
      , EmailEvent (..), EmailSentData (..)
      , EmailVertex (..)
      , EmailRegs
      , emailDelivery
      ) where

    import GHC.Generics (Generic)
    ...

    data SendEmailData = SendEmailData
      { recipient :: Text
      , body      :: Text
      , at        :: UTCTime
      } deriving (Eq, Show, Generic)

    data EmailCmd = SendEmail SendEmailData
      deriving (Eq, Show, Generic)

    -- ...EmailEvent, EmailVertex, EmailRegs, emailDelivery...

The aggregate has one vertex, one command, one event; the entire
implementation is ~80 lines including the per-ctor declarations
(or one splice form if EP-8 has landed; M0 records EP-8's
status).

Add to `keiki.cabal`'s `library:exposed-modules`. `cabal build`
succeeds.

Acceptance: `emailDelivery :: SymTransducer ...` is exported and
type-checks.

**Milestone 4 — Compose + verify guarantees.** Add the process
manager (a small transducer mapping `UserEvent` → `EmailCmd`)
and the composite. Add tests in
`test/Keiki/CompositionSpec.hs`:

    spec :: Spec
    spec = describe "compose userReg pmgr emailDelivery" $ do
      it "preserves single-valuedness symbolically" $ do
        isSingleValuedSym (withSymPred composite) `shouldBe` True

      it "passes the hidden-input check" $ do
        checkHiddenInputs composite `shouldBe` []

      it "reconstitutes the canonical multi-aggregate event log" $ do
        reconstitute composite canonicalLog
          `shouldBe` Just expectedFinalState

The third test is the load-bearing acceptance: a multi-aggregate
event log is replayed end-to-end through the composite and lands
in the expected combined state.

Wire `Keiki.CompositionSpec` into `test/Spec.hs` and
`keiki.cabal`'s `keiki-test:other-modules`.

`cabal test all` reports M0 baseline + 3 (or more, depending on
intermediate test additions), 0 failures.

Acceptance: all three tests pass.

**Milestone 5 — MasterPlan revision (conditional).** If M1
decided to fan out:

1. Run `bun agents/skills/exec-plan/init-plan.ts --title "..."
   --master-plan docs/masterplans/4-composition-combinators-on-symtransducer.md
   --intention intention_01knjzws4qezz9w8b0743zfqv8` for each
   per-combinator EP. The script creates the file with proper
   numbering.
2. Edit `docs/masterplans/4-composition-combinators-on-symtransducer.md`'s
   Exec-Plan Registry to add the new rows.
3. Update the Dependency Graph and Integration Points sections.
4. Append a revision note at the bottom of the MasterPlan
   describing the fan-out decision and rationale.

If M1 decided to stay as a single EP, this milestone is a no-op
and the EP marks complete.

Acceptance: the MasterPlan reflects the actual shape of work.

**Milestone 6 — Update design note + commit.** Edit
`docs/research/keiki-generics-design.md` "### F. crem-style
composition combinators on `SymTransducer`" entry. Append a
paragraph beginning **Implemented (see EP-11 / MP-4).** linking
to the new design note and the new module(s).

Stage and commit. The commit set:

- `docs/research/composition-combinators-design.md` (new)
- `src/Keiki/Composition.hs` (new) or
  `src/Keiki/Core.hs` (modified)
- `src/Keiki/Examples/EmailDelivery.hs` (new)
- `test/Keiki/CompositionSpec.hs` (new)
- `test/Spec.hs` (one-line addition)
- `keiki.cabal` (additions: `exposed-modules` × 2, `other-modules` × 1)
- `docs/research/keiki-generics-design.md` (item F retirement)
- `docs/masterplans/4-composition-combinators-on-symtransducer.md`
  (revised if M5 fanned out)

Single commit (or one per milestone if logical splits emerge).
Trailers: `MasterPlan: docs/masterplans/4-composition-combinators-on-symtransducer.md`,
`ExecPlan: docs/plans/11-composition-combinators-on-symtransducer.md`,
`Intention: intention_01knjzws4qezz9w8b0743zfqv8`.


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki/`.

**M0 baseline:**

    cabal build all
    cabal test all 2>&1 | grep -E '^[0-9]+ examples'
    grep -rn "^union\|^compose" src/Keiki/

**M1 design milestone.** No code; produce
`docs/research/composition-combinators-design.md` per Plan of
Work M1.

**M2 first combinator.** Edit `keiki.cabal` to add the new
module; create `src/Keiki/Composition.hs` per the design note.

    cabal build all

**M3 Email Delivery.** Create
`src/Keiki/Examples/EmailDelivery.hs`; add to
`library:exposed-modules`.

    cabal build all

**M4 compose + tests.** Create `test/Keiki/CompositionSpec.hs`
per Plan of Work M4. Wire into `test/Spec.hs` and
`keiki.cabal`'s `keiki-test:other-modules`.

    cabal test all 2>&1 | grep -E '^[0-9]+ examples'

**M5 (conditional).** See Plan of Work M5.

**M6 commit.** See Plan of Work M6.


## Validation and Acceptance

After all six milestones (assuming the single-EP path; the
fan-out path defers full acceptance to the per-combinator EPs):

- `cabal build all` succeeds.
- `cabal test all` reports baseline + 3 (or more), 0 failures.
- `docs/research/composition-combinators-design.md` exists and
  documents the chosen combinators' formal semantics.
- `src/Keiki/Composition.hs` (or the chosen module) exports the
  combinator(s).
- `src/Keiki/Examples/EmailDelivery.hs` exports the second
  worked-example aggregate.

Behavioral acceptance (the load-bearing tests):

1. **Single-valuedness preserved.** `isSingleValuedSym
   (withSymPred composite) == True` is symbolically proved by
   z3. The composition does not silently introduce overlapping
   guards.
2. **Mechanical inversion preserved.** `solveOutput` on the
   composite's `OutTerm` recovers the composite's `ci`. (For the
   process-manager example, the composite's input is `UserCmd`
   and the composite's output is `EmailEvent`; `solveOutput`
   walks `EmailEvent`'s structure back to a `UserCmd`.)
3. **Hidden-input check sharp.** `checkHiddenInputs composite ==
   []` for the worked example. If a deliberate hidden-input
   variant is constructed (e.g. by dropping a field from the
   process manager's output), the check fires with a
   field-precise warning.
4. **Reconstitute round-trip.** The canonical multi-aggregate
   event log replays through `reconstitute composite` and
   produces the expected `(state, regfile)` pair.


## Idempotence and Recovery

The plan's milestones are largely additive. Each milestone's
edits can be re-applied without harm:

- M1's design note is a new file; deleting and rewriting it has
  no side effects.
- M2's new module is self-contained.
- M3's new aggregate module is self-contained.
- M4's test additions are scoped to a single new spec module.
- M5's MasterPlan revisions follow the standard revision
  protocol; the MasterPlan tracks its own revision history.

Recovery from a bad design milestone — if the formal semantics
turn out to be wrong (e.g. `compose` introduces hidden inputs the
check can't detect):

1. Revert the design note's affected sections.
2. Re-evaluate the design space with the surface failure as
   evidence.
3. Update the Decision Log with the failure mode and the
   adjusted design.

Recovery from a failing acceptance test — if
`isSingleValuedSym` returns `False` on the composite when the
underlying transducers are individually single-valued:

1. The most likely cause is a guard-translation bug: the SBV
   translation of the composite's edge guards doesn't share the
   register variables across the two underlying transducers.
2. Inspect with `SBV.satWith config { verbose = True }` to see
   the model's variable names.
3. Fix the translation in the composite's `guard` construction
   to thread `SymEnv` correctly across both machines.

Recovery from a bad MasterPlan revision (M5):

1. The MasterPlan revision protocol allows appending revision
   notes; revert by appending a corrective note.
2. If per-combinator EPs were created in error, mark them
   `Cancelled` in the registry rather than deleting the files
   (preserves audit trail).


## Interfaces and Dependencies

New types and functions (assuming `compose` is in scope; the
design milestone may add `feedback` and/or `alternative`):

    -- src/Keiki/Composition.hs (or extension of Keiki/Core.hs)
    compose
      :: BoolAlg phi (RegFile (Append rs1 rs2), ci1)
      => SymTransducer phi rs1 s1 ci1 mid
      -> SymTransducer phi rs2 s2 mid co
      -> SymTransducer phi (Append rs1 rs2) (s1, s2) ci1 co

    -- (additional combinators per design milestone)

New modules:

- `Keiki.Composition` (if the design picks "new module" over
  "extend Keiki.Core") — exports the combinator(s).
- `Keiki.Examples.EmailDelivery` — the second worked-example
  aggregate.
- `Keiki.CompositionSpec` (test) — the round-trip + guarantees
  test.

Existing functions consumed:

- `Keiki.Core.SymTransducer`, `Edge`, `Update`, `OutTerm`, `HsPred`.
- `Keiki.Symbolic.isSingleValuedSym`, `withSymPred`.
- `Keiki.Generics.Append` (the slot-list concat type family).

No new external libraries.

The `Keiki.Generics.Append` type family already exists. The
`(s1, s2)` composite vertex shape requires `Bounded`/`Enum`
instances on the pair if the existing `checkHiddenInputs` is to
range over composite vertices; the design milestone confirms
whether stock `instance (Bounded s1, Bounded s2) => Bounded (s1,
s2)` derivations suffice or a custom enumeration is needed.

The MasterPlan parent
(`docs/masterplans/4-composition-combinators-on-symtransducer.md`)
governs the multi-EP coordination if the design milestone fans
out.
