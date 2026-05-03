---
id: 8
slug: composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli
title: "Composition combinators beyond sequential: parallel, alternative, feedback, kleisli"
kind: master-plan
created_at: 2026-05-02T23:43:59Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
---

# Composition combinators beyond sequential: parallel, alternative, feedback, kleisli

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

Today `Keiki.Composition` exports exactly one combinator: `compose`,
the categorical sequential composition delivered by MP-4 / EP-11.
`docs/research/composition-combinators-design.md`'s "Future
improvements (deferred)" section lists four crem-style combinators
that EP-11 deliberately punted with documented rationale:
`parallel`, `alternative`, `feedback`, and `Kleisli`. The
`docs/research/architecture-comparison-fst-aggregate-vs-crem.md`
note records these as the gap that keeps keiki's pure-core surface
behind crem's for orchestration patterns that don't reduce to a
linear chain of `compose`.

After this MasterPlan, `Keiki.Composition` (or a sibling module)
exports the in-scope subset chosen by the design milestone, each
combinator preserves keiki's three load-bearing analyses
(`solveOutput`, `checkHiddenInputs`, `isSingleValuedSym`) on the
composite, and at least one worked example demonstrates each
combinator on a realistic aggregate / process-manager shape.

The user-visible behaviours enabled:

- **`parallel t1 t2`** — run two independent transducers side by
  side on a tuple input, emitting a tuple output. Models product
  aggregates (e.g. distinct bounded contexts within one service)
  without forcing the author to glue them by hand.
- **`alternative t1 t2`** — disjoint-input dispatch; the composite
  consumes `Either ci1 ci2` and routes to whichever transducer
  matches. Models command routing across sibling aggregates that
  share a runtime channel.
- **`feedback t f`** — fixed-point combinator for the
  aggregate ↔ policy loop spelled out in
  `docs/research/orchestration-sagas-choreography-and-feedback-loops-as-transducers.md`.
  An aggregate's output drives a stateless policy `f` that emits
  follow-up commands which loop back into the aggregate.
- **`kleisli`** — sequential composition over multi-event edges,
  i.e. `compose` generalised to the case where `t1` produces a
  list of events per step. EP-20's state-refinement work exists
  precisely so multi-event commands stay inside one transducer;
  `kleisli` is its cross-transducer counterpart.

In scope:

- A design milestone (the first child EP) that re-evaluates each
  of the four combinators against the *current* keiki core
  (post-MP-1..MP-7), updates
  `docs/research/composition-combinators-design.md`'s "Future
  improvements" section into a full design record per combinator,
  and decomposes the rest of the MasterPlan into per-combinator
  EPs. The design milestone must explicitly settle:
    - the iteration model for `feedback` (bounded-iteration count,
      a termination witness, or a fixed-step variant);
    - the global-mutual-exclusion check `alternative` needs (Z3
      via `Keiki.Symbolic` is the obvious tool);
    - whether `Kleisli` waits on the multi-event edge form
      flagged by the synthesis note's §5 (in which case it stays
      deferred, with the deferral re-confirmed in this plan).
- Per-combinator implementation EPs for whichever combinators the
  design milestone admits.
- A worked example per shipped combinator, added under
  `src/Keiki/Examples/` with matching tests under
  `test/Keiki/Examples/`.
- Updates to `docs/research/composition-combinators-design.md`
  and `docs/research/keiki-generics-design.md` so the "Future
  improvements" entries that this MasterPlan retires are
  redirected to MP-8's outcomes section.

Out of scope:

- Anything that would require crem-style type-level topology
  (item G in the keiki-generics-design "Future improvements"
  note). The `Composite s1 s2` newtype keeps the cross-product
  vertex enumeration; we do not introduce an `AllowedTransition`
  GADT proof in this MasterPlan.
- Effectful composition. The pure formalism stays pure; effects
  remain a runtime concern per
  `docs/research/effects-boundary.md`.
