---
id: 24
slug: composition-combinators-beyond-sequential-design-milestone
title: "Composition combinators beyond sequential — design milestone"
kind: exec-plan
created_at: 2026-05-03T01:40:45Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md"
---


# Composition combinators beyond sequential — design milestone

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This is a **design-only ExecPlan**. It produces no executable code; it
produces prose decisions that determine the per-combinator
implementation EPs that fan out from MasterPlan 8 (the parent at
`docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md`).

When this plan is complete, a reader will be able to answer five
questions purely from artefacts in the working tree:

1. Of the four combinators MP-8 lists in scope (`parallel`,
   `alternative`, `feedback`, `Kleisli`), which ones pass the
   keiki-guarantee bar against the *current* core
   (post-MP-1..MP-7) and warrant their own implementation EP, and
   which are re-deferred?
2. For `feedback`, which iteration model does keiki commit to:
   bounded-step `feedback n t f` (a fuel parameter), single-step
   `feedback1 t f` (one round, no loop), or decline `feedback`
   entirely?
3. For `alternative`, what cross-transducer mutual-exclusion check
   does the composite need, and which API in `Keiki.Symbolic`
   surfaces it (extend `isSingleValuedSym` to a two-input variant
   versus add a sibling `isAlternativeSafeSym`)?
