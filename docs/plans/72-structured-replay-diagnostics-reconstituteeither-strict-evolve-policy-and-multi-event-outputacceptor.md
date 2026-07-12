---
id: 72
slug: structured-replay-diagnostics-reconstituteeither-strict-evolve-policy-and-multi-event-outputacceptor
title: "Structured replay diagnostics, Decider removal, and multi-event outputAcceptor"
kind: exec-plan
created_at: 2026-07-12T04:16:45Z
master_plan: "docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md"
---

# Structured replay diagnostics, Decider removal, and multi-event outputAcceptor

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This is Phase 2 of the master plan at
`docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md`
(EP-72 in its registry) and is release-gating for keiki `0.1.0.0`. The master plan's
Decision Log fixes the policy this plan implements, restated here so this document is
self-contained: **replay-facing APIs default to strict, structured-failure semantics;
the misleading `Keiki.Decider` facade is removed before `0.1.0.0`; the
`Either`-returning replay entry points become the primary documented surface, with the
existing Core `Maybe` variants kept as thin wrappers over them.**


## Purpose / Big Picture

keiki is a pure event-sourcing core: an aggregate is a "symbolic-register transducer"
(a finite state machine whose transitions read a typed command, update a typed register
file, and emit zero or more typed events), and rebuilding an aggregate's state from its
stored event log — "replay" — works by *inverting* each event back to the command that
produced it and re-running the transition. keiki targets critical business applications
where a replay defect silently corrupts state reconstruction, which is the worst failure
class an event-sourcing core can have.

Today every replay entry point (`reconstitute`, `applyEvents`, `applyEvent`,
`applyEventStreaming` in `src/Keiki/Core.hs`) collapses every possible failure into a
bare `Nothing`. An operator staring at a production incident learns only "the log did
not replay" — not which event failed, at which position, in what state, or why. Worse,
the `Decider` facade in `src/Keiki/Decider.hs` hides even the `Nothing`: its `evolve`
silently returns the *input state* when an event cannot be replayed, so corrupt or
foreign events are absorbed without a trace. And `src/Keiki/Acceptor.hs` documents an
equivalence between its output acceptor and `reconstitute` that is simply false for any
log produced by a multi-event edge.

After this plan, replaying a corrupted log through the new `reconstituteEither` names
the exact zero-based index of the offending event, the replay state at the moment of
failure, and a structured reason (no edge could have produced this event; more than one
edge could have — an ambiguity; a mid-chain event arrived out of order; the log ended in
the middle of a multi-event chain). A new seedable streaming replay fold gives runtime
authors (concretely: current keiro) a single library function that replaces the two
near-identical hand-rolled hydration folds keiro maintains today. `Keiki.Decider` is
removed from the exposed API, source, tests, and documentation instead of preserving
its letter-only and silently lossy projection. The output acceptor becomes multi-event aware, making its
documented equivalence with `reconstitute` actually true, proven by a test on a
multi-event fixture. All existing `Maybe`-returning entry points keep their exact
signatures and semantics (they are load-bearing for keiro) and are re-expressed as thin
wrappers over the new `Either` surface.

To see it working after implementation, from the repository root run
`nix develop --command cabal test all` and observe the new `ReplayEitherSpec` and
extended `AcceptorSpec` pass, with no remaining `Decider` module or spec; the Validation and Acceptance
section below shows the exact structured failure values a corrupted and a truncated log
must produce.


## Progress

- [ ] M1: `ReplayStepFailure`, `ReplayFailureReason`, `ReplayFailure` types added to `src/Keiki/Core.hs` and exported
- [ ] M1: `applyEventStreamingEither` implemented; `applyEventStreaming` re-expressed as a thin wrapper; existing suites stay green
- [ ] M1: `test/Keiki/ReplayEitherSpec.hs` created and registered (cabal `other-modules` + `test/Spec.hs`); single-step failure cases covered (no-inverting-edge, ambiguous inversion, queue mismatch)
- [ ] M2: `replayEvents` seedable fold implemented with strict index accounting
- [ ] M2: `applyEventsEither` and `reconstituteEither` implemented; `applyEvents` and `reconstitute` re-expressed as thin wrappers
- [ ] M2: list-level specs: corrupted-log index/reason, truncated multi-event chain, mid-chain seed resume, fold returns final `InFlight` wrapper without failing
- [ ] M3: `Keiki.Decider` removed from `keiki.cabal`, source, tests, exports, and documentation
- [ ] M3: uniquely valuable replay assertions from `DeciderSpec` moved to Core replay specs before the obsolete spec is deleted
- [ ] M4: `outputAcceptor` state carrier changed to `(InFlight s co, RegFile rs)`; equivalence haddock now true
- [ ] M4: `test/Keiki/AcceptorSpec.hs`: multi-event acceptance spec (fails before the fix, passes after), truncation rejection, reconstitute-agreement spec updated
- [ ] M5: `omega` haddock states the rejected/ε conflation loudly and points at `stepEither`
- [ ] M5: haddocks on `reconstitute`/`applyEvents`/`applyEventStreaming` repointed so the `Either` variants are the primary documented surface
- [ ] M5: `CHANGELOG.md` entry; full sweep `cabal build all`, `cabal test all`, `nix fmt -- --no-cache`; living sections updated


## Surprises & Discoveries

Entries below were verified during plan authoring; add implementation-time discoveries
as they occur.

