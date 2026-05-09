---
id: 4
slug: composition-combinators-on-symtransducer
title: "Composition combinators on SymTransducer"
kind: master-plan
created_at: 2026-05-01T22:08:48Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
---

# Composition combinators on SymTransducer

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

The keiki library currently ships **two** composition operators on
`SymTransducer`:

- `union` (alternative-style; either of two transducers may step).
- A proposed `compose` (sequential; the output of one is the input
  of the next), mentioned in
  `docs/research/keiki-generics-design.md` but not implemented.

The crem comparison note
(`docs/research/architecture-comparison-keiki-vs-crem.md`)
documents that crem ships **six** composition primitives:
`Sequential`, `Parallel`, `Alternative`, `Feedback`, `Kleisli`, plus
the full Profunctor hierarchy. The `keiki-generics-design.md` note
catalogues this gap as **item F — crem-style composition combinators
on `SymTransducer`** in its "Future improvements" list and explicitly
flags it as:

- "Significant: each combinator needs a careful semantics worked out
  against the formal projection."
- "Independent of `Keiki.Generics`' DX scope" — so it sits outside
  MasterPlan 3.

This MasterPlan delivers a working set of composition combinators on
`SymTransducer` while preserving the keiki guarantees the v2 core
established (mechanical inversion via `solveOutput`, build-time
hidden-input checks, symbolic single-valuedness via
`isSingleValuedSym`). Each combinator must produce a composite
`SymTransducer` whose own `solveOutput`, `checkHiddenInputs`, and
`isSingleValuedSym` answers are correct — i.e. composition does not
introduce silent inversion gaps or symbolic-analysis blind spots.

After this MasterPlan is complete, the repository contains:

- A new module `src/Keiki/Composition.hs` (or extension of
  `Keiki/Core.hs`; M1 picks) exporting the chosen combinators.
- A new design note `docs/research/composition-combinators-design.md`
  capturing the formal semantics of each combinator against the
  symbolic-register-transducer projection (existing notes
  `synthesis-c-foundation-b-presentation-with-worked-examples.md`
  and `core-design-transducer-as-source-of-truth.md` are the
  starting point).
- A worked example demonstrating composition: a *process manager*
  spanning the User Registration aggregate and a hypothetical Email
  Delivery aggregate (or another small aggregate the design
  milestone picks). The process manager is the canonical use case
  for `compose` + `feedback` per the orchestration note
  `docs/research/orchestration-sagas-choreography-and-feedback-loops-as-transducers.md`.
- A test suite asserting that the worked example's composition
  preserves single-valuedness symbolically and reconstitutes
  correctly under `omega` + `applyEvent`.
- Updates to `docs/research/keiki-generics-design.md` retiring
  item F with a pointer to this MasterPlan.

This MasterPlan begins with a **single design milestone** (EP-11)
that determines which combinators are in scope, what the formal
semantics are, and how the per-combinator implementation work
fans out. **Likely outcome: EP-11 produces a design note and then
a per-combinator decomposition that revises this MasterPlan to add
EP-12, EP-13, ... — one per combinator that survives the design
milestone.** EP-11's design note explicitly produces that
recommendation; the MasterPlan revision protocol cascades the
update.

In scope:

- A formal design note for composition combinators against the
  keiki symbolic-register projection.
- An implementation of *at least* the two combinators flagged by
  the design note as "minimum viable" (likely `compose` and
  `feedback`, but the design milestone confirms).
- A worked process-manager example.
- A test that composition preserves the keiki guarantees
  (mechanical inversion, hidden-input checks,
  symbolic single-valuedness).
- Updates to the keiki-generics-design Future Improvements entry.

Out of scope:

- The full crem profunctor hierarchy. crem inherits Profunctor +
  Strong + Choice + Costrong + Cochoice + Closed + Mealy machinery
  via its dependency on `profunctors` and `machines`; replicating
  the hierarchy would balloon scope. The design milestone picks a
  minimum viable subset and documents what is left for future
  work.
- Effects in compositions. crem parameterizes its machines over a
  `Monad m`; keiki's pure formalism says compositions remain pure
  (effects live at the runtime boundary per
  `docs/research/effects-boundary.md`). The design milestone
  reaffirms or revisits this.
- Integration with a hypothetical `Keiki.Runtime`. Process-manager
  scheduling, retry, persistence — all runtime concerns; deferred.
- crem-style topology safety (item G in the design note). Out of
  scope here, deferred to a future v3 MasterPlan.


## Decomposition Strategy

This MasterPlan starts with **one child ExecPlan**: EP-11, the
*design milestone*. EP-11's terminal output is a design note that
either:

