---
id: 5
slug: acceptor-projections-and-genview-th-splice-for-b-presentation
title: "Acceptor projections and genView TH splice for B-presentation"
kind: master-plan
created_at: 2026-05-02T12:33:40Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
---

# Acceptor projections and genView TH splice for B-presentation

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

The keiki library has two named projections that the design notes
describe but the code base does not yet expose as first-class
artifacts:

1. **The input and output acceptors of a `SymTransducer`.** The
   foundations chapter
   `docs/foundations/04-projections-and-deriving-event-sourcing.md`
   centres on the insight that an FST has two acceptor projections:
   π₁ (drop the events; the remaining transition function is the
   command-language acceptor) and π₂ (drop the commands by inverting
   ω; the remaining transition function is `evolve`, i.e. the
   event-language acceptor). In `src/Keiki/Core.hs` these
   projections are *implicit* — π₁ is reachable by calling `delta`
   directly and π₂ is reachable by calling `applyEvent` directly —
   but no `Acceptor` data type exists, no `inputAcceptor` /
   `outputAcceptor` functions are exported, and the relationship the
   foundations chapter spells out is not visible in the API
   surface.

2. **The B-presentation per-vertex `View v` GADT.** The synthesis
   note
   (`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`,
   §3 "Where indexed state (B) fits") proposes a typed projection
   `viewFor :: SVertex v -> RegFile rs -> View v` so that each
   control vertex exposes only the registers meaningful in that
   state. The synthesis flagged a `genView` TH helper as "a
   nice-to-have, not a v1 requirement." Today no aggregate in
   `src/Keiki/Examples/` has a B-view, no `SVertex` machinery
   exists, and the user who wants the typed projection has to
   hand-write the GADT and the projection by hand.

This MasterPlan ships both. After completion the repository
contains:

- A new module `src/Keiki/Acceptor.hs` exporting an `Acceptor a s`
  data type, `inputAcceptor` and `outputAcceptor` projections from
  `SymTransducer`, plus thin helpers `runAcceptor` and `accepts`
  that fold over input sequences. The `Acceptor` is the formalism
  layer's name for "a `SymTransducer` viewed as an acceptor over
  one alphabet."

- A new TH splice in `src/Keiki/Generics/TH.hs` named
  `deriveView`. Given a vertex enum, a register-file slot-list
  type, and a per-vertex spec listing which slots are live in each
  vertex, it generates: (a) a per-aggregate `S<Vertex>` singletons
  GADT, (b) a per-aggregate `View` GADT with one constructor per
  vertex carrying the live slots as typed fields, (c) the
  `viewFor :: S<Vertex> v -> RegFile rs -> View v` projection.

- Two new design notes:
  `docs/research/acceptor-projections-design.md` (the formal
  semantics and the deliberate scope cap) and
  `docs/research/genview-th-splice-design.md` (the splice's
  user-facing API, spec format, validation rules, and worked
  expansion).

- Worked examples on `Keiki.Examples.UserRegistration`:
  - the input/output acceptors are exercised by tests in
    `test/Keiki/AcceptorSpec.hs`
  - a `UserView` GADT and `userView` projection are added to
    `Keiki.Examples.UserRegistration` (TH-derived); exercised by
    tests in `test/Keiki/Examples/UserRegistrationViewSpec.hs`.

- Updates to `docs/foundations/04-...md` and
  `docs/research/keiki-generics-design.md` retiring the relevant
  "future improvement" entries with a pointer to MP-5.

The user-visible win:

- "How do I get the command acceptor for `userReg`?" → `inputAcceptor
  userReg`.
- "How do I get a typed view of the `Confirmed` state's live
  registers?" → `userView SConfirmed regs` returns
  `ConfirmedV { cfEmail = ..., cfConfirmedAt = ... }`.

Both surfaces are pure projections — neither changes the
formalism. The transducer remains the source of truth.

In scope:

- `Acceptor a s` as a minimal data type. Just enough to encode
  "drop one alphabet" — a step function plus initial state plus
  final-state predicate.