4. For `Kleisli`, is the deferral confirmed (multi-event edge form
   from the synthesis note's §5 stays out of scope) or did the
   re-evaluation against the *current* core surface a viable
   reduction that doesn't require it?
5. What module shape — extend `Keiki.Composition` or add sibling
   modules per combinator family — do the implementation EPs
   inherit?

The visible artefacts produced by this plan are:

- This ExecPlan, with all milestones marked complete.
- `docs/research/composition-combinators-design.md`, with its
  "Future improvements (deferred)" section replaced by per-combinator
  design records (one section per in-scope combinator) reflecting
  the decisions above.
- The parent MasterPlan
  (`docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md`),
  with its Exec-Plan Registry and Dependency Graph extended by one
  row per per-combinator implementation EP added by the fan-out.
- One new ExecPlan in `docs/plans/` per per-combinator EP the fan-out
  admits (likely `parallel`, `alternative`, and one `feedback`
  variant; `Kleisli` is expected to be re-deferred). Each new EP is
  created via `bun agents/skills/exec-plan/init-plan.ts` with the
  parent path passed as `--master-plan`, producing a self-contained
  child plan a future contributor can pick up cold.

The reader can verify the plan succeeded by:

- Running `cabal build` and `cabal test` — both must pass
  unchanged, since this plan touches no source code.
- Reading
  `docs/research/composition-combinators-design.md` and observing
  per-combinator sections with concrete signatures, semantics, and
  acceptance criteria — instead of the current four-bullet "Future
  improvements (deferred)" list.
- Reading MP-8's Exec-Plan Registry and observing N+1 rows where N
  is the number of per-combinator EPs admitted (the +1 is EP-24
  itself, which is now "Complete").
- Reading each new per-combinator EP and observing it satisfies
  `agents/skills/exec-plan/PLANS.md`'s self-containment requirement.

This plan does **not** implement any combinator. Code lands in
follow-up per-combinator EPs.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] **M0 — Re-confirm prerequisites.** *(2026-05-03)*
    - [x] `cabal build all` — `Up to date`. GHC 9.12.3 (per
      `ghc --version`) matches `keiki.cabal`'s `tested-with: GHC ==
      9.12.*`. Zero warnings on the up-to-date rebuild.
    - [x] `cabal test all` — `169 examples, 0 failures` in 0.3381s.
      Test suite `keiki-test` passes (1 of 1 test suites, 1 of 1
      test cases). Test log at
      `dist-newstyle/build/aarch64-osx/ghc-9.12.3/keiki-0.1.0.0/t/keiki-test/test/keiki-0.1.0.0-keiki-test.log`.
    - [x] Read `src/Keiki/Composition.hs` (459 lines) end-to-end.
      Export surface: `Composite (..)`, `compose`, `WeakenR (..)`,
      `weakenL`, `weakenLTerm`, `weakenLPred`, `weakenLUpdate`,
      `substTerm`, `substPred`, `substUpdate`, `substOut`,
      `substOutFields`. Substitution machinery is structural over
      `HsPred` only; the `subst*` family takes a t1-side
      `OutTerm rs1 ci1 mid` and rewrites a t2-side AST into the
      `Append rs1 rs2` register file with `ci1` as the input. The
      `WeakenR rs1` class converts an `Index rs2 r` into an
      `Index (Append rs1 rs2) r` by walking rs1 with `SIdx` /
      `IS` prepends. The `Disjoint (Names rs1) (Names rs2)`
      constraint is the documented disjoint-slot-names precondition
      (used by `compose`'s body via raw `UCombine`).
    - [x] Read `src/Keiki/Symbolic.hs`'s key surface.
      `isSingleValuedSym` at line 384 is `BoolAlg phi`-polymorphic
      over a single `SymTransducer phi rs s ci co`; it iterates
      `[minBound .. maxBound :: s]` and checks pairwise
      `isBot (g_i `conj` g_j)` for each vertex's outgoing edges.
      `withSymPred` at line 407 is the `HsPred → SymPred` lift.
      The single-transducer shape means a cross-transducer check
      for `alternative` requires either threading both transducers
      through one analysis (option α in M2) or adding a sibling
      check (option β in M2).
- [x] **M1 — Re-evaluate each of the four combinators against the current core.** *(2026-05-03)*
    - [x] `parallel` — **RE-DEFER.** See Decision Log entry "M1
      verdict — parallel".
    - [x] `alternative` — **ADMIT.** See Decision Log entry "M1
      verdict — alternative".
    - [x] `feedback` — **ADMIT, single-step `feedback1` reduction
      (option b).** See Decision Log entry "M1 verdict — feedback".
    - [x] `Kleisli` — **RE-DEFER.** See Decision Log entry "M1
      verdict — Kleisli".
- [x] **M2 — Settle the three named open questions.** *(2026-05-03)*
    - [x] `feedback`'s iteration model: **single-step `feedback1`**.
      See Decision Log "M2 verdict — feedback iteration model".
    - [x] `alternative`'s mutual-exclusion check API: **no new API
      needed**. The `Either ci1 ci2` input makes the per-vertex
      single-valuedness check vacuous across the two transducers;
      the existing `isSingleValuedSym` (lifted via `withSymPred`) on
      the alternative composite suffices. See Decision Log "M2
      verdict — alternative mutual-exclusion check".
    - [x] `Kleisli`'s status: **re-defer** with explicit pointer to
      MP-7's state-refinement coverage. See Decision Log "M2 verdict
      — Kleisli deferral".
    - [x] Module shape: **extend `Keiki.Composition`**. See
      Decision Log "M2 verdict — module shape".
- [x] **M3 — Extend `docs/research/composition-combinators-design.md`.** *(2026-05-03)*
    - [x] Replaced "Future improvements (deferred)" with the
      "Combinators beyond `compose` — per-combinator design records"
      section. One full subsection per admitted combinator
      (`alternative`, `feedback1`) with signature, semantics,
      single-step example, three preservation arguments,
      limitations, acceptance criteria for the implementation EP.
      One "Re-deferred" subsection per re-deferred combinator
      (`parallel`, `Kleisli`) with deferral conditions and
      redirects.
    - [x] Extended the Decision summary table with an "EP-24 / MP-8"
      block listing all M2 verdicts.
    - [x] Updated `docs/research/keiki-generics-design.md`'s item F
      with a new "In progress (see EP-24 / MP-8)" paragraph
      summarising the fan-out and pointing to the per-combinator
      design records.
- [x] **M4 — Fan out per-combinator EPs and update MP-8.** *(2026-05-03)*
    - [x] Created EP-25
      (`docs/plans/25-alternative-composition-combinator-on-symtransducer.md`)
      via `bun agents/skills/exec-plan/init-plan.ts` with parent
      MP-8 and the shared intention.
    - [x] Created EP-26
      (`docs/plans/26-single-step-feedback-combinator-on-symtransducer.md`)
      via the same script.
    - [x] Fleshed out each child EP's prose end-to-end (Purpose,
      Progress, Decision Log, Context, Plan of Work, Concrete Steps,
      Validation, Idempotence/Recovery, Interfaces) per
      `agents/skills/exec-plan/PLANS.md`'s self-containment
      requirement. Each plan stands alone for a contributor cold-
      starting the implementation.
    - [x] Appended EP-25 and EP-26 to MP-8's Exec-Plan Registry as
      rows 2 and 3, with hard dep on EP-1 (this milestone, EP-24)
      and soft dep on EP-11 (external, the existing `compose`).
    - [x] Replaced MP-8's Dependency Graph placeholder with the
      concrete two-EP fan-out and a "Re-deferred (no EP)" footer
      naming `parallel` and `Kleisli`.
    - [x] Marked EP-24 "Complete" in MP-8's Exec-Plan Registry and
      ticked all five M0..M4 entries in MP-8's Progress section.
      Added per-combinator implementation entries for EP-25 and
      EP-26 to MP-8's Progress.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: This plan is design-only — no source code changes, no
  test changes, no example aggregates added. Code lands in
  per-combinator follow-up EPs.
  Rationale: MP-8's Decomposition Strategy explicitly mirrors MP-4's
  shape: a single design-milestone EP that fans out into
  per-combinator implementation EPs. Bundling design and
  implementation would force commitment to combinators that the
  re-evaluation may rule out, and would violate
  `agents/skills/exec-plan/PLANS.md`'s "every milestone must be
  independently verifiable" requirement (a design pass is verifiable
  by reading the resulting note; an implementation pass is verifiable
  by running tests; mixing them obscures both).
  Date: 2026-05-02

- Decision: Use the parent MasterPlan's intention
  (`intention_01knjzws4qezz9w8b0743zfqv8`) on this EP and on every
  child EP created by the fan-out, plus on every commit made under
  this plan.
  Rationale: The parent MasterPlan's frontmatter already records this
  intention; children inherit the parent's tracking by default so a
  query against the intention surface returns the whole MP-8 tree.
  Date: 2026-05-02

- Decision: **M1 verdict — `parallel` is re-deferred.**
  Rationale: Crem's `Parallel :: StateMachineT m a b -> StateMachineT
  m c d -> StateMachineT m (a, c) (b, d)` runs both sub-machines on
  a strict tuple input, stepping in lockstep. keiki's runtime model
  (per `docs/research/effects-boundary.md` §"What the runtime is
  responsible for", subsection "Queue dequeue") delivers one
  command at a time from a queue; there is no natural source of
  paired `(ci1, ci2)` inputs in event sourcing. The use cases MP-8
  cites in its Vision section ("product aggregates, e.g. distinct
  bounded contexts within one service") are operationally *sum*
  inputs (each external command lands in one bounded context per
  tick), which is the `alternative` shape, not the `parallel`
  shape. Two independent transducers with no shared input or
  register file produce nothing the user couldn't get by running
  them as two separate aggregates with separate queue subscriptions.
  Re-deferring keeps MP-8 focused on combinators with concrete
  authoring use cases. The deferral conditions (admit if a future
  authoring need surfaces a paired-input pattern, e.g. a runtime
  that genuinely batches commands across bounded contexts per tick)
  are recorded in the revised
  `docs/research/composition-combinators-design.md`.
  Date: 2026-05-03

- Decision: **M1 verdict — `alternative` is admitted.**
  Rationale: Crem's `Alternative :: StateMachineT m a b ->
  StateMachineT m c d -> StateMachineT m (Either a c) (Either b d)`
  is a perfect fit for keiki's event-sourcing model: each external
  command lands in exactly one of two sibling aggregates via the
  `Either` arm. The composite vertex is the sum
  `data CompositeSum s1 s2 = InL s1 | InR s2`. The composite
  register file is `Append rs1 rs2` (each side reads its own
  prefix/suffix). Edges from `InL s1` are t1's lifted edges (input
  alphabet `Either ci1 ci2`, with the input pattern matching
  `Left ci1`). Edges from `InR s2` are t2's lifted edges
  symmetrically. The post-MP-6 retirements (no `OFn`, no `PMatchC`)
  mean every t1 / t2 edge is structural by construction; no
  substitution caveats. Preservation arguments:
   * `solveOutput`: each composite output is `OPack` over an
     `InCtor (Either ci1 ci2) ifs` — built by lifting the underlying
     `InCtor ci_i ifs` through the `Either` arm. Inversion runs
     side's `solveOutput` and wraps the result in `Left` / `Right`.
   * `checkHiddenInputs`: each side's check inherits per-edge; the
     composite's combined warning list is the union.
   * `isSingleValuedSym`: at `InL s1`, only t1's edges fire (t2's
     guards over `ci2` are unsatisfiable when the input is `Left
     _`); single-valuedness reduces to t1's at s1. Symmetrically
     at `InR s2`. **No cross-transducer check is needed.**
  Date: 2026-05-03

- Decision: **M1 verdict — `feedback` is admitted with the
  single-step `feedback1` reduction (option b from MP-8's
  Decomposition Strategy).**
  Rationale: The aggregate ↔ policy loop in
  `docs/research/orchestration-sagas-choreography-and-feedback-loops-as-transducers.md`
  §5 is operationally "iterate until quiescence", which
  `docs/research/effects-boundary.md` classifies as an effect (the
  loop can diverge). The pure-core boundary forbids this, so MP-8
  required a bounded reduction. Of the two bounded reductions:
   * Bounded-step `feedback :: Int -> SymTransducer ... a (n b) ->
     SymTransducer ... b (n a) -> SymTransducer ... a (n b)`
     unrolls the loop `n` times. Symbolic analysis must enumerate
     all `n` rounds at every check, multiplying the analysis cost
     by `n` and forcing the user to pick `n` at the type or value
     level. The choice of `n` leaks an implementation detail of
     the runtime (how many policy reactions per external command)
     into the symbolic surface. Termination is guaranteed by
     construction but the symbolic edge graph grows linearly with
     `n`.
   * Single-step `feedback1 :: SymTransducer ... ci co ->
     SymTransducer ... co ci -> SymTransducer ... ci co` runs
     exactly one round: aggregate edge → policy reaction → one
     more aggregate edge. The composite expands to a single
     `compose t (compose policy_lifted t)` and the symbolic graph
     is the natural cross-product. Multi-round patterns are
     expressible by composing multiple `feedback1`s. Termination
     is trivial because there is no loop.
  The single-step reduction is strictly the smaller commitment:
  it is a re-use of `compose` plus a lift of the policy. Authors
  who need bounded-N rounds nest `feedback1` n times. If a
  bounded-step variant proves necessary later, it can be added
  without disturbing single-step's API.
  
  The "stateless policy" requirement in MP-8's Vision means the
  policy `f` has trivial state (a one-vertex transducer with
  `rs = '[]`); the lift is mechanical. Preservation arguments for
  all three keiki guarantees inherit from `compose`'s preservation
  arguments (the composite is two `compose` applications stacked).
  Date: 2026-05-03