(a) Decomposes the work into per-combinator child ExecPlans
    (EP-12 `compose`, EP-13 `feedback`, EP-14 `alternative`, ...),
    in which case this MasterPlan is updated via the standard
    revision protocol to add the new rows to the Exec-Plan
    Registry; or

(b) Concludes that the minimum viable subset is small enough to
    fit in EP-11 itself (e.g. `compose` only), in which case
    EP-11 also implements the chosen combinators and a worked
    example, and the MasterPlan completes after EP-11.

The two-stage shape — design milestone first, fan-out
afterwards — is the right grain for an open-ended design space
where the right number of work units is not yet knowable. Trying
to enumerate per-combinator EPs upfront would force premature
decisions about which combinators are in scope.

**Why a MasterPlan and not a single ExecPlan:**

Item F's design note already says "significant" and "each
combinator needs a careful semantics worked out." A single
ExecPlan can hold a design milestone *or* a single-combinator
implementation, but not "design + multiple impls" without
violating PLANS.md's "two to four milestones" rule of thumb. The
MasterPlan structure lets EP-11's design milestone fan out into
sibling EPs without forcing them to share an ExecPlan envelope.

**Alternatives considered:**

- *Single ExecPlan covering design + a fixed combinator set.*
  Rejected: presupposes the combinator set, which is the design
  milestone's output.
- *Bundle item F into MasterPlan 3 (Keiki.Generics DX
  follow-ups).* Rejected: the design note explicitly says F is
  "independent of `Keiki.Generics`' DX scope." Bundling would
  conflate themes.
- *Skip the design milestone; implement `compose` directly using
  intuition from `union`.* Rejected: the keiki formal projection
  is non-trivial. Composition that breaks `solveOutput` (loses a
  field on the wire) or `isSingleValuedSym` (silently
  over-approximates) would defeat keiki's value proposition. The
  design milestone is load-bearing.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Composition combinators on SymTransducer | docs/plans/11-composition-combinators-on-symtransducer.md | None | EP-7 (external), MP-3 children | Complete |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix
(e.g., EP-1, EP-3). "EP-7 (external)" refers to
`docs/plans/7-upgrade-keiki-to-ghc-9-12.md`. "MP-3 children" refers
to `docs/masterplans/3-keiki-generics-dx-follow-ups.md`'s child
plans (EP-8, EP-9, EP-10).

This registry will grow when EP-11's design milestone fans out
into per-combinator EPs (see the Vision & Scope and Decomposition
Strategy sections above). EP-11's revision step appends rows for
each combinator that survives the design milestone.


## Dependency Graph

```
        ┌─────────────────────────────────────┐
        │ EP-7  (external) — GHC 9.12 upgrade │
        │ MP-3  (external) — Generics DX      │
        └──────────────────┬──────────────────┘
                           │ (soft)
                           ▼
                    ┌─────────────┐
                    │   EP-11     │
                    │  Design +   │
                    │ initial impl│
                    └──────┬──────┘
                           │
                           │ (after design milestone)
                           ▼
              ┌────────────┴─────────────┐
              │  Per-combinator EPs      │
              │  (added by MP revision)  │
              └──────────────────────────┘
```

**EP-11 has no hard dependencies.** Its design milestone reads the
existing `Keiki.Core` and `Keiki.Symbolic` modules and produces a
note. Implementation milestones touch `Keiki.Core` (or a new
`Keiki.Composition` module).

**Soft external deps:**

- *EP-7 (GHC 9.12 upgrade).* Recommended-soft-dep for the same
  reasons as MP-3's children.
- *MP-3 children.* The worked example may benefit from EP-8's TH
  splice (less boilerplate when defining the second aggregate
  needed for the process-manager demo) and EP-10's `Keiki.Decider`
  façade (composition-as-Decider is a common idiom from the naive
  decider world). Neither is required.


## Integration Points

### IP-1: `Keiki.Core` (or new `Keiki.Composition` module)

**Plans involved:** EP-11 (and any per-combinator EPs that follow
the design milestone).

**Owner:** EP-11's design milestone decides whether combinators
extend `Keiki.Core` or live in a new `Keiki.Composition` module.
The default — when no constraints apply — is "new module" so
`Keiki.Core` stays focused on the single-transducer formalism.

**Coordination rule:** subsequent per-combinator EPs adopt
whatever shape EP-11's design milestone chose.

### IP-2: `docs/research/composition-combinators-design.md`

**Plans involved:** EP-11 (creates the note); per-combinator EPs
(amend the note as their semantics are refined).