- `inputAcceptor` / `outputAcceptor` projections from
  `SymTransducer`. State carrier is `(s, RegFile rs)` because edge
  guards depend on the register file.
- `runAcceptor` and `accepts` helpers for folding over input
  sequences.
- `deriveView` TH splice in `Keiki.Generics.TH`.
- Per-aggregate generated `S<Vertex>` singleton GADT alongside
  the `View` GADT (no shared singletons library).
- Worked example on `UserRegistration` for both surfaces.
- Test coverage proving the round-trip property
  `runAcceptor (outputAcceptor t) log == fmap fst (reconstitute t
  log)` and the per-vertex view `userView SConfirmed regs == ...`
  for hand-constructed register files.

Out of scope:

- Acceptor composition (intersection of acceptor languages,
  `compose` over Acceptors, language-equivalence checks). The
  Acceptor is a one-direction projection only. A future EP can
  add composition if needed.
- Read-model / query-side projections. Those are runtime concerns
  living outside the pure core (per `effects-boundary.md`).
- Lifting `viewFor` into the transducer's evolution loop. The
  synthesis note explicitly says "the transducer doesn't know
  about it"; the projection stays opt-in.
- A shared `Keiki.View` module exposing a generic `Singleton`
  class. Each aggregate gets its own freshly-generated singleton
  GADT to avoid kind-generic plumbing.
- A `View v = RegFile rs` default for aggregates that don't opt
  in. EP-B's splice is opt-in by invocation; aggregates that
  don't invoke it simply don't get a `View`.
- Updating MP-3's `Keiki.Decider` façade to project via Acceptors.
  Decider stays as it is.
- Profunctor hierarchy on Acceptors.


## Decomposition Strategy

This MasterPlan starts with **two child ExecPlans**, both already
sized in this document. There is no design-milestone-first stage
because both work streams have well-understood targets — the
Acceptor shape comes straight from foundations doc 04, and the
B-view shape comes straight from synthesis doc §3.

- **EP-12 (Acceptor projections).** Pure formalism addition. One
  new module (`Keiki.Acceptor`), ~100-150 lines. Five milestones:
  baseline, design note, module, tests, foundations doc update,
  commit.

- **EP-13 (genView TH splice + B-presentation).** Larger.
  Extends an existing module (`Keiki.Generics.TH`), generates a
  per-aggregate singleton GADT and `View` GADT, wires a worked
  example into `UserRegistration`. Six milestones.

The two are independent. Their public surfaces share no types;
their tests are in separate spec modules; their design notes are
separate files. EP-12 and EP-13 can run in either order (or in
parallel, if a contributor picks one and another contributor
picks the other).

**Why two EPs and not one.** A single ExecPlan would have eleven
milestones once both work streams are folded together — past
PLANS.md's "two to four milestones" rule of thumb. Splitting also
preserves independent rollback: if EP-13's splice design turns
out to need revision, EP-12's Acceptor module is unaffected.

**Why two EPs and not three.** A three-EP split (separating
SVertex singletons foundation from the TH splice) was considered.
Rejected because the splice generates the singletons GADT
itself; there's no shared singletons abstraction worth lifting
into its own EP. The dependency between "generate the GADT" and
"use the GADT" is internal to one EP.

**Alternatives considered:**

- *One EP covering both work streams.* Rejected for the milestone
  count reason above.
- *Design-milestone-first (à la MP-4).* Rejected because the two
  surfaces are well-defined in the existing research notes; no
  open design questions warrant a separate milestone.
- *Add `Acceptor` to `Keiki.Core` rather than a new module.*
  Considered briefly; rejected because `Keiki.Core` is the single-
  transducer formalism and Acceptor is a derived view. Same
  rationale that put `Keiki.Composition` in its own module
  (MP-4 / EP-11 Decision Log).
- *Bundle the genView splice into MP-3 (Keiki.Generics DX
  follow-ups).* Rejected because MP-3 is closed; reopening it for
  a new EP would require revising it. A fresh MasterPlan is the
  cleaner shape.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Acceptor projections (input/output) for SymTransducer | docs/plans/12-acceptor-projections-input-output-for-symtransducer.md | None | None | Complete |