- Verified (2026-07-11, plan authoring): the multi-event round-trip test in
  `test/Keiki/DeciderSpec.hs` passes *by accident*. `runRound` (line 64) is
  `foldl (evolve d) acc (decide d cmd acc)`. For `StartRegistration`, `decide` returns
  the two-event chain `[RegistrationStarted …, ConfirmationEmailSent …]` from the
  collapsed entrance edge (`test/Keiki/Fixtures/UserRegistration.hs:307-323`). `evolve`
  on the head event succeeds — the edge's *entire* update (writing `email`,
  `confirmCode`, `registeredAt`) runs and the vertex advances to
  `RequiresConfirmation`. `evolve` on the tail event `ConfirmationEmailSent` then finds
  no outgoing edge of `RequiresConfirmation` whose head output inverts it (`Confirm`
  heads with `AccountConfirmed`, `Resend` with `ConfirmationResent`, and the GDPR edge
  is an ε-edge skipped by `applyEvent`'s `o : _` pattern at `src/Keiki/Core.hs:1040`),
  so `applyEvent` returns `Nothing` and the fallback at `src/Keiki/Decider.hs:115`
  silently returns the input state. The final snapshot is correct only because the head
  edge's update already did all the work; the tail event is dropped on the floor.
- Verified (2026-07-11, plan authoring): the equivalence documented at
  `src/Keiki/Acceptor.hs:115-123` ("`accepts (outputAcceptor t) events` iff
  `reconstitute t events` reaches a final vertex") is false for multi-event logs:
  `aStep` (line 130) uses the letter-only `applyEvent` while `reconstitute`
  (`src/Keiki/Core.hs:1131-1136`) folds the InFlight-aware `applyEventStreaming`. The
  canonical five-event `userReg` log replays fine via `reconstitute` but is rejected by
  the acceptor at its second event. The existing `AcceptorSpec` never noticed because
  its output-acceptor cases use the letter-only `emailDelivery` fixture
  (`test/Keiki/AcceptorSpec.hs:68-85`).
- Noted (2026-07-11): keiro already built everything this plan adds, by hand, twice —
  see Context and Orientation for the prior-art walkthrough of `hydrate` /
  `hydrateFull`.


## Decision Log

- Decision: implement the master plan's fixed policy — strict structured-failure
  default; remove `Keiki.Decider`; make `Either` entry points primary and keep Core
  `Maybe` variants as thin wrappers.
  Rationale: the user explicitly selected removal. Current keiro uses `Keiki.Core`
  replay directly and does not import the facade. The facade cannot represent
  multi-event `InFlight` replay honestly, and preserving it would maintain a second,
  lossy abstraction before the first release.
  Date: 2026-07-12 (supersedes the 2026-07-11 strict-`evolve` redesign)

- Decision: the replay-failure vocabulary reuses the existing EP-56 step-diagnostic
  types — `EdgeRef`, `RejectedEdgeSummary`, `MatchedEdgeSummary`
  (`src/Keiki/Core.hs:920-947`) — and mirrors `StepFailure`'s style (structured, `Eq` +
  `Show`, carries *no register values*: diagnostics summarize, they do not dump state).
  Events (`co` values) *are* carried where they identify the failure — an event log is
  already observable data, unlike the register file.
  Rationale: master plan integration point 3 makes EP-72 the owner of this vocabulary
  and directs reuse; plan 71 (validation warnings) shares `EdgeRef` as the edge-identity
  vocabulary, and plan 73's property harness renders these values in counterexamples,
  so stock `Eq`/`Show` instances are required.
  Date: 2026-07-11

- Decision: two-level failure shape. `ReplayStepFailure s co` describes one event's
  failure with no positional information (returned by the single-step
  `applyEventStreamingEither`); `ReplayFailure s co` wraps a reason with the zero-based
  event index and the `InFlight` wrapper state at failure (returned by list-level entry
  points). Truncation (`ReplayLogTruncated`) is a *list-level* reason only: the
  seedable fold `replayEvents` never fails on a log that ends mid-chain — it returns
  the final `InFlight` wrapper on the `Right` so the caller decides — and only the
  strict facades `applyEventsEither`/`reconstituteEither` convert a final `InFlight`
  into `ReplayLogTruncated`. For truncation the index is the *length* of the input log
  (the position at which the next expected event was missing).
  Rationale: mirrors exactly the layering keiro hand-rolled (`finishReplay` at
  `keiro/src/Keiro/Command.hs:259-264` converts a final `InFlight` into a typed error
  *after* the fold), and a runtime that replays page-by-page must be able to end a page
  mid-chain without that being an error.
  Date: 2026-07-11

- Decision: `ReplayStepFailure` has three constructors, not four: the
  "vertex has no outgoing edges" case is represented by `ReplayNoInvertingEdge` with an
  empty summary list rather than a dedicated constructor (unlike `StepFailure`, which
  separates `NoOutgoingEdges`).
  Rationale: on the replay side, "an event arrived at a terminal vertex" and "an event
  arrived that no edge could produce" are the same operator question ("where did this
  event come from?"), the empty list already distinguishes them, and per-edge rejection
  cannot be refined further anyway (a rejected edge may have failed `solveOutput`
  inversion *or* its guard; distinguishing would require dumping recovered inputs,
  which the no-register-values rule forbids). `RejectedEdgeSummary`'s `rejectedGuard`
  field is documented as "always False, leaves room for richer reasons later" — we
  inherit that posture.
  Date: 2026-07-11

- Decision: do not replace `Keiki.Decider` with a deprecated shim or a redesigned
  record in this initiative.
  Rationale: the supported Core surface already provides `stepEither`,
  `applyEventStreamingEither`, and the seedable structured fold. A shim would preserve
  the mistaken idea that letter-only `evolve` is the aggregate replay primitive.
  Date: 2026-07-12

- Decision: no `applyEventEither` (letter-only `Either` variant). The single-event
  `Either` step is `applyEventStreamingEither` only.
  Rationale: `applyEventStreaming` is the real replay step (`reconstitute`,
  `applyEvents`, keiro's hydration all fold it); the letter-only `applyEvent` remains a
  niche verb for callers who *know* their transducer is letter-only, and duplicating
  the diagnostic surface there adds API without a consumer. Its haddock already directs
  multi-event callers to the streaming path.
  Date: 2026-07-11

- Decision (keiro impact statement, master plan integration point 6): the load-bearing
  surfaces `step`, `applyEventStreaming`, `applyEvents`, `InFlight` keep their exact
  signatures and semantics; they are re-expressed internally as wrappers over the new
  `Either` primitives, and the unchanged existing test suites
  (`test/Keiki/CoreApplyEventsSpec.hs`, `test/Keiki/CoreInFlightSpec.hs`,
  `test/Keiki/NoThunksSpec.hs`) are the regression evidence. Current keiro imports
  none of `reconstitute`, `stepEither`, `Keiki.Decider`, or the acceptors; the
  facade's removal is coordinated as a pre-release API deletion. Everything else in
  this plan is additive except the acceptor carrier correction.
  Date: 2026-07-12


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Everything in this section can be re-verified by reading the cited files; no prior
context is assumed.

### The machine and its replay direction

A keiki aggregate is a `SymTransducer phi rs s ci co` (`src/Keiki/Core.hs`): a graph of
control vertices `s` where each outgoing `Edge` carries a guard over the command type
`ci` and the register file `RegFile rs` (a typed heterogeneous tuple of named slots),
an update to those registers, a declared `target` vertex, and an `output :: [OutTerm
rs ci co]` — the list of events the edge emits. An edge with an empty output is an
"ε-edge" (state changes, nothing observable is emitted); one output is a "letter edge";
two or more is a "multi-event edge". The test fixture
`test/Keiki/Fixtures/UserRegistration.hs` is the canonical aggregate: its entrance edge
from `PotentialCustomer` (builder form lines 307-323, AST form lines 398-429) is a
length-2 multi-event edge emitting `RegistrationStarted` then `ConfirmationEmailSent`
for one `StartRegistration` command — verify this before starting; several tests below
depend on it.

Forward execution ("decide") runs `delta`/`omega`/`step` (`src/Keiki/Core.hs:866-918`).
Replay runs the *inverse*: given an observed event, find the unique edge whose output
could have produced it, recover the command via `solveOutput`, check the guard, and
re-run the update. Because a multi-event edge commits all its register updates at the
first (head) event and then merely verifies the remaining (tail) events by equality,
replay threads a wrapper state `InFlight s co` (`src/Keiki/Core.hs:1063-1066`):
`Settled s` at a stable vertex, `InFlight s pendingQueue` mid-chain. The step function
for this is `applyEventStreaming` (`src/Keiki/Core.hs:1089-1118`); the letter-only,
non-wrapper variant is `applyEvent` (`src/Keiki/Core.hs:1030-1045`, head-only
inversion). Full-log replay is `reconstitute` (`src/Keiki/Core.hs:1131-1136`) and
chunk replay from a caller-supplied start is `applyEvents`
(`src/Keiki/Core.hs:1167-1179`).

### Defect 1 — Maybe-only replay

`reconstitute` and `applyEvents` return `Maybe (s, RegFile rs)`. Every distinct failure
— foreign event, ambiguous inversion, out-of-order mid-chain event, truncated chain —
collapses to `Nothing` (see the `go` loop at `src/Keiki/Core.hs:1173-1179`). Contrast
with the forward direction, which since EP-55/EP-56 has an excellent structured
vocabulary: `stepEither` returns `Either (StepFailure s) …` where `StepFailure`
(`src/Keiki/Core.hs:959-963`) distinguishes `NoOutgoingEdges` / `NoMatchingEdge` /
`AmbiguousEdges`, each carrying `EdgeRef` locators (`src/Keiki/Core.hs:923-927`: the
source vertex plus the zero-based position of the edge in `edgesOut t source`) and
per-edge summaries (`RejectedEdgeSummary`, `MatchedEdgeSummary`,
`src/Keiki/Core.hs:934-947`) that deliberately carry no register values. The replay
direction deserves the same vocabulary; this plan adds it.

### Defect 2 — every runtime must hand-roll the same hydration fold

Current keiro, the event-sourcing framework whose compatibility matters to this plan,
hand-rolls TWO
near-identical replay folds in `keiro/src/Keiro/Command.hs:201-378`: `hydrate` (seeds
replay from a persisted snapshot, lines 221-306) and `hydrateFull` (seeds from the
transducer's initial state, lines 308-378). Read them as prior art if the repository is
available; the essentials are restated here so this plan stands alone. Each fold: (a)
carries an accumulator `Replay` pairing the keiki wrapper state (`Keiki.InFlight s co`),
the register file, and keiro-side bookkeeping (a `StreamVersion` counter and global
position); (b) calls `Keiki.applyEventStreaming` per event and converts every `Nothing`
into a typed `HydrationReplayFailed streamVersion` error (lines 287 and 359); (c) after
the fold, checks whether the final wrapper is `Settled` and converts a final `InFlight`
into the same typed error (`finishReplay`, lines 259-264 and 336-341). All of (b) and
(c) is generic replay logic that belongs in keiki. The new `replayEvents` fold is
designed so keiro could delete both folds: it starts from an arbitrary seed
`(InFlight s co, RegFile rs)` (a snapshot seed is `(Settled snapshotState, snapshotRegs)`;
a fresh seed is `(Settled (initial t), initialRegs t)`), reports failure with the
zero-based event index (keiro's version arithmetic becomes
`seedVersion + fromIntegral replayFailedIndex` — the accumulator stays on the caller's
side), and returns the final wrapper state so the caller performs the `Settled` check
itself. Because the seed and result are both wrapper states, a multi-event chain may
span two page-sized calls without error. Migrating keiro itself is out of scope for
this plan (the master plan scopes keiro changes out); the deliverable here is a
signature that makes that migration a deletion.

### Defect 3 — `Keiki.Decider` is a lossy duplicate replay abstraction

`src/Keiki/Decider.hs` projects the transducer onto a `decide` / `evolve` record. Its
`evolve` field wraps the letter-only `applyEvent` and returns the input state when
replay fails. This silently absorbs corrupt or foreign events and drops multi-event
tails. The accidental passing test is documented in Surprises & Discoveries.

Changing only the result to `Maybe` would remove the fallback but preserve the wrong
replay unit: one event and a settled state, with no `InFlight` queue. Adding the vertex
and failure parameters needed for honest structured replay would duplicate Core's
actual API. The selected correction is therefore to remove the facade entirely.
Current keiro uses `step`, `applyEventStreaming`, `applyEvents`, and `InFlight`
directly and does not import `Keiki.Decider`.

### Defect 4 — `outputAcceptor` documents a false equivalence

`src/Keiki/Acceptor.hs` names the transducer's two acceptor projections. The output
acceptor's haddock (lines 115-123) claims `accepts (outputAcceptor t) events` holds iff
`reconstitute t events` reaches a final vertex. But `aStep` (line 130) is the
letter-only `applyEvent` while `reconstitute` is InFlight-aware, so any multi-event log
is accepted by `reconstitute` and rejected by the acceptor. The fix: the acceptor's
state carrier becomes the wrapper pair `(InFlight s co, RegFile rs)`, `aStep` becomes
`applyEventStreaming`, and `aIsFinal` holds only for `Settled s` with `isFinal t s`
(a mid-chain `InFlight` state is never final — which also makes the acceptor correctly
reject truncated chains, matching `reconstitute`'s `Nothing`). Current keiro does not
use `Acceptor`, `inputAcceptor`, or `outputAcceptor`; the carrier correction does not
require a keiro source migration.

### Defect 5 — `omega` conflates rejection with silence

`omega` (`src/Keiki/Core.hs:889-902`) returns `[]` for three inequivalent situations:
no edge matched (rejected command), multiple edges matched (ambiguity), and exactly one
ε-edge matched (accepted command that emits nothing). This plan fixes the `omega`
documentation loudly and points at `stepEither`, which distinguishes all three.

### Coordination with sibling plans

Plan 71 (`docs/plans/71-align-build-time-validation-with-replay-head-recoverability-cross-edge-inversion-ambiguity-and-guard-implies-input-read-checks.md`)
adds build-time validation warnings; this plan adds runtime replay failures. Both reuse
`EdgeRef` as the shared edge-identity vocabulary (master plan integration point 3) —
do not fork or rename it. Plan 73
(`docs/plans/73-decide-replay-round-trip-property-harness-across-all-fixtures.md`)
renders this plan's failure values in property-test counterexamples, which is why every
new type derives stock `Eq` and `Show`. Neither sibling plan blocks this one; both are
skeletons at time of writing.

### Build environment

GHC 9.12 via the flake. All commands run from the repository root inside
`nix develop`. Formatting is `nix fmt -- --no-cache` (the fourmolu config is canonical;
run it before committing). Tests are Hspec, driven by `test/Spec.hs` which imports each
spec module qualified and runs them from one `main`; test modules are listed in
`keiki.cabal` under the `keiki-test` suite's `other-modules` (around line 101).


## Plan of Work

The work is five milestones. M1 and M2 build the new Core surface bottom-up (single
step, then folds); M3 and M4 apply the policy to the two zero-consumer facades; M5 is
documentation, changelog, and the final sweep. Each milestone leaves
`cabal build all && cabal test all` green.

### Milestone 1 — replay-failure vocabulary and the single-step Either primitive

Scope: add the failure types and `applyEventStreamingEither` to `src/Keiki/Core.hs`,
re-express `applyEventStreaming` as a wrapper over it, and cover the single-step
failure cases in a new spec module. At the end of M1, a single unreplayable event can
be *explained*; nothing else has changed behavior.

In `src/Keiki/Core.hs`, immediately after the `InFlight` declaration (currently ending
at line 1066) and before `applyEventStreaming`, add three types (full definitions in
Interfaces and Dependencies below): `ReplayStepFailure s co` (three constructors:
`ReplayNoInvertingEdge s [RejectedEdgeSummary s]` — at `Settled s`, no outgoing edge's
head output inverted the observed event with a satisfied guard, one summary per
outgoing edge in declaration order, empty when the vertex has no outgoing edges;
`ReplayAmbiguousInversions s [MatchedEdgeSummary s]` — two or more edges inverted, the
runtime witness of a single-valuedness violation on the inverse; and
`ReplayQueueMismatch s co [co]` — at `InFlight s queue`, the observed event (carried
second) did not equal the head of the expected queue (carried third, in full));
`ReplayFailureReason s co` (`ReplayEventFailed (ReplayStepFailure s co)` or
`ReplayLogTruncated [co]` carrying the pending expected events when the log ended
mid-chain); and the record `ReplayFailure s co` with fields `replayFailedIndex :: Int`
(zero-based index into the input log; for truncation, the log's length),
`replayFailedState :: InFlight s co` (the wrapper state when the failure hit), and
`replayFailureReason :: ReplayFailureReason s co`. All derive stock `(Eq, Show)`.
Write haddocks in the same voice as the `StepFailure` block, including the explicit
"carries NO register values" sentence and a pointer to this plan's Decision Log entry
about the empty-list convention.

Then implement `applyEventStreamingEither` with the same two arms as
`applyEventStreaming` (`src/Keiki/Core.hs:1096-1118`), except the `Settled` arm binds
the indexed edge list (`zip [0 ..] (edgesOut t s)`, exactly as `stepEither` does at
line 976) so failures can name edges: an empty or non-inverting candidate set yields
`Left (ReplayNoInvertingEdge s summaries)` where `summaries` has one
`RejectedEdgeSummary` per outgoing edge (including ε-edges — they exist and could not
have produced the event) with `rejectedGuard = False`, mirroring `stepEither`'s
construction at lines 986-995; two or more inversions yield
`Left (ReplayAmbiguousInversions s matchedSummaries)`; exactly one behaves as today
(commit the update, evaluate the tail, return `Settled`/`InFlight`). The `InFlight`
arm returns `Left (ReplayQueueMismatch s co queue)` on a head mismatch, and treats the
degenerate hand-constructed `InFlight s []` the same way (empty expected queue — today
this is `Nothing` at line 1112; the wrapper equivalence below demands it stay a
failure). Keep the *same evaluation discipline* as the current `applyEventStreaming`
(the `let regs' = applyEdgeUpdate …` without an extra bang, line 1104): the write path
already forces slots via `setSlotN`, and `test/Keiki/NoThunksSpec.hs` arbitrates
strictness regressions.

Re-express the load-bearing `applyEventStreaming` as exactly

```haskell
applyEventStreaming t w regs co =
  either (const Nothing) Just (applyEventStreamingEither t w regs co)
```

keeping its signature and haddock (extend the haddock to name the `Either` variant as
the primary surface). This must be observationally identical to the old body; the
unchanged `test/Keiki/CoreInFlightSpec.hs`, `test/Keiki/CoreApplyEventsSpec.hs`, and
`test/Keiki/NoThunksSpec.hs` are the proof.

Export the three new types (with constructors) and the new function from the module
export list — add them in the "Pure-layer entry points" group next to `stepEither`
(`src/Keiki/Core.hs:128-141`).

Create `test/Keiki/ReplayEitherSpec.hs` (register it in `keiki.cabal` under the
`keiki-test` suite's `other-modules`, alphabetically, and in `test/Spec.hs` following
the existing qualified-import-plus-runner pattern). M1 cases, all against `userReg`
from `test/Keiki/Fixtures/UserRegistration.hs` unless noted: (a) a foreign event at a
`Settled` vertex produces `Left (ReplayNoInvertingEdge …)` naming every outgoing edge
(exact expected value in Validation and Acceptance); (b) a wrong event while `InFlight`
produces `Left (ReplayQueueMismatch …)` carrying the observed event and the full
expected queue; (c) ambiguous inversion: hand-build a tiny two-edge transducer as a
plain `SymTransducer` record (the way `userRegAST` is built at
`test/Keiki/Fixtures/UserRegistration.hs:387-429`, and in the spirit of the
WireCtor-free inline fixture in `test/Keiki/StepEitherSpec.hs`) whose single vertex
has two copies of the `userReg` entrance edge (reuse `inCtorStart`,
`wireRegistrationStarted`, and the exported `inpStart` helpers) differing only in
`target`; feeding the head event must yield
`Left (ReplayAmbiguousInversions …)` listing both `MatchedEdgeSummary` values, and the
`Maybe` wrapper must yield `Nothing` on the same input (locking the wrapper
equivalence on a failure case).

Acceptance: `cabal test all` green; the new spec's three failure shapes assert exact
structured values with `shouldBe`.

### Milestone 2 — the seedable fold, `applyEventsEither`, `reconstituteEither`

Scope: the list-level surface. At the end of M2, a corrupted log names its failing
index and a truncated chain is reported as such; keiro-shaped consumers have their
fold.

In `src/Keiki/Core.hs`, after `applyEventStreamingEither`, add `replayEvents`: a strict
left fold from an arbitrary seed. Signature in Interfaces and Dependencies; semantics:
thread `(InFlight s co, RegFile rs)` through `applyEventStreamingEither` over the list
with a strict zero-based index counter (`!i`); on the first `Left stepFailure`, return
`Left ReplayFailure { replayFailedIndex = i, replayFailedState = <wrapper state
*before* the failing event>, replayFailureReason = ReplayEventFailed stepFailure }`;
if every event applies, return `Right` with the final `(wrapper, regs)` — including a
final `InFlight`, which is *not* an error here (the caller detects mid-chain endings;
see Decision Log). Match the existing `applyEvents` `go`-loop evaluation discipline
(`src/Keiki/Core.hs:1173-1179`) plus the strict counter.

Then `applyEventsEither`: seed `replayEvents` with `(Settled s0, regs0)`; on
`Right (Settled s, regs)` return `Right (s, regs)`; on `Right (InFlight s pending,
_regs)` return `Left ReplayFailure { replayFailedIndex = length events,
replayFailedState = InFlight s pending, replayFailureReason = ReplayLogTruncated
pending }`. And `reconstituteEither t = applyEventsEither t (initial t, initialRegs t)`.
Re-express the `Maybe` versions as thin wrappers:
`applyEvents t seed = either (const Nothing) Just . applyEventsEither t seed` and
`reconstitute t = either (const Nothing) Just . reconstituteEither t` — signatures and
haddock contracts unchanged (update the haddock prose to present the `Either` variants
as primary, per policy). Export `replayEvents`, `applyEventsEither`,
`reconstituteEither`.

Extend `test/Keiki/ReplayEitherSpec.hs`. Reproduce the canonical five-event log locally
(the spec must be self-contained, as `test/Keiki/CoreApplyEventsSpec.hs:17-24` does):
`RegistrationStarted "alice@x" "Z9F4" t0; ConfirmationEmailSent "alice@x";
ConfirmationResent "alice@x" "K2P7" t100; AccountConfirmed "alice@x" "K2P7" t200;
AccountDeleted "alice@x" t300`. Cases: (a) the intact log reconstitutes to
`Right (Deleted, regs)` agreeing with `reconstitute`; (b) corrupting index 1 (replace
`ConfirmationEmailSent` with a foreign event) yields the exact `Left` shown in
Validation and Acceptance — failing index 1, `InFlight` state, `ReplayQueueMismatch`;
(c) a foreign first event yields failing index 0 at `Settled PotentialCustomer` with
`ReplayNoInvertingEdge`; (d) `take 1` of the log yields `ReplayLogTruncated` with index
1 and the pending `ConfirmationEmailSent` queue; (e) `replayEvents` seeded mid-chain
with `(InFlight RequiresConfirmation [ConfirmationEmailSent …], regsAfterHead)` and fed
exactly `[ConfirmationEmailSent …]` returns `Right (Settled RequiresConfirmation, …)` —
proving arbitrary-seed resumption across a "page boundary"; (f) `replayEvents` fed only
the head event from the initial seed returns `Right` with a final `InFlight` wrapper
(the fold does not fail on truncation); (g) wrapper agreement: for the corrupted log,
`applyEvents`/`reconstitute` return `Nothing` where the `Either` variants return
`Left` (thin-wrapper law on a failure).

Acceptance: `cabal test all` green, including the untouched
`test/Keiki/CoreApplyEventsSpec.hs` (wrapper re-expression changed nothing observable).

### Milestone 3 — remove `Keiki.Decider`

Scope: delete the lossy duplicate abstraction while preserving any useful regression
coverage in Core.

First inventory `test/Keiki/DeciderSpec.hs`. Move its uniquely valuable multi-event
tail-loss, epsilon-boundary, and canonical round-trip assertions into
`ReplayEitherSpec`, `CoreApplyEventsSpec`, or the EP-73 round-trip harness. Do not move
tests whose only purpose is the obsolete record projection.

Then remove `Keiki.Decider` from `keiki.cabal`'s exposed modules, delete
`src/Keiki/Decider.hs` and `test/Keiki/DeciderSpec.hs`, remove the test registration,
and sweep `README.md`, `ROADMAP.md`, research notes, haddocks, and changelog references.
Do not add a compatibility or deprecated shim.

Acceptance: `rg -n "Keiki\\.Decider|toDecider|evolveStreaming" . --glob
'!dist-newstyle/**' --glob '!docs/**'` returns no hits (plan history under `docs/`
is exempt), current keiro has no source change, and the migrated Core regression
assertions pass.

### Milestone 4 — InFlight-aware `outputAcceptor`

Scope: make the documented acceptor/reconstitute equivalence true. At the end of M4, a
multi-event log is accepted iff `reconstitute` reaches a final vertex.

In `src/Keiki/Acceptor.hs`: change `outputAcceptor`'s result type to
`Acceptor co (InFlight s co, RegFile rs)` with `aStep = \(w, regs) co ->
applyEventStreaming t w regs co`, `aInitial = (Settled (initial t), initialRegs t)`,
and `aIsFinal = \(w, _regs) -> case w of Settled s -> isFinal t s; InFlight {} ->
False`. Import `InFlight (..)` and `applyEventStreaming` from `Keiki.Core` (dropping
the now-unused `applyEvent` import if nothing else uses it). Update the haddock: the
equivalence statement (lines 115-123) is now true by construction — state it as
`accepts (outputAcceptor t) events == case reconstitute t events of Just (s, _) ->
isFinal t s; Nothing -> False`, and explain the two ways a log fails (a step rejects;
the log ends mid-chain, leaving a non-final `InFlight` carrier). Also note in the
module haddock that π₂'s step is now `applyEventStreaming`, not `applyEvent`, and
update the `Acceptor` type's haddock reference (line 68) accordingly. `inputAcceptor`
is untouched.

Extend `test/Keiki/AcceptorSpec.hs`: (a) the multi-event acceptance spec this plan's
acceptance names — `accepts (outputAcceptor userReg) canonicalLog` is `True` for the
five-event `userReg` log (reproduce the log in the spec; before this milestone the
same assertion is `False`, which is the review's broken equivalence — verify once
against the pre-M4 code, then land); (b) truncation: `take 1 canonicalLog` is
rejected, and `runAcceptor` returns `Just` with an `InFlight` carrier for it (rejection
comes from `aIsFinal`, not a step failure); (c) update the "agrees with reconstitute"
spec (lines 83-85): the carrier is now the wrapper, so compare
`accepts (outputAcceptor t) log` against
`maybe False (isFinal t . fst) (reconstitute t log)` on the letter-only
`emailDelivery` log, the multi-event `userReg` log, the
truncated log, and a foreign-event log — four rows of the (now true) equivalence; (d)
keep the existing rejection case at lines 73-81, updating only its carrier plumbing if
needed.

Acceptance: `cabal test all` green; spec (a) fails before the M4 edit and passes after.

### Milestone 5 — documentation honesty, changelog, final sweep

Scope: close defect 5, present the Either surface as primary everywhere, and sweep.

In `src/Keiki/Core.hs`, extend `omega`'s haddock (lines 883-895): it already mentions
the caller cannot distinguish "no active edge" from "active ε-edge"; strengthen it to
name all three conflated outcomes (rejected, ambiguous, accepted-ε), state plainly
that `[] :: [co]` must never be interpreted as "command rejected", and point at
`stepEither` as the verb that distinguishes them. Confirm `reconstitute`,
`applyEvents`, and `applyEventStreaming` haddocks each open by naming their `Either`
counterpart as the primary documented surface (done incrementally in M1/M2; verify).
Add a `CHANGELOG.md` entry under the `0.1.0.0` heading covering: new
`ReplayStepFailure`/`ReplayFailureReason`/`ReplayFailure` types;
`applyEventStreamingEither`, `replayEvents`, `applyEventsEither`,
`reconstituteEither`; BREAKING: `Keiki.Decider` has been removed; BREAKING:
`outputAcceptor`'s state carrier is now
`(InFlight s co, RegFile rs)`. Run the full sweep (Concrete Steps) and
`nix fmt -- --no-cache`; update this plan's Progress, Surprises & Discoveries, and
Outcomes & Retrospective.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki` (shown
here as `.`), inside the dev shell.

```bash
cd /Users/shinzui/Keikaku/bokuno/keiki
nix develop            # GHC 9.12 toolchain; subsequent commands assume this shell
cabal build all        # after each milestone's edits
cabal test all         # full suite; new + existing specs
nix fmt -- --no-cache  # canonical fourmolu formatting before every commit
```

Expected test transcript shape (module counts will differ; the point is zero
failures and the presence of the new spec groups):

```text
Keiki.ReplayEitherSpec
  applyEventStreamingEither
    reports ReplayNoInvertingEdge with one summary per outgoing edge [✔]
    reports ReplayQueueMismatch with the observed event and expected queue [✔]
    reports ReplayAmbiguousInversions listing both matched edges [✔]
  reconstituteEither
    names index 1 and the queue mismatch on the corrupted canonical log [✔]
    reports ReplayLogTruncated for a log ending mid-chain [✔]
  replayEvents
    resumes from a mid-chain InFlight seed [✔]
    returns a final InFlight wrapper without failing [✔]
...
N examples, 0 failures
```

Files touched, for orientation: `src/Keiki/Core.hs` (types, four functions, three
re-expressed wrappers, export list, haddocks), `src/Keiki/Decider.hs` (removed),
`src/Keiki/Acceptor.hs` (`outputAcceptor`, haddocks),
`test/Keiki/ReplayEitherSpec.hs` (new), `test/Keiki/DeciderSpec.hs` (removed after
useful assertions migrate),
`test/Keiki/AcceptorSpec.hs`, `test/Spec.hs`, `keiki.cabal` (test `other-modules`),
`CHANGELOG.md`, and this plan. Commit per milestone with conventional-commit messages,
e.g.:

```text
feat(core): structured replay failures and applyEventStreamingEither (EP-72 M1)
feat(core): replayEvents fold, applyEventsEither, reconstituteEither (EP-72 M2)
refactor(api)!: remove the lossy Decider facade (EP-72 M3)
fix(acceptor)!: InFlight-aware outputAcceptor restores reconstitute equivalence (EP-72 M4)
docs(core): omega conflation warnings; Either replay surface is primary (EP-72 M5)
```


## Validation and Acceptance

Beyond compilation, acceptance is the following observable behaviors, each encoded as
a `shouldBe` in the named spec. `t n` below is the shared test time fixture
`UTCTime (fromGregorian 2026 5 1) (secondsToDiffTime n)`.

First, a corrupted log names the exact failing index and reason. In
`test/Keiki/ReplayEitherSpec.hs`, corrupt index 1 of the canonical `userReg` log by
replacing `ConfirmationEmailSent` with a foreign `AccountDeleted`; then:

```haskell
reconstituteEither userReg corruptedLog
  `shouldBe` Left
    ReplayFailure
      { replayFailedIndex = 1,
        replayFailedState =
          InFlight
            RequiresConfirmation
            [ConfirmationEmailSent (ConfirmationEmailSentData "alice@x")],
        replayFailureReason =
          ReplayEventFailed
            ( ReplayQueueMismatch
                RequiresConfirmation
                (AccountDeleted (AccountDeletedData "alice@x" (t 999)))
                [ConfirmationEmailSent (ConfirmationEmailSentData "alice@x")]
            )
      }
```

A foreign event at a settled vertex names the vertex and every candidate edge
(`PotentialCustomer` has exactly one outgoing edge, targeting `RequiresConfirmation`):

```haskell
reconstituteEither userReg [AccountConfirmed (AccountConfirmedData "alice@x" "Z9F4" (t 0))]
  `shouldBe` Left
    ReplayFailure
      { replayFailedIndex = 0,
        replayFailedState = Settled PotentialCustomer,
        replayFailureReason =
          ReplayEventFailed
            ( ReplayNoInvertingEdge
                PotentialCustomer
                [ RejectedEdgeSummary
                    { rejectedEdge = EdgeRef {edgeSource = PotentialCustomer, edgeIndex = 0},
                      rejectedTarget = RequiresConfirmation,
                      rejectedGuard = False
                    }
                ]
            )
      }
```

Second, a truncated multi-event chain is reported as such (index = log length,
pending queue carried):

```haskell
reconstituteEither userReg (take 1 canonicalLog)
  `shouldBe` Left
    ReplayFailure
      { replayFailedIndex = 1,
        replayFailedState =
          InFlight
            RequiresConfirmation
            [ConfirmationEmailSent (ConfirmationEmailSentData "alice@x")],
        replayFailureReason =
          ReplayLogTruncated
            [ConfirmationEmailSent (ConfirmationEmailSentData "alice@x")]
      }
```

Third, the lossy facade is gone: `Keiki.Decider` is absent from cabal exposure,
source, tests, and public documentation. The multi-event tail-loss example that
motivated removal remains as a Core replay regression, and canonical chunk replay
still lands on `(Deleted, expectedSnapshot)`.

Fourth, the acceptor/reconstitute equivalence passes on a multi-event fixture
(`test/Keiki/AcceptorSpec.hs`): `accepts (outputAcceptor userReg) canonicalLog ==
True` (this exact assertion is `False` before M4 — run it once against the pre-M4
tree to capture the failing-before evidence), `accepts (outputAcceptor userReg)
(take 1 canonicalLog) == False`, and for all four log rows (letter-only, multi-event,
truncated, foreign) the equivalence
`accepts (outputAcceptor t) log == maybe False (isFinal t . fst) (reconstitute t log)`
holds.

Fifth, nothing load-bearing moved: the untouched `test/Keiki/CoreApplyEventsSpec.hs`,
`test/Keiki/CoreInFlightSpec.hs`, and `test/Keiki/NoThunksSpec.hs` pass unmodified,
proving `applyEvents`/`applyEventStreaming`/`reconstitute` kept their exact semantics
as thin wrappers. Final gate: from the repo root, `nix develop` then `cabal build all`,
`cabal test all` (zero failures), `nix fmt -- --no-cache` (no diff on a clean tree).


## Idempotence and Recovery

Every step is an ordinary source edit plus a test run; all are safe to repeat. The
plan is additive-first: M1/M2 only add API (the `Maybe` wrappers are re-expressed but
observationally identical, guarded by existing suites), so if anything goes wrong
mid-milestone, revert the incomplete source edit before continuing. The two breaking edits
(M3's module removal, M4's `outputAcceptor` carrier) are isolated milestones; current
keiro does not import either changed surface. If either milestone must be abandoned mid-way, reverting just
that milestone's commit restores a releasable state because milestones are committed
separately and each leaves the suite green. Re-running `cabal test all` and
`nix fmt -- --no-cache` is always safe. No migrations, no persisted data, no
destructive operations are involved.


## Interfaces and Dependencies

No new package dependencies; everything uses the existing `base`/Hspec toolchain. All
additions live in `Keiki.Core` (module `src/Keiki/Core.hs`) except the acceptor edit;
`Keiki.Decider` no longer exists. At the end of the plan these signatures exist
exactly as written:

```haskell
-- src/Keiki/Core.hs — new vocabulary (all deriving stock (Eq, Show))

-- | Why one observed event could not be replayed. Mirrors 'StepFailure';
-- carries NO register values. Events (@co@) are carried where they
-- identify the failure — the log is already observable data.
data ReplayStepFailure s co
  = -- | At @'Settled' s@: no outgoing edge's head output inverted the
    -- observed event with a satisfied guard. One summary per outgoing
    -- edge in declaration order; empty iff the vertex has no outgoing
    -- edges. 'rejectedGuard' is always 'False' (same posture as
    -- 'NoMatchingEdge').
    ReplayNoInvertingEdge s [RejectedEdgeSummary s]
  | -- | At @'Settled' s@: two or more edges inverted the event — a
    -- runtime witness of a single-valuedness violation on the inverse.
    ReplayAmbiguousInversions s [MatchedEdgeSummary s]
  | -- | At @'InFlight' s queue@: the observed event (second field) did
    -- not equal the head of the expected queue (third field, in full).
    ReplayQueueMismatch s co [co]

data ReplayFailureReason s co
  = ReplayEventFailed (ReplayStepFailure s co)
  | -- | The log ended while mid-chain; carries the pending expected events.
    ReplayLogTruncated [co]

data ReplayFailure s co = ReplayFailure
  { -- | Zero-based index of the offending event in the input log; for
    -- 'ReplayLogTruncated', the log's length (where the next event was due).
    replayFailedIndex :: Int,
    -- | Wrapper state at the moment of failure (before the failing event).
    replayFailedState :: InFlight s co,
    replayFailureReason :: ReplayFailureReason s co
  }

-- src/Keiki/Core.hs — new functions

applyEventStreamingEither ::
  (BoolAlg phi (RegFile rs, ci), Eq co) =>
  SymTransducer phi rs s ci co ->
  InFlight s co ->
  RegFile rs ->
  co ->
  Either (ReplayStepFailure s co) (InFlight s co, RegFile rs)

-- | Strict left fold from an arbitrary seed. Never fails on a log that
-- ends mid-chain: the final wrapper is returned on the Right and the
-- caller decides (see 'applyEventsEither' for the strict facade).
replayEvents ::
  (BoolAlg phi (RegFile rs, ci), Eq co) =>
  SymTransducer phi rs s ci co ->
  (InFlight s co, RegFile rs) ->
  [co] ->
  Either (ReplayFailure s co) (InFlight s co, RegFile rs)

applyEventsEither ::
  (BoolAlg phi (RegFile rs, ci), Eq co) =>
  SymTransducer phi rs s ci co ->
  (s, RegFile rs) ->
  [co] ->
  Either (ReplayFailure s co) (s, RegFile rs)

reconstituteEither ::
  (BoolAlg phi (RegFile rs, ci), Eq co) =>
  SymTransducer phi rs s ci co ->
  [co] ->
  Either (ReplayFailure s co) (s, RegFile rs)
```

The existing `applyEventStreaming`, `applyEvents`, and `reconstitute` keep their
current signatures verbatim and are defined as `either (const Nothing) Just . <Either
variant>`. `Keiki.Decider` is removed, and `Keiki.Acceptor.outputAcceptor` becomes
`SymTransducer phi rs s ci co -> Acceptor co (InFlight s co, RegFile rs)` (the
`Acceptor` type itself is unchanged). Downstream coordination: plan 73 consumes
`ReplayFailure`'s `Show` instance in counterexample rendering; plan 71 shares
`EdgeRef`; keiro's future migration consumes `replayEvents` +
`replayFailedIndex`-based version arithmetic (out of scope here, designed for above).

---

Revision note (2026-07-12): surgically replaced the proposed `Maybe` redesign of
`Decider.evolve` with removal of the entire `Keiki.Decider` interface. The Core replay
and Acceptor work is otherwise unchanged. Compatibility was checked against current
keiro, which uses Core replay directly.

Revision note (2026-07-11): initial authoring — replaced the generated skeleton with
the full plan. Sources: the master plan's Phase 2 scope and Decision Log (policy
restated verbatim in intent), direct verification of `src/Keiki/Core.hs`,
`src/Keiki/Decider.hs`, `src/Keiki/Acceptor.hs`, `test/Keiki/DeciderSpec.hs`,
`test/Keiki/AcceptorSpec.hs`, `test/Keiki/Fixtures/UserRegistration.hs`, and the keiro
prior art in `keiro/src/Keiro/Command.hs` (sibling repository).