- Profunctor / Category / Strong / Choice typeclass instances on
  the existential wrapper. Those are MP-9's concern; this
  MasterPlan ships standalone combinator functions.
- A full multi-event edge form (synthesis §5 MultiDecider). If
  `Kleisli` requires it, it stays deferred and the deferral is
  re-recorded here, not unlocked.


## Decomposition Strategy

This MasterPlan starts with **one child ExecPlan** — a design
milestone — and fans out to per-combinator implementation EPs
through the standard MasterPlan revision protocol, mirroring
MP-4's shape.

The four combinators have very different difficulty profiles:

- `parallel` is mechanical: the composite vertex is `Composite s1
  s2`, the register file is `Append rs1 rs2` (existing
  `WeakenR` / `weakenL` machinery applies), and edges form a
  cross-product on independent input/output halves. Closest in
  spirit to `compose`; smallest EP.
- `alternative` is mechanical *if* the global mutual-exclusion
  check is offloaded to `Keiki.Symbolic` (Z3); without it the
  composite can silently lose single-valuedness. Single EP, with
  a Z3 step in its acceptance criteria.
- `feedback` requires picking an iteration model. The futures
  note (§1) and the orchestration note both describe an
  iterate-until-quiescence loop; that is itself an effect (it can
  diverge), incompatible with the pure-core boundary. The design
  milestone must commit to one of three reductions:
  (a) bounded-step `feedback n t f` where `n :: Int` caps the
  inner loop, (b) single-step `feedback1 t f` that runs exactly
  one round of the policy, (c) decline `feedback` entirely and
  document the deferral. Each option implies a different EP.
- `Kleisli` per the synthesis §5 note needs a multi-event edge
  form; promoting it requires lifting the `output :: Maybe (OutTerm
  rs ci co)` field of `Edge` to `[OutTerm rs ci co]` (or a new
  multi-output combinator). EP-20 deliberately avoided this by
  staying within state-refinement; redoing that decision is
  out-of-scope here. Most likely outcome: the design milestone
  re-confirms the deferral with a pointer to a hypothetical v3
  initiative.

Decomposing per-combinator (rather than per "phase") lets each
combinator's EP own its own design subtleties (iteration model,
mutual-exclusion check, multi-event form) without dragging the
others along. It also matches the precedent set by MP-4, which
shipped a single `compose` EP and used the MasterPlan only for
coordination.

**Why a MasterPlan and not a single ExecPlan:** the design
milestone's output decides how many implementation EPs are
warranted. Forcing a fixed combinator set upfront would either
over-scope (commit to building all four when only two pass the
design pass) or under-scope (commit to two when the design
milestone clears three). The two-stage shape preserves option
value.

**Alternatives considered:**

- *Single ExecPlan with all four combinators.* Rejected: each
  combinator carries its own non-trivial design question
  (iteration model, mutual-exclusion check, multi-event form);
  bundling them would violate PLANS.md's "two to four
  milestones" guidance and force premature commitment to
  combinators that the design milestone may rule out.
- *Bundle into MP-9 (Profunctor / Category instances).* Rejected:
  MP-9's `Strong` and `Choice` instances are parameterised over
  the combinators MP-8 ships, so MP-9 has a soft dependency on
  MP-8. Bundling would create an internal cycle; keeping them
  separate lets MP-9 pick whichever instances correspond to the
  combinators that actually land.
- *Skip the design milestone; clone EP-11 four times.* Rejected:
  EP-11's documented limitations (t1 outputs must be `OPack`, t2
  mid-side guards must be structural, escape hatches refused)
  applied to a single combinator with one substitution shape.
  The new combinators have entirely different formal structures
  (especially `feedback`); copy-paste would obscure rather than
  surface those differences.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Composition combinators beyond sequential — design milestone | docs/plans/24-composition-combinators-beyond-sequential-design-milestone.md | None | EP-11 (external) | In Progress |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix
(e.g., EP-1, EP-3). "EP-11 (external)" refers to MP-4's child plan
`docs/plans/11-composition-combinators-on-symtransducer.md`,
which delivered the existing `compose` and the design note this
MasterPlan extends.

This registry will grow when EP-24's design milestone fans out
into per-combinator EPs. The fan-out step appends one row per
combinator the design milestone admits (likely `parallel`,
`alternative`, and one of `feedback`'s reductions; `Kleisli` is
expected to be re-deferred).

The first child EP path above (`docs/plans/24-...`) is the
expected path; the actual number is assigned by
`bun agents/skills/exec-plan/init-plan.ts` when EP-24 is
created, and this row updated to match.


## Dependency Graph

```
        ┌─────────────────────────────────────────┐
        │ EP-11 (external) — existing `compose`   │
        │ MP-4  (external) — composition design   │
        └──────────────────┬──────────────────────┘
                           │ (soft)
                           ▼
                    ┌─────────────┐
                    │   EP-24     │
                    │  Design     │
                    │  milestone  │
                    └──────┬──────┘
                           │
                           │ (after design milestone)
                           ▼
              ┌────────────┴─────────────┐
              │  Per-combinator EPs      │
              │  (added by MP revision)  │
              │                          │
              │  - parallel              │
              │  - alternative           │
              │  - feedback variant      │
              │  - (Kleisli, if not      │
              │     re-deferred)         │
              └──────────────────────────┘
```

**EP-24 has no hard dependencies.** Its design pass reads
`Keiki.Composition`, `Keiki.Core`, `Keiki.Symbolic`, and the
existing `composition-combinators-design.md` note; it produces an
updated note and the per-combinator EP fan-out.

**Soft external deps:**

- *EP-11 (the existing `compose` work).* Soft, not hard: EP-24's
  design milestone is a pure prose pass and doesn't touch code.
  Per-combinator implementation EPs reuse the `WeakenR` /
  `weakenL` / substitution machinery from EP-11, but each
  combinator's substitution shape is its own.

Within the per-combinator EPs (added after the fan-out), `parallel`
and `alternative` are independent of each other; either can land
first. `feedback` likely depends on whichever combinator is used
to express the inner step (probably `parallel` for the
aggregate ↔ policy pair), so it lands after.


## Integration Points

### IP-1: `src/Keiki/Composition.hs` (or sibling modules)

**Plans involved:** EP-24 (design milestone) and every
per-combinator EP added by the fan-out.

**Owner:** EP-24's design milestone decides whether the new
combinators extend `Keiki.Composition` (the file already exports
`compose`, `Composite`, the `WeakenR` class, the `weakenL*`
lifters, and the `subst*` family) or live in sibling modules per
combinator family. The default — when no constraint applies — is
to extend `Keiki.Composition`, since the substitution machinery
(`weakenL`, `WeakenR`) is shared across all combinators that
build a composite register file.

**Coordination rule:** subsequent per-combinator EPs adopt
whatever module shape EP-24 picks. If a per-combinator EP
discovers a need for a different shape (e.g. `feedback`'s
iteration helper wants to live in `Keiki.Composition.Feedback`),
it updates this section via the standard MasterPlan revision
protocol.

### IP-2: `docs/research/composition-combinators-design.md`