- Decision: **M1 verdict — `Kleisli` is re-deferred with explicit
  pointer to MP-7's state-refinement coverage.**
  Rationale: Crem's `Kleisli :: StateMachineT m a (n b) ->
  StateMachineT m b (n c) -> StateMachineT m a (n c)` lifts
  sequential composition over a `Foldable` of inner events. keiki's
  edge form (`Edge.output :: Maybe (OutTerm rs ci co)`, defined at
  `src/Keiki/Core.hs:458`) emits at most one event per step. The
  three approaches to multi-event commands documented in
  `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`
  resolve to:
   * Approach 1 (state refinement) — what MP-7 / EP-20 shipped.
     Multi-event commands stay inside one transducer via
     intermediate vertices; the edge form is unchanged.
   * Approach 2 (GSM expansion) — rejected by MP-7 (the
     synthesis chose Approach 1).
   * Approach 3 (`MultiDecider`) — would widen `Edge.output` to
     `[OutTerm rs ci co]` and is explicitly out of MP-8's scope
     per Out-of-Scope item 4.
  Cross-transducer `Kleisli` requires Approach 3's edge widening,
  which is a separate (v3-class) initiative. **Within MP-8's
  scope, `Kleisli` collapses to `compose` for the single-event
  case keiki actually supports**; admitting `Kleisli` would
  duplicate `compose` without adding capability.
  
  The deferral conditions: re-evaluate `Kleisli` if and only if a
  future MasterPlan promotes Approach 3 to ship status. Until
  then, multi-event commands are written via state refinement
  (per `Keiki.Builder.chainTo` and `Keiki.Decider.toMultiDecider`
  with `DriverConfig`).
  Date: 2026-05-03

- Decision: **M2 verdict — `feedback`'s iteration model is
  single-step (`feedback1`).** See "M1 verdict — feedback" above.
  No additional rationale needed.
  Date: 2026-05-03

- Decision: **M2 verdict — `alternative`'s mutual-exclusion check
  needs no new API.** The `Either ci1 ci2` input makes the
  cross-transducer guard intersection vacuous: at composite vertex
  `InL s1`, t2's guards (over `ci2`) are unsatisfiable when the
  input is `Left _`; symmetrically at `InR s2`. The existing
  `isSingleValuedSym` (`src/Keiki/Symbolic.hs:384`), invoked on the
  alternative composite via `withSymPred`, decides single-valuedness
  per-vertex without seeing both transducers at once. The composite
  is single-valued whenever t1 and t2 are individually
  single-valued, exactly as for `compose`. The implementation EP
  records this fact and wires the check; no API change to
  `Keiki.Symbolic`.
  Rationale: This contradicts the existing
  `docs/research/composition-combinators-design.md`'s "Future
  improvements" wording, which speculated a "global mutual-exclusion
  check" was needed. The speculation arose from a misreading: in
  the `Either`-wrapped form (which MP-8 confirms is the right
  shape), the disjointness of `Left` vs `Right` already separates
  the two transducers' guard domains. The revised design note
  records the corrected analysis.
  Date: 2026-05-03

- Decision: **M2 verdict — `Kleisli`'s deferral is confirmed.** See
  "M1 verdict — Kleisli" above.
  Date: 2026-05-03

- Decision: **M2 verdict — module shape is "extend
  `Keiki.Composition`".** Both new combinators (`alternative`,
  `feedback1`) reuse `Keiki.Composition`'s `WeakenR` class, the
  `weakenL*` family of lifters, and the `subst*` family of
  substitution helpers. Splitting into siblings
  (`Keiki.Composition.Alternative`, `Keiki.Composition.Feedback`)
  would force every sibling to import the parent for these
  shared helpers, with no offsetting clarity gain — the parent's
  current 459-line size easily absorbs ~150 additional lines per
  combinator. The parent's haddock organizes by "* Foo" sections;
  the new combinators get their own sections within the same
  module. If a future combinator (e.g. an admitted `parallel` or
  `Kleisli`) brings substantially different machinery, splitting
  can happen at that point.
  Rationale: IP-1 in MP-8 names "extend `Keiki.Composition`" as
  the default. The default holds because the new combinators'
  substitution analyses are isomorphic to `compose`'s
  (`alternative`'s `Left`/`Right` lifting is even simpler, and
  `feedback1` is a literal re-use of `compose` twice). The
  per-combinator EPs may add Composite-vertex newtypes
  (`CompositeSum` for `alternative`) within `Keiki.Composition`
  alongside `Composite`.
  Date: 2026-05-03


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

### Outcomes (2026-05-03)

The design milestone delivered exactly what the Purpose section
promised:

- **Five Purpose-section questions answered**, all in concrete
  artefacts:
   1. Of the four MP-8 combinators, two are admitted (`alternative`,
      `feedback1`) and two are re-deferred (`parallel`, `Kleisli`).
      Verdicts in this Decision Log; design records under
      `docs/research/composition-combinators-design.md`.
   2. `feedback`'s iteration model is single-step `feedback1`. No
      fuel parameter; multi-round patterns nest `feedback1`s.
   3. `alternative` needs no new mutual-exclusion API. The `Either
      ci1 ci2` arms make the check vacuous; `isSingleValuedSym`
      via `withSymPred` on the composite suffices.
   4. `Kleisli`'s deferral is confirmed; redirected to MP-7's
      state-refinement coverage for the in-aggregate multi-event
      case.
   5. Module shape: extend `Keiki.Composition`. Per-combinator
      modules would require importing the shared substitution
      machinery from the parent for no clarity gain.
- **Design note revised.** The "Future improvements (deferred)"
  bullet list is replaced by per-combinator design records
  (signature, semantics, single-step example, three preservation
  arguments, limitations, acceptance criteria). Two admitted
  records (~250 lines) and two re-deferred records (~50 lines).
- **MasterPlan extended.** MP-8's Exec-Plan Registry, Dependency
  Graph, and Progress section reflect the two-EP fan-out
  concretely.
- **Two child EPs created.** Each child plan is fully
  self-contained per `agents/skills/exec-plan/PLANS.md` — a
  contributor with only the child plan and the working tree can
  implement the combinator end-to-end.
- **No source code changes.** The plan was design-only as
  specified. `git diff src/` and `git diff test/` are empty
  across all four EP-24 commits.

### Lessons learned

- **The `Either`-arm vacuity insight on `alternative`'s
  cross-transducer check.** EP-11's design speculation that
  `alternative` would require a "global mutual-exclusion check"
  was over-conservative: the `Either ci1 ci2` arms structurally
  separate the two transducers' guard domains, so per-vertex
  single-valuedness reduces to per-side single-valuedness without
  a cross-transducer step. This clarification let M2 close
  cleanly without proposing a new SBV API; the implementation EP
  (EP-25) inherits a much simpler acceptance criterion.

- **Single-step over bounded-step for `feedback`.** The pull
  toward bounded-step (option a) was the symmetry-with-crem
  argument. Single-step (option b) won on three independent
  counts: (1) trivial purity (no fuel needed), (2) composable
  (multi-round = nested `feedback1`s), (3) symbolic analysis
  inheriting from `compose`'s without modification. The composite
  vertex space grows multiplicatively per nesting, but that's a
  property of the use case, not the combinator.

- **The post-MP-6 retirements were the structural enabler.**
  EP-11's design listed several escape-hatch caveats (`OFn` on
  t1's outputs, `PMatchC` on t2's mid-side guards). MP-6 retired
  both, so the new combinators don't need to enumerate fallback
  rules. The post-MP-1..MP-7 core is genuinely simpler than
  EP-11's reference point.

- **The `parallel` re-deferral is the most significant scope
  reduction.** MP-8's Vision section listed `parallel` in scope
  with an authoring use case ("product aggregates within one
  service"). The re-evaluation surfaced that the operational
  shape for that use case is `alternative` (sum input from a
  queue), not `parallel` (strict tuple input). Confirming this
  required reading the runtime model in
  `docs/research/effects-boundary.md` and noting that no current
  keiki user has requested paired-input batching. Re-deferring
  rather than admitting kept MP-8 from over-shipping.

### What remains

EP-25 and EP-26 implement the two admitted combinators. Their
plans are written; a contributor can pick up either.

`parallel` and `Kleisli` re-deferral conditions are recorded.
Either may be reopened by a future MasterPlan if the deferral
conditions change (a runtime that batches commands across bounded
contexts; an Approach 3 multi-event edge form).

MP-9 (Profunctor / Category instances) has its soft dependency on
MP-8 partially resolved: `Choice` follows from `alternative`
(EP-25), `Category` follows from `compose` (EP-11, already
shipped). `Strong` is unblocked only if `parallel` is later
admitted.


## Context and Orientation

The reader of this plan has the working tree at the keiki repository
root and nothing else. This section establishes the vocabulary and
file map without assuming any prior plan in memory.

### What keiki is, in one paragraph

`keiki` is a pure-core Haskell library that models a single event
sourcing aggregate (or workflow / process manager) as a
**symbolic-register transducer**: a finite control graph, an
existentially-typed register file `RegFile rs` indexed by a
type-level slot list `rs :: [Slot]`, and edges that carry a guard
predicate `phi`, a register update term, an optional output term, and
a target vertex. The library lives entirely in `src/Keiki/` and
exposes its types and operations through the modules listed in
`keiki.cabal`'s `exposed-modules`. It has no `IO`. It pushes effects
to a runtime layer not implemented in this repository (per
`docs/research/effects-boundary.md`).

### The three load-bearing analyses

`keiki` ships three pure analyses that every composition combinator
must preserve end-to-end on the composite:

1. **`solveOutput` (mechanical inversion).** Defined at
   `src/Keiki/Core.hs:730`. Given an `OutTerm rs ci co`, a
   `RegFile rs`, and a wire-form output value of type `co`, it
   returns the input value of type `ci` that produced `co` — when
   the term is the structural `OPack` form (the v2 keiki output
   shape that pairs an `InCtor ci ifs` with a `WireCtor co fs` and
   an `OutFields rs ci fs` chain). The `OFn` form (the v1 escape
   hatch — an opaque `co -> Maybe ci`) is opaque and `solveOutput`
   returns whatever the function says.

2. **`checkHiddenInputs` (build-time hidden-input check).** Defined
   at `src/Keiki/Core.hs:786`. Walks every edge of a transducer and
   flags: ε-edges whose update reads the input symbol, edges with
   `OFn` outputs (opaque), and `OPack` outputs whose `OutFields`
   chain doesn't visit every slot of the named input constructor.
   The first two are warnings; the third indicates a field of the
   input that doesn't reach the wire-form output — a *hidden input*
   that breaks event-sourced replay.

3. **`isSingleValuedSym` (symbolic single-valuedness).** Defined at
   `src/Keiki/Symbolic.hs:384`. For each control vertex, checks
   that every distinct pair of outgoing edges has a `bot`
   (unsatisfiable) guard conjunction. The check is
   `BoolAlg phi`-polymorphic; with the `SymPred` carrier it uses an
   SBV/Z3-backed `isBot`. With the `HsPred` carrier it uses a v1
   syntactic over-approximation. The `withSymPred` adapter at
   `src/Keiki/Symbolic.hs:407` lifts an `HsPred`-carriered
   transducer into the `SymPred` carrier without changing the
   control graph or update / output terms.

A composition combinator that breaks any of these three guarantees
is unacceptable. Each per-combinator EP must produce the
preservation argument as part of its design record (see M3 below).

### The single combinator keiki ships today: `compose`

The current state, as of MP-8's creation, is:

- `src/Keiki/Composition.hs` exports `Composite`, `compose`, the
  `WeakenR` class, the `weakenL*` family of lifters, and the
  `subst*` family (substitution under a t1 edge output). The full
  signature is at `src/Keiki/Composition.hs:383`. The implementation
  walks t2's `HsPred` / `Term` / `Update` / `OutTerm` ASTs and
  substitutes `mid`-reads with structural references to t1's edge
  output, preserving all three guarantees end-to-end.
- The full design record, including the formal proof that the
  composite is single-valued whenever t1 and t2 are individually
  single-valued, is at
  `docs/research/composition-combinators-design.md`.
- The acceptance test is at `test/Keiki/CompositionSpec.hs`. The
  fixture composes a tiny `AlertSource` aggregate (defined inline)
  with `Keiki.Examples.EmailDelivery`. Six tests verify `step`,
  `omega`, `reconstitute`, `checkHiddenInputs`, and
  `isSingleValuedSym` on the composite.
- The original ExecPlan that delivered `compose` is at
  `docs/plans/11-composition-combinators-on-symtransducer.md`. EP-11
  was the only child of MP-4
  (`docs/masterplans/4-composition-combinators-on-symtransducer.md`).
  MP-4's Decomposition Strategy is the precedent MP-8 mirrors: one
  design-milestone EP that explicitly leaves room to fan out into
  per-combinator EPs once authoring need surfaces.

The four combinators this plan re-evaluates were enumerated in
EP-11's design pass as deferred:

- `feedback` — fixed-point combinator for the aggregate ↔ policy
  loop. Crem's signature is `Feedback :: StateMachineT m a (n b) ->
  StateMachineT m b (n a) -> StateMachineT m a (n b)` (where `n` is
  a `Foldable` of inner steps). Deferred for lack of a pure
  iteration model.
- `alternative` — disjoint-input dispatch. Crem's signature is
  `Alternative :: StateMachineT m a b -> StateMachineT m c d ->
  StateMachineT m (Either a c) (Either b d)`. Deferred for lack of
  a global mutual-exclusion check.
- `parallel` — independent product. Crem's signature is `Parallel
  :: StateMachineT m a b -> StateMachineT m c d -> StateMachineT m
  (a, c) (b, d)`. Deferred as "rarely useful at the aggregate
  level" without strong authoring evidence.
- `Kleisli` — sequential composition over multi-event edges.
  Crem's signature is `Kleisli :: StateMachineT m a (n b) ->
  StateMachineT m b (n c) -> StateMachineT m a (n c)`. Deferred for
  lack of a multi-event edge form (synthesis §5's MultiDecider).

### What changed since EP-11 (post-MP-1..MP-7)

The "current core" referenced by M1 means: post-MP-1 (DSL shape),
post-MP-2 (schema evolution), post-MP-3 (effects boundary), post-MP-4
(`compose`), post-MP-5 (TH splices `deriveAggregateCtors`,
`deriveWireCtors`, `deriveView`), post-MP-6 (v1 escape hatch
retirements: `OFn` retired in EP-16, `PMatchC` retired in EP-17,
`unsafeCombine` retired in EP-18), post-MP-7 (multi-event commands via
state refinement, EP-20). MP-7's retrospective at
`docs/masterplans/7-multi-event-commands-via-state-refinement-with-decider-facade-and-builder-dsl.md`
deliberately stayed with state refinement (Approach 1 in
`docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`)
rather than promoting the multi-event edge form (Approach 3).

The two structural shifts that the design re-evaluation must
reckon with:

- **`OFn` is retired.** EP-16 (`docs/plans/16-retire-ofn-and-mkout-from-keiki-core.md`)
  removed `OFn` from the public surface. `compose`'s "errors on `OFn`
  outputs" caveat is now history; every transducer authored against
  the post-MP-6 core has `OPack`-only outputs by construction. This
  simplifies several of the design questions below: substitution
  under any t1 output is now structural.
- **`PMatchC` is retired.** EP-17 removed `PMatchC` from the public
  surface. `compose`'s "errors on `PMatchC` over `mid`" caveat is
  history. t2's mid-side guards are structural (`PInCtor`, `PEq`,
  `TInpCtorField`) by construction.

These two retirements meaningfully change the design surface for
`parallel`, `alternative`, and `feedback`: the substitution analysis
no longer needs to enumerate escape-hatch fallback rules.

### The four research notes the design milestone must read

Each milestone in this plan refers back to specific subsections in
the following research notes. The reader who arrives at this plan
cold should read each at least once before starting M1:

1. `docs/research/composition-combinators-design.md` — the
   existing design note. The "Future improvements (deferred)"
   section (currently lines 685–719) is what this plan rewrites.
2. `docs/research/orchestration-sagas-choreography-and-feedback-loops-as-transducers.md`
   — describes the aggregate ↔ policy feedback pattern (§5,
   "Feedback Loops") and the saga / process manager pattern (§1).
   The "iterate until quiescence" loop in §5 is the loop a pure
   `feedback` cannot directly model.
3. `docs/research/effects-boundary.md` — pins effects to the
   runtime layer. Any combinator whose semantics requires
   unbounded iteration is an effect by this contract and stays out
   of `Keiki.Core` / `Keiki.Composition`. This is what forces
   `feedback` into a bounded reduction.
4. `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`
   — describes the three approaches to multi-event commands. The
   library lives in Approach 1 (state refinement) per MP-7;
   Approach 3 (`MultiDecider`) is what `Kleisli` would require if
   admitted. Re-confirming the deferral means re-confirming MP-7's
   choice from the composition angle.

### Module surface after the design milestone

The design milestone does not change any module's exports. However,
M2 must commit to whether the implementation EPs *will* extend
`src/Keiki/Composition.hs` (the default per IP-1 in MP-8) or split
per-combinator into sibling modules:

- `Keiki.Composition.Parallel`
- `Keiki.Composition.Alternative`
- `Keiki.Composition.Feedback`

The decision is informed by whether the per-combinator substitution
analysis differs enough from `compose`'s to justify a separate
module. Note that `Keiki.Composition` already exports the
substitution machinery (`WeakenR`, `weakenL*`, `subst*`); a sibling
module can import these.


## Plan of Work

The work is purely editorial: re-evaluate, decide, document, fan
out. There is no compilation step beyond the M0 baseline check.

### M0 — Re-confirm prerequisites

**Scope.** Verify the working tree builds cleanly and all tests pass
*before* the design pass touches anything. This anchors the
"prose-only, no code change" claim: a green run at M0 plus a green
run at M4 plus zero source-tree diffs equals proof that this plan
is design-only.

**What will exist at the end of this milestone.** A recorded GHC
version, build output, and test summary in this section's Progress
checklist (or in Surprises & Discoveries if anything fails).

**Commands.**

    cabal build all
    cabal test all

**Acceptance.** Both commands succeed with exit code 0. The test
summary reports zero failures. Record the GHC version printed by
`cabal build` (expected: `ghc-9.12.x` per `keiki.cabal`'s
`tested-with: GHC == 9.12.*`).

### M1 — Re-evaluate each of the four combinators against the current core

**Scope.** For each combinator, walk through the current
`src/Keiki/Composition.hs`, the post-MP-6 retirements (no `OFn`, no
`PMatchC`), and the existing design note. Produce a verdict
(admit / re-defer / admit-with-reduction) plus the formal
preservation sketch for each of the three keiki guarantees.

The walking order is mechanical → exotic: `parallel`,
`alternative`, `feedback`, `Kleisli`. The first two are mechanical
in shape (cross-product on disjoint halves); `feedback` introduces
iteration; `Kleisli` introduces multi-event edges.

**What will exist at the end of this milestone.** Four prose
verdicts in this plan's Decision Log, each citing the relevant
subsection of the existing design note and the relevant
post-retirement caveat. A summary in this Plan of Work section
listing the in-scope set.

**Commands.** None — this milestone is reading and writing.

**Acceptance.** Each verdict in the Decision Log names: (1) the
combinator, (2) the verdict (admit / re-defer / admit-with-reduction),
(3) the rationale citing concrete artefacts in the working tree, (4)
the preservation sketch for `solveOutput`,
`checkHiddenInputs`, and `isSingleValuedSym`. A reader who consults
only the Decision Log understands why the in-scope set is what it
is.

### M2 — Settle the three named open questions

**Scope.** Commit to concrete answers for the three questions MP-8
explicitly asks the design milestone to settle:

1. **`feedback`'s iteration model.** Three options, per MP-8's
   Decomposition Strategy:
   - **(a) Bounded-step `feedback :: Int -> SymTransducer ... -> SymTransducer ... -> SymTransducer ...`.**
     The integer caps the inner loop; the composite produces at
     most `n` policy reactions per external command. Pure (the cap
     guarantees termination).
   - **(b) Single-step `feedback1 t f`.** Runs exactly one round of
     the policy. The composite's edges from `(s1, s2)` are
     "(t1 edge from `s1`) ∘ (t-shape lifted f from `f`'s entry on
     t1's output) ∘ (t1 edge from the policy output)". Effectively
     `compose t (compose (lift f) t)` once, no fixed point. Pure
     trivially.
   - **(c) Decline.** Document the deferral; do not ship `feedback`
     in MP-8 at all.

   The decision must explain why the chosen option is the
   smallest reduction that preserves the keiki guarantees.

2. **`alternative`'s mutual-exclusion check API.** Two options:
   - **(α) Extend `isSingleValuedSym` to a two-input variant.**
     E.g. `isSingleValuedSymPair :: SymTransducer ... -> SymTransducer ... -> Bool`
     that checks both per-vertex single-valuedness on each side
     *and* cross-transducer guard exclusion at the alternative's
     dispatch site. Single API, polymorphic in the carrier.
   - **(β) Add a sibling `isAlternativeSafeSym`.** A new check that
     encapsulates the cross-transducer logic without disturbing
     `isSingleValuedSym`. Two APIs, but each does one thing.

   The decision must address how the new check composes with
   `withSymPred` and whether it costs an extra solver call per
   `alternative` use site.

3. **`Kleisli`'s status.** Three positions:
   - **Re-defer.** The multi-event edge form
     (`output :: Maybe (OutTerm rs ci co)` widening to `[OutTerm rs ci co]`)
     is out of MP-8 per MP-8's Out-of-Scope item 4. `Kleisli`
     stays deferred to a hypothetical v3 initiative.
   - **Admit, with multi-event edges.** Promote `Kleisli`. This
     conflicts with MP-8's Out-of-Scope and would require a new
     MasterPlan; not chosen unless the re-evaluation reveals a
     reduction that doesn't widen `Edge`.
   - **Admit, with state refinement only.** If the post-MP-7
     state-refinement ergonomics (`Keiki.Builder.chainTo`,
     `Keiki.Decider.toMultiDecider`) make `Kleisli`-style
     authoring expressible at the *aggregate* level without a
     cross-transducer combinator, document the redirection and
     re-defer the cross-transducer form.

The expected outcome (per MP-8's Decomposition Strategy) is the
re-deferral with a pointer to MP-7's state-refinement coverage.

**Module shape.** Settle whether the implementation EPs extend
`Keiki.Composition` or branch into siblings. The default is
"extend"; a counter-decision must justify the split (typically:
the substitution algorithm has materially different shape, or the
combinator carries non-trivial helpers that don't generalize).

**What will exist at the end of this milestone.** Four decisions in
this plan's Decision Log (one per question above plus the module
shape).

**Commands.** None.

**Acceptance.** Each decision is a single paragraph in the Decision
Log with rationale citing concrete artefacts (existing types in
`src/Keiki/Composition.hs`, existing analyses in
`src/Keiki/Symbolic.hs`, existing patterns in
`docs/research/orchestration-sagas-choreography-and-feedback-loops-as-transducers.md`).

### M3 — Extend `composition-combinators-design.md`

**Scope.** Replace the existing "Future improvements (deferred)"
section in `docs/research/composition-combinators-design.md` (lines
685–719 in the current file) with one full section per in-scope
combinator. Each section follows the same shape as the existing
`compose` design (`§"compose — type signature"`,
`§"compose — semantics"`, `§"compose — single-step example"`,
`§"How the composite preserves the three guarantees"`,
`§"Limitations and escape hatches"`):

- **Type signature.** The full Haskell signature with all
  constraints, kinded type variables, and the carrier `phi`.
- **Semantics.** The composite vertex type, register file,
  initial state, edge construction rules, `isFinal`. State the
  cross-product cardinality where relevant.
- **Single-step example.** A concrete walk-through using existing
  fixtures (`UserRegistration`, `OrderCart`, `EmailDelivery`, or
  `CompositionSpec`'s `AlertSource`) that demonstrates one round
  of execution.
- **Preservation arguments.** A subsection per guarantee
  (`solveOutput`, `checkHiddenInputs`, `isSingleValuedSym`)
  describing how the composite inherits or extends the analysis.
- **Limitations.** Any caveat that would surprise an author
  (state-space blow-up, restricted input shape, additional Z3
  cost).
- **Acceptance criteria for the implementation EP.** A short
  checklist the implementation EP can lift verbatim into its own
  Validation section.

The re-deferred combinators (whichever the M2 decisions place in
that bucket) get a shorter "Re-deferred" subsection that names the
deferral conditions and points to the sibling research that
covers the same need.

**What will exist at the end of this milestone.** A revised
`docs/research/composition-combinators-design.md` with per-combinator
sections that any implementation EP can quote directly.

**Commands.** None.

**Acceptance.** Reading the revised note, a contributor can answer
each combinator's design questions without consulting other
research notes. The note's table of contents (the heading hierarchy
visible in `grep '^##' docs/research/composition-combinators-design.md`)
shows one section per in-scope combinator.

The changes also extend `docs/research/keiki-generics-design.md`'s
item F summary to mention which follow-up combinators are now
admitted by MP-8 (the existing "Implemented (see EP-11 / MP-4)"
paragraph already mentions deferred combinators by name).

### M4 — Fan out per-combinator EPs and update MP-8

**Scope.** For each admitted combinator (the in-scope set decided
in M1/M2), create a new ExecPlan in `docs/plans/` that the
contributor for that combinator can pick up cold and implement.

**Commands (once per admitted combinator).**

    bun agents/skills/exec-plan/init-plan.ts \
        --title "<combinator-specific title>" \
        --master-plan docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md \
        --intention intention_01knjzws4qezz9w8b0743zfqv8

The init script picks the next sequential number, derives the
slug, writes frontmatter linking back to MP-8, and prints the
created path to stdout. After creation, edit the new EP file to
flesh out every section per `agents/skills/exec-plan/PLANS.md`'s
self-containment requirement: the EP must include the relevant
context from this design milestone, the substitution rules from
the revised design note, the worked-example sketch, and the
acceptance criteria. Cross-reference but do not omit.

After all per-combinator EPs are created, update MP-8:

- Append one row per child EP to MP-8's Exec-Plan Registry,
  using the actual file paths from the init script's output.
- Replace the placeholder bullet list in MP-8's Dependency Graph
  with the concrete fan-out (parallel, alternative, feedback variant,
  whatever else lands).
- Tick MP-8's Progress entries M0..M4 (those entries already point
  to EP-24, so this milestone matches them off).
- Mark this EP-24 row in MP-8's Exec-Plan Registry "Complete".

**What will exist at the end of this milestone.** N new files in
`docs/plans/` (one per admitted combinator), each self-contained.
MP-8 reflects the fan-out.

**Acceptance.** A contributor can read MP-8's Exec-Plan Registry,
pick any per-combinator EP whose hard dependencies are satisfied,
and implement it without reading any other plan in the tree.


## Concrete Steps

This is a design plan; the only concrete commands are the build
verification at M0 and the init script invocations at M4. Inline
those exactly here for reference.

### M0

Run from the repository root (`/Users/shinzui/Keikaku/bokuno/keiki`):

    cabal build all
    cabal test all

Both must succeed. Record the printed GHC version in M0's Progress
entry (expected: 9.12.x).

### M4

Run from the repository root, once per admitted combinator. The
title is short and action-oriented per
`agents/skills/exec-plan/PLANS.md` ("ExecPlan title style"):

    bun agents/skills/exec-plan/init-plan.ts \
        --title "Parallel composition combinator on SymTransducer" \
        --master-plan docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md \
        --intention intention_01knjzws4qezz9w8b0743zfqv8

    bun agents/skills/exec-plan/init-plan.ts \
        --title "Alternative composition combinator on SymTransducer" \
        --master-plan docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md \
        --intention intention_01knjzws4qezz9w8b0743zfqv8

    bun agents/skills/exec-plan/init-plan.ts \
        --title "<feedback-variant title>" \
        --master-plan docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md \
        --intention intention_01knjzws4qezz9w8b0743zfqv8

The exact `feedback` title depends on M2's decision (e.g.
"Bounded-step feedback combinator on SymTransducer" or
"Single-step feedback combinator on SymTransducer"). If `feedback`
is declined entirely, drop the third invocation.

If `Kleisli` is admitted (against M2's expected outcome), append a
fourth invocation. If re-deferred, do nothing — the deferral is
recorded in the revised design note, no EP needed.


## Validation and Acceptance

Acceptance for this design-only plan is observable in the working
tree, not in any test runtime:

1. **Build still green.** `cabal build all` and `cabal test all`
   produce the same pass/fail counts as M0. Source-tree diffs
   (`git diff src/`) are empty. Test-tree diffs (`git diff test/`)
   are empty.
2. **Design note revised.** `git diff docs/research/composition-combinators-design.md`
   shows the "Future improvements (deferred)" section replaced by
   per-combinator sections. The number of new sections matches the
   number of admitted combinators.
3. **MP-8 updated.** `git diff docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md`
   shows the Exec-Plan Registry has one row per admitted combinator
   plus one for EP-24 (now Complete), the Dependency Graph shows
   the concrete fan-out, and Progress entries M0..M4 are ticked.
4. **Per-combinator EPs created.** `ls docs/plans/` shows N new
   files, where N matches the admitted combinator count. Reading
   each new file confirms self-containment per
   `agents/skills/exec-plan/PLANS.md`.

Beyond compilation: a peer reading the revised design note and a
random per-combinator EP can answer the five Purpose-section
questions without consulting any other research note.


## Idempotence and Recovery

The design pass is idempotent: re-running M0's commands produces
the same green build. M3's edits to the design note are
overwriting; the prior content lives in git history. M4's
`init-plan.ts` invocations refuse to overwrite an existing file —
re-running picks the next sequential number, so a partially failed
run can be resumed by deleting the half-written child EP and
re-invoking the init script (or by reusing the already-created
file and re-fleshing its prose).

If M2's decisions need to be revisited mid-flight (e.g. a
preservation argument fails to close), update the Decision Log with
the revised decision and rationale dated to the revision day; do
not edit the prior decision in place. M3 and M4 then cascade from
the new decision.


## Interfaces and Dependencies

This plan introduces no new dependencies. It reads from and writes
to the following artefacts in the working tree:

**Read:**

- `src/Keiki/Composition.hs` — current composition module.
- `src/Keiki/Core.hs` — `Edge`, `SymTransducer`, `OutTerm`, `Update`,
  `HsPred`, `BoolAlg`, `solveOutput`, `checkHiddenInputs`,
  `applyEvents`.
- `src/Keiki/Symbolic.hs` — `SymPred`, `withSymPred`,
  `isSingleValuedSym`, `symIsBot`, `symSat`.
- `src/Keiki/Generics.hs` — `Append`, `appendRegFile`, `Names`,
  `Disjoint`.
- `src/Keiki/Examples/EmailDelivery.hs` and
  `src/Keiki/Examples/UserRegistration.hs` — fixtures the worked
  examples in M3 reuse.
- `test/Keiki/CompositionSpec.hs` — the existing `AlertSource`
  fixture used by `compose`'s test.
- `docs/research/composition-combinators-design.md` — the file M3
  rewrites.
- `docs/research/orchestration-sagas-choreography-and-feedback-loops-as-transducers.md`,
  `docs/research/effects-boundary.md`,
  `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`,
  `docs/research/architecture-comparison-fst-aggregate-vs-crem.md`,
  `docs/research/keiki-generics-design.md` — design context.
- `docs/masterplans/4-composition-combinators-on-symtransducer.md`
  and `docs/plans/11-composition-combinators-on-symtransducer.md`
  — precedent for the design-milestone-then-fan-out shape.

**Write:**

- `docs/research/composition-combinators-design.md` — replace
  "Future improvements (deferred)" with per-combinator sections.
- `docs/research/keiki-generics-design.md` — extend item F's
  "Implemented" paragraph to mention the MP-8 fan-out.
- `docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md`
  — extend Exec-Plan Registry, Dependency Graph, Progress.
- `docs/plans/<N>-<slug>.md` — one new file per admitted
  combinator, created by `init-plan.ts`.

**Required signatures at the end of this plan.** None new. The
combinator signatures (`parallel`, `alternative`, `feedback`,
`Kleisli`) are *documented* in the revised design note but
*implemented* in follow-up EPs. The point of this plan is that the
signatures *are* fully documented before the implementation work
begins.

**Git trailers.** Every commit made under this plan must include all
three trailers:

    MasterPlan: docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md
    ExecPlan: docs/plans/24-composition-combinators-beyond-sequential-design-milestone.md
    Intention: intention_01knjzws4qezz9w8b0743zfqv8

Per the project's CLAUDE.md (Conventional Commits) and the
master-plan / exec-plan skills' trailer requirements.