| 2 | genView TH splice and B-presentation View v GADT | docs/plans/13-genview-th-splice-and-b-presentation-view-v-gadt.md | None | EP-1 (Examples.UserRegistration coordination) | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix
(EP-1 = the first row above, the Acceptor projections plan;
EP-2 = the second row, the genView splice plan).


## Dependency Graph

```
                 ┌──────────────────────┐
                 │     EP-1 (Acc.)      │
                 │  Acceptor module +   │
                 │  worked example      │
                 └──────────────────────┘

                 ┌──────────────────────┐
                 │     EP-2 (genView)   │
                 │  TH splice + UserView│
                 │  on UserRegistration │
                 └──────────────────────┘

                 (no hard deps between them;
                  soft coord only at IP-2 below)
```

Both EPs have no hard dependencies. Either can start first. They
share no source-code symbols.

Soft coordination only: IP-2 below describes the one place
where edits could collide.


## Integration Points

### IP-1: `keiki.cabal` `library:exposed-modules`

**Plans involved:** EP-1, EP-2.

**Shared artifact:** the `library:exposed-modules` block of
`keiki.cabal`.

**Owner:** each EP adds its own line. EP-1 adds `Keiki.Acceptor`.
EP-2 adds nothing new to `library:exposed-modules` (the splice
extends an existing module, `Keiki.Generics.TH`); it does add a
test module under `keiki-test:other-modules`.

**Coordination rule:** plain merge. The cabal additions are
independent lines.


### IP-2: `src/Keiki/Examples/UserRegistration.hs`

**Plans involved:** EP-2 (primary). EP-1 may reference the module
in tests but does not edit it.

**Shared artifact:** the example aggregate module.

**Owner:** EP-2. EP-2 adds: the `deriveView` TH invocation, the
generated `UserView` and `SUserVertex` types appearing in the
module's exports list (extending the existing export block at
lines 30-69), and a brief haddock note explaining the B-view
addition.

**Coordination rule:** if EP-1 lands first, EP-2 rebases over its
changes (which should be additive — EP-1 only reads the module).
If EP-2 lands first, EP-1's tests can use the new `UserView`
exports, but EP-1's acceptance does not require them.


### IP-3: `docs/foundations/04-projections-and-deriving-event-sourcing.md`

**Plans involved:** EP-1 (primary). EP-2 does not touch it.

**Shared artifact:** the foundations chapter on projections.

**Owner:** EP-1. EP-1 adds a brief section at the bottom of the
chapter (or extends the "Vocabulary recap" section) pointing at
`Keiki.Acceptor` as the module that materializes the
`inputAcceptor` / `outputAcceptor` discussed in the chapter.

**Coordination rule:** EP-2 does not edit foundations docs. The
B-presentation belongs in `docs/research/`, not foundations.


### IP-4: `docs/research/keiki-generics-design.md`

**Plans involved:** EP-2 (primary). EP-1 does not touch it.

**Shared artifact:** the keiki-generics design note's "Future
improvements" list.

**Owner:** EP-2. EP-2 retires the entry that flags `genView` as
a future improvement (or marks it Implemented with a pointer to
MP-5 / EP-13, mirroring the way EP-11 retired item F).

**Coordination rule:** plain merge.


## Progress

This section aggregates milestone-level progress across all child
plans for an at-a-glance view.