**Owner:** EP-11 owns the file's structure. Subsequent EPs add
sections for their combinator's semantics if not already covered.

### IP-3: Worked example aggregate(s)

**Plans involved:** EP-11 (defines the second aggregate the
process-manager demo composes against); subsequent EPs reuse it.

**Owner:** EP-11.

**Coordination rule:** the second aggregate lives at
`src/Keiki/Examples/<Name>.hs` and reuses `Keiki.Generics`. If
EP-8 (TH splice from MP-3) has landed, the second aggregate uses
the splice form; otherwise it uses `mkInCtorVia`/`mkWireCtorVia`.


## Progress

This section aggregates milestone-level progress across all child
plans for an at-a-glance view.

- [x] EP-11: Verify prerequisites — Keiki.Core builds, all tests pass; record GHC version (M0) *(2026-05-02; baseline 89 examples, GHC 9.12.3)*
- [x] EP-11: Survey crem and orchestration notes; pick minimum viable combinator set; write design note (M1) *(2026-05-02; chose `compose` only; ~480-line design note)*
- [x] EP-11: Decide module shape (`Keiki.Core` extension vs. new `Keiki.Composition`); add chosen combinators (M2) *(2026-05-02; new module Keiki.Composition)*
- [x] EP-11: Add second worked-example aggregate for process-manager demo (M3) *(2026-05-02; Keiki.Examples.EmailDelivery)*
- [x] EP-11: Implement composition; verify mechanical inversion / hidden-input check / symbolic single-valuedness all hold on the composite (M4) *(2026-05-02; 6 new tests pass, 95 examples 0 failures)*
- [x] EP-11: Update keiki-generics-design.md item F entry; capture verdict; revise this MasterPlan if fan-out is needed (M5/M6) *(2026-05-02; no fan-out, item F retired)*


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments,
or unexpected interactions between child plans. Provide concise
evidence.

- *(EP-11 M0, 2026-05-02)* **Neither `union` nor `compose` existed
  in the codebase at EP-11 start.** `keiki-generics-design.md`'s
  claim that the library "ships `union`" was aspirational; both
  operators were net-new for EP-11. The design milestone treated
  them as such; `union` was not included in the minimum viable
  set (it has its own non-local single-valuedness invariant
  warranting a separate design pass).

- *(EP-11 M0, 2026-05-02)* **`cabal test all` requires `z3` in
  PATH; the devShell does not include it.** Workaround:
  `nix-shell -p z3 --run "cabal test all"`. Adding `pkgs.z3` to
  `flake.nix`'s devShell is a small follow-up; out of scope for
  EP-11.

- *(EP-11 M1, 2026-05-02)* **Reconstitute on a composite requires
  every composite transition to produce a wire event.** The
  initial worked-example design (User Registration ⨾ Process
  Manager ⨾ Email Delivery) had ε-edges in the process manager's
  state machine for non-target events; on the composite this
  meant `reconstitute` couldn't move past states with only
  ε-outgoing edges. The fix was to use a simpler 2-aggregate
  pipeline (AlertSource ⨾ EmailDelivery) where every transition
  is wire-producing. The orchestration-note process-manager
  pattern remains documented as a future application; EP-11
  validates the composition mechanism on the simpler shape.


## Decision Log

- Decision: Item F (crem-style composition combinators) gets its
  own MasterPlan, separate from MP-3 (Keiki.Generics DX
  follow-ups).
  Rationale: The keiki-generics-design.md note explicitly states F
  is "independent of `Keiki.Generics`' DX scope" and "significant
  (each combinator needs a careful semantics worked out)." Bundling
  with MP-3's DX work would conflate themes; sizing a single EP for
  it would force premature combinator-set decisions.
  Date: 2026-05-01

- Decision: Start with one child EP (the design milestone). Allow
  the design milestone's output to fan out into per-combinator EPs
  via the standard MasterPlan revision protocol.
  Rationale: The right number of per-combinator EPs is unknowable
  before the design milestone. Forcing an upfront enumeration would
  either over-scope (build all six crem combinators when keiki
  needs two) or under-scope (commit to two when three turn out to
  be needed for the worked example).
  Date: 2026-05-01

- Decision: Soft external deps on EP-7 (GHC 9.12) and on MP-3's
  children. None are required to start EP-11's design milestone.
  Rationale: The design milestone reads existing modules and
  produces a note; it doesn't compile new code. Implementation
  milestones can land regardless of the external deps' status.
  Date: 2026-05-01


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones
or at completion. Compare the result against the original vision.

### What MP-4 delivered (2026-05-02)