**Plans involved:** EP-24 (extends the existing "Future
improvements" section into per-combinator design records);
per-combinator EPs (refine their combinator's section as the
implementation reveals subtleties).

**Owner:** EP-24 owns the structural change (one section per
in-scope combinator). Subsequent EPs append a "What we shipped"
subsection to their combinator's section once they finish.

### IP-3: Composite vertex enumeration

**Plans involved:** every per-combinator EP.

**Owner:** the existing `Composite s1 s2` newtype in
`src/Keiki/Composition.hs` (see lines 56–87) is the agreed
representation for product vertices. `parallel` reuses it
verbatim. `alternative` needs a `Sum` newtype (likely
`data CompositeSum s1 s2 = InL s1 | InR s2`) with hand-rolled
`Bounded` / `Enum`. `feedback` reuses `Composite s1 s2`. EP-24
either confirms these choices or proposes alternatives; the
per-combinator EPs adopt whatever EP-24 picks.

**Coordination rule:** if any per-combinator EP needs a new
composite vertex shape, it must be added to `Keiki.Composition`'s
exports (or a sibling module) and reused by later EPs rather than
re-invented per combinator.

### IP-4: `Keiki.Symbolic`'s single-valuedness check

**Plans involved:** EP-24 and the `alternative` per-combinator
EP.

**Owner:** `Keiki.Symbolic.isSingleValuedSym` already analyses a
single transducer. `alternative` requires a *cross-transducer*
mutual-exclusion check at each shared composite vertex; EP-24
decides whether to extend `isSingleValuedSym` to a
two-transducer variant or to add a new
`isAlternativeSafeSym` helper. Either way, the alternative EP
inherits the chosen API.

### IP-5: Worked-example aggregates

**Plans involved:** every per-combinator EP.

**Owner:** EP-24 does *not* author the worked examples; each
per-combinator EP authors its own under `src/Keiki/Examples/`.
The existing `UserRegistration`, `OrderCart`, and `EmailDelivery`
examples (and the `AlertSource` test fixture in
`test/Keiki/CompositionSpec.hs`) are reused where shape allows.
Each per-combinator EP names the example it ships in its own
plan.


## Progress

Track milestone-level progress across all child plans. Each
entry names the child plan and the milestone. This section
provides an at-a-glance view of the entire initiative.

- [ ] EP-24: Re-confirm prerequisites — Keiki.Composition builds, all tests pass; record GHC version (M0)
- [ ] EP-24: Re-evaluate each of the four deferred combinators against the current core; pick the in-scope subset (M1)
- [ ] EP-24: Settle the iteration model for `feedback`, the mutual-exclusion check for `alternative`, and the multi-event question for `Kleisli` (M2)
- [ ] EP-24: Extend `composition-combinators-design.md`'s "Future improvements" section into per-combinator design records (M3)
- [ ] EP-24: Decompose into per-combinator EPs; revise this MasterPlan's Exec-Plan Registry and Dependency Graph (M4)


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope
adjustments, or unexpected interactions between child plans.
Provide concise evidence.

(None yet.)


## Decision Log

- Decision: Adopt MP-4's two-stage shape (one design milestone EP
  followed by a fan-out into per-combinator EPs) rather than
  enumerating per-combinator EPs upfront.
  Rationale: The design milestone's output (which combinators
  pass the keiki-guarantee bar, which iteration model `feedback`
  uses, whether `Kleisli` stays deferred) determines how many
  implementation EPs are warranted. MP-4 used the same shape for
  the same reason and shipped cleanly.
  Date: 2026-05-02

- Decision: Treat MP-9 (Profunctor / Category instances) as a
  downstream consumer of MP-8's output, not a co-resident
  initiative.
  Rationale: `Strong` requires `parallel`, `Choice` requires
  `alternative`. Bundling MP-8 and MP-9 would force MP-9 to wait
  on every MP-8 combinator decision; keeping them separate lets
  MP-9 advance whichever instances correspond to the combinators
  MP-8 has shipped at any given time.
  Date: 2026-05-02

- Decision: Stay within the pure formalism — no effectful
  composition variant, no iterate-until-quiescence `feedback`.
  Rationale: `docs/research/effects-boundary.md` pins effects to
  the runtime layer. An iterate-until-quiescence `feedback` can
  diverge, which is itself an effect; the pure-core boundary
  rules it out. The design milestone must commit to a bounded
  variant or decline `feedback` outright.
  Date: 2026-05-02


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones
or at completion. Compare the result against the original vision.

(To be filled during and after implementation.)