- [x] EP-1: Verify prerequisites — `Keiki.Core` builds, all tests pass; record GHC version (M0) (2026-05-02; GHC 9.12.3, 95 examples)
- [x] EP-1: Acceptor design note (M1) (2026-05-02)
- [x] EP-1: `Keiki.Acceptor` module with `Acceptor`, `inputAcceptor`, `outputAcceptor`, `runAcceptor`, `accepts` (M2) (2026-05-02)
- [x] EP-1: `test/Keiki/AcceptorSpec.hs` exercising input/output acceptors on `userReg` and `emailDelivery`; round-trip property test (M3) (2026-05-02; 6 new tests, 101 total examples, 0 failures)
- [x] EP-1: Foundations doc 04 pointer paragraph; commit (M4/M5) (2026-05-02; commit pending)
- [ ] EP-2: Verify prerequisites — TH machinery from EP-8 still works; record GHC version (M0)
- [ ] EP-2: genView TH splice design note (M1)
- [ ] EP-2: `deriveView` splice in `Keiki.Generics.TH` (M2)
- [ ] EP-2: Wire splice into `Keiki.Examples.UserRegistration`; export `UserView` and `SUserVertex` (M3)
- [ ] EP-2: `test/Keiki/Examples/UserRegistrationViewSpec.hs` (M4)
- [ ] EP-2: Update `keiki-generics-design.md`; commit (M5/M6)


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments,
or unexpected interactions between child plans. Provide concise
evidence.

(None yet.)


## Decision Log

- Decision: Split into two child ExecPlans (EP-12 Acceptor
  projections, EP-13 genView TH splice). Not one combined EP, not
  three (separating singletons from the splice).
  Rationale: a combined EP would land at ~11 milestones (past
  PLANS.md's two-to-four rule of thumb). A three-EP split is over-
  granular because the singletons GADT and the `View` GADT are
  generated by the same TH pass — no shared singletons abstraction
  warrants its own EP.
  Date: 2026-05-02

- Decision: EP-12 and EP-13 have no hard dependency. They can be
  implemented in either order or in parallel.
  Rationale: their public surfaces share no types. EP-12 ships a
  data type (`Acceptor`) and two functions; EP-13 ships a TH
  splice that generates per-aggregate types. Tests live in
  separate spec modules.
  Date: 2026-05-02

- Decision: `Acceptor a s` is a minimal data type (step function,
  initial state, final-state predicate). No composition, no
  language-equivalence APIs, no profunctor hierarchy.
  Rationale: scope is "name what's already implicit in `delta` and
  `applyEvent`," not "build out an automata-theory toolkit." A
  future EP can add composition over Acceptors if a real workflow
  demands it.
  Date: 2026-05-02

- Decision: `deriveView` generates a per-aggregate singletons
  GADT (e.g. `SUserVertex`) alongside the `View` GADT. No shared
  `Keiki.View` module exposes a kind-generic `Singleton` class.
  Rationale: a shared class would force kind-polymorphic
  machinery for every aggregate. Per-aggregate generation keeps
  each splice invocation self-contained and matches the worked
  example shape from synthesis §3.
  Date: 2026-05-02

- Decision: `deriveView` lives in the existing
  `Keiki.Generics.TH` module, not a new `Keiki.Generics.TH.View`
  module.
  Rationale: consistency with the EP-8 derivation surface
  (`deriveAggregateCtors`/`deriveWireCtors`). Users invoke all
  keiki TH from one import.
  Date: 2026-05-02

- Decision: `deriveView`'s spec format names slots by string
  (e.g. `["email", "confirmedAt"]`) rather than by `Index` value
  or by promoted symbol. The splice validates that each named
  slot exists in the supplied register-file type.
  Rationale: TH splice ergonomics; users already write slot
  labels as strings via OverloadedLabels at term sites. The
  validation step gives precise error messages on typos.
  Date: 2026-05-02

- Decision: The worked example for both EPs is
  `Keiki.Examples.UserRegistration`. EP-12's tests may also
  exercise `Keiki.Examples.EmailDelivery` to demonstrate the
  output acceptor on a wire-event-on-every-transition pipeline
  (avoiding the ε-edge issue the MP-4 retrospective noted for
  `userReg`'s `RequiresConfirmation → Deleted` edge).
  Rationale: `UserRegistration` is the canonical example; tests
  should cover the canonical surface. `EmailDelivery` covers the
  ε-edge-free shape.
  Date: 2026-05-02


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones
or at completion. Compare the result against the original vision.

(To be filled during and after implementation.)