- A **new `Keiki.Composition` module** exporting `compose`, the
  `Composite s1 s2` newtype with hand-rolled `Bounded`/`Enum`
  instances, the `WeakenR` typeclass, the
  `weakenL`/`weakenLTerm`/`weakenLPred`/`weakenLUpdate` lifters,
  and the substitution algorithm
  (`substTerm`/`substPred`/`substUpdate`/`substOut`/
  `substOutFields`). Source: `src/Keiki/Composition.hs` (~290
  lines including haddock).

- A **new design note**
  `docs/research/composition-combinators-design.md` (~480 lines)
  capturing the formal semantics: the substitution algorithm in
  full, the case analysis for single-valuedness preservation,
  the documented limitations (t1 outputs must be `OPack`; t2
  mid-side guards must be structural), and the future-improvement
  list (`feedback`, `alternative`, `parallel`, `Kleisli`,
  profunctor hierarchy).

- A **second worked-example aggregate**
  `Keiki.Examples.EmailDelivery` — a 2-vertex aggregate with one
  command (`SendEmail`) and one event (`EmailSent`), built using
  EP-8's TH splices. Source: `src/Keiki/Examples/EmailDelivery.hs`.

- A **composite test suite** `test/Keiki/CompositionSpec.hs` —
  six tests asserting `step`, `omega`, `reconstitute`,
  `checkHiddenInputs`, and `isSingleValuedSym (withSymPred ...)`
  on a composite of an inline `AlertSource` fixture and the
  `EmailDelivery` aggregate. The pipeline shape (every transition
  produces a wire event) makes the round-trip well-defined.

- Updates to `docs/research/keiki-generics-design.md` retiring
  item F with a reference to MP-4 / EP-11.

Test count: **89 → 95 examples, 0 failures**.

### How the result compares to the original vision

The MasterPlan vision was to "deliver a working set of composition
combinators on `SymTransducer` while preserving the keiki
guarantees (mechanical inversion, build-time hidden-input checks,
symbolic single-valuedness)." The chosen subset is a single
combinator (`compose`); the design milestone ruled out the other
five crem combinators with documented rationale and deferred them
to follow-up EPs. The three load-bearing guarantees are preserved
end-to-end on the composite, verified by symbolic z3 single-
valuedness, structural hidden-input check, and full-log
`reconstitute` round-trip.

### Lessons learned

- **The pure-formalism reconstitute path constrains what
  composite shapes are usable.** A composite whose intermediate
  ε-edges block `reconstitute` from advancing past a state isn't
  amenable to a round-trip test as currently shaped. EP-11
  worked around this by using a wire-event-on-every-transition
  pipeline; a future EP could relax the constraint by extending
  `reconstitute` to advance through ε-edges between events. This
  is non-trivial — runtime semantics of "advance until a wire
  event lands or no edge fires" is a separate design.

- **Substitution preserves single-valuedness mechanically.** The
  proof sketch in the design note's "Guarantee 3" section is a
  case analysis that the implementation respects. The composite
  is single-valued whenever the underlying transducers are
  individually single-valued — the symbolic z3 check on the
  pipeline (passing in <1s) confirms this for the test fixture.

- **Structural alignment between t1's `WireCtor` and t2's
  `InCtor` is load-bearing.** The substitution relies on
  `icName ic2 == wcName wc1` to discharge `PInCtor` atoms and to
  align `OutFields`-positional reads with `InCtor` slot-list
  positions. The `Generic` derivations in `Keiki.Generics` already
  enforce shape consistency (slot list of an `InCtor` matches
  the field tuple of a `WireCtor` of the same payload type), so
  in practice `compose userReg ...` over the canonical worked
  examples works without alignment headaches.

### Gaps and follow-ups (deferred)

- **`feedback`** — fixed-point combinator for aggregate ↔ policy
  loops. Requires either bounded iteration or a termination
  proof. Defer to a follow-up EP.
- **`alternative`** — disjoint-input parallel composition with
  its own non-local single-valuedness invariant.
- **`parallel`**, **`Kleisli`**, **profunctor hierarchy** — see
  the design note's "Future improvements (deferred)" section.
- **Graceful fallback for non-structural transducers.**
  Currently `compose` errors when t1 has `OFn` outputs or t2 has
  `PMatchC` over `mid`. A future revision could emit composite
  edges with appropriate escape hatches and let
  `checkHiddenInputs` flag them.
- **z3 in the devShell.** `flake.nix` should include `pkgs.z3`
  so `cabal test all` runs without `nix-shell -p z3`. Small
  follow-up.
