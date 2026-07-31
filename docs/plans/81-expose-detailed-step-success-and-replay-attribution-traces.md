---
id: 81
slug: expose-detailed-step-success-and-replay-attribution-traces
title: "Expose detailed step success and replay attribution traces"
kind: exec-plan
created_at: 2026-07-31T20:29:39Z
---

# Expose detailed step success and replay attribution traces

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

After this change, a caller can ask Keiki not only whether a command or event log succeeds, but
which concrete declared edge Keiki selected. A detailed forward step returns the selected local
`EdgeRef`, its `Live` mode, and the same state, register file, and output word that `stepEither`
already returns. A detailed strict replay returns the same settled state and register file that
`applyEventsEither` returns plus an ordered trace that factors the complete observed event list
into the non-empty output word consumed by each selected `Live` or `ReplayOnly` edge.

This is evidence about Keiki's existing evaluator, not a second evaluator. The old entry points
retain their signatures and exact successes and failures by erasing the new detail. Users can see
the feature work in focused Hspec examples: two behaviorally indistinguishable guarded siblings
report different `EdgeRef`s; live-first replay reports the live edge rather than its replay-only
twin; and a two-event edge followed by a one-event edge reports spans `[0,2)` and `[2,3)` while
returning the same final state as `applyEventsEither`.

Existing replay callers do not pay to build a trace they discard. The common private replay fold
has a no-trace mode with O(1) auxiliary state and a collecting mode with O(number of completed
edges) trace storage. `replayEvents`, `applyEventsEither`, and `reconstituteEither` use the former;
only callers that opt into detailed replay use the latter. Forward `stepEither` keeps the simpler
record-erasure implementation because its one short-lived success record is constant-size and not
an asymptotic cost.

The existing `jitsurei:keiki-bench` tasty-bench suite supplies before/after performance evidence.
Before changing Core, it gains compatibility rows for `stepEither` and strict replay over both the
existing 32-event log and a 1,024-event log, and captures a CSV baseline with allocation statistics.
After implementation, the same rows are compared against that file and new opt-in detailed rows
measure the real trace cost by strictly consuming a metadata checksum. The benchmark complements,
but does not replace, the semantic laws and the static no-trace call-graph gate.

This is one ExecPlan rather than a MasterPlan. The work has one implementation authority in
`src/Keiki/Core.hs`, one public API surface, and one release. Splitting forward and replay detail
into independent plans would force both plans to edit the same evaluator and compatibility laws,
while the completed architecture-hardening MasterPlan 16 is historical context rather than an
active parent initiative.


## Progress

- [ ] Milestone 0: extend the existing tasty-bench suite with compatibility probes and capture the
  pre-refactor timing/allocation baseline.
- [ ] Milestone 1: add the public detailed-forward result and make `stepEither` erase it.
- [ ] Milestone 2: factor replay through one internal kernel with allocation-free no-trace and
  trace-collecting modes, then add strict detailed replay entry points.
- [ ] Milestone 3: add example and property coverage for edge identity, trace laws, exact erasure,
  live-first selection, epsilon observability, and unchanged failures; add detailed benchmark rows
  and compare compatibility performance with the Milestone 0 baseline.
- [ ] Milestone 4: update Haddocks, user/foundation documentation, ADR-0002, the changelog, and
  improvement-request and benchmark documentation.
- [ ] Milestone 5: pass focused, benchmark, full-project, Haddock, Nix, OKF, and diff gates.
- [ ] Milestone 6: reconcile release authority, publish the additive release through the repository
  release workflow, and record the final tag/version evidence.


## Surprises & Discoveries

- The package registry and Git release authorities are temporarily out of sync. On 2026-07-31,
  Hackage's `preferred.json` lists `0.6.0.0`, but `git ls-remote --tags origin` exposes tags only
  through `v0.5.0.0`. A local annotated `v0.6.0.0` tag points to
  `c8f2c343ce03f42e10de77d684769f15ad30feda` but is not public. Release work must not treat that
  local tag as authoritative.

- `RegFile rs` intentionally has no whole-value `Eq` or `Show` instance. Exact compatibility tests
  must compare state, outputs, and fixture-specific per-slot observations rather than compare a
  complete `Either` success value.

- The public `InFlight s co` wrapper remembers only the target state and pending evaluated output
  tail. It deliberately forgets the edge selected by the head event. Detailed strict replay must
  carry private pending attribution alongside `InFlight`; it cannot reconstruct attribution from
  the target after the tail finishes.

- Making `applyEventsEither` call the collecting detailed operation and then erase its trace would
  be observably compatible but operationally wrong for long hydrations. It would change auxiliary
  memory from O(1) to O(number of completed edges) and retain one record plus one list cell per
  edge until replay finishes. The shared worker is therefore an asymptotic safeguard, not a
  speculative micro-optimization.

- Keiki already has the appropriate performance harness at `jitsurei/bench/Bench.hs`, registered
  as `jitsurei:keiki-bench`. It uses tasty-bench, enables `-fproc-alignment=64`, supports CSV
  baselines, and reports allocated/copied/peak-memory columns when run with `+RTS -T`. A second
  benchmark executable or dependency would duplicate established machinery.

- The existing suite mostly uses `whnf`. That is insufficient for a `ReplaySuccess` on its own:
  reaching the outer `Right` and record constructor need not force the ordered trace or its
  metadata. A detailed replay benchmark must reduce the trace to a strict scalar, or it can report
  an unrealistically small cost because of laziness.


## Decision Log

- Decision: Implement this request as standalone ExecPlan 81, not a new MasterPlan and not a child
  of completed MasterPlan 16.
  Rationale: one Core refactor, one law suite, and one release form a single coherent delivery. No
  independently useful subplan or cross-team integration needs a separate progress registry.
  Date: 2026-07-31

- Decision: Expose `StepSuccess`, `ReplayEventSpan`, `ReplayAttribution`, and `ReplaySuccess`, with
  `stepDetailedEither`, `applyEventsDetailedEither`, and `reconstituteDetailedEither` as the public
  operations.
  Rationale: these names follow the existing convention that `Either` is the final operation
  suffix, keep result records explicit despite `RegFile` lacking `Eq`, and provide both seedable and
  initial-state strict replay without exposing internal cursors.
  Date: 2026-07-31

- Decision: Put `EdgeMode` directly in both detailed success records even though a forward success
  is always `Live`.
  Rationale: direct evidence cannot be invalidated by accidentally resolving an `EdgeRef` against a
  different transducer, and downstream conformance can assert the execution phase without
  re-enumerating edges. Tests still verify that every record agrees with the edge at its local
  `EdgeRef`.
  Date: 2026-07-31

- Decision: Make `stepDetailedEither` the forward selection/evaluation authority and express
  `stepEither` by erasing its `Right`; do not select the edge twice or change `step` in this plan.
  Rationale: the requested compatibility law concerns `stepEither`, while changing the older
  `step`/`delta`/`omega` relationship would broaden the task. One authority makes disagreement
  structurally difficult and property tests make it observable.
  Date: 2026-07-31

- Decision: Add one private replay kernel and list fold parameterized by `DiscardTrace` or
  `CollectTrace`. The discard state is nullary and never constructs `PendingAttribution`,
  `ReplayAttribution`, or a trace list. The collecting state carries pending attribution only after
  a head event selects a multi-event edge and appends a public entry only when the queue empties.
  Rationale: attribution happens at the head, completion happens at the tail, and the public
  `InFlight` type cannot remember the former. The shared kernel preserves evaluation and failure
  authority, while separate result policies keep compatibility replay at O(1) auxiliary memory.
  Date: 2026-07-31

- Decision: Compatibility replay calls the shared worker directly in `DiscardTrace` mode; it does
  not call a detailed public operation and erase a fully built trace.
  Rationale: the erasure law is observational, not a requirement to allocate the richer value.
  Calling the common worker satisfies the no-drift requirement without an O(number of edges)
  allocation and retention penalty.
  Date: 2026-07-31

- Decision: Keep `stepEither` as erasure of `stepDetailedEither` for the first implementation. Do
  not add a continuation-style forward worker unless measurement shows the constant-size record
  allocation survives optimization and matters.
  Rationale: forward stepping creates at most one short-lived detailed record per accepted
  command, whereas discarded replay traces accumulate with log length. The extra forward worker
  would add complexity to avoid a small, likely optimized constant cost.
  Date: 2026-07-31

- Decision: Reuse and extend `jitsurei:keiki-bench`; do not create a new executable or change the
  existing tasty-bench dependency bound.
  Rationale: the checked-in harness already covers builder and AST transducers, has baseline and
  allocation-reporting instructions, and uses the alignment option recommended for meaningful
  comparisons. Mori locates the dependency source as
  `mori://Bodigrim/tasty-bench/packages/tasty-bench`.
  Date: 2026-07-31

- Decision: Add compatibility-only benchmark rows and capture their CSV before editing Core, then
  add the detailed rows after the API exists. Use both the established 32-event UserRegistration
  log and a valid 1,024-event variant containing 1,020 `ConfirmationResent` self-loop events.
  Rationale: a before/after baseline can detect constant forward overhead and compatibility replay
  regressions, while the two replay lengths expose a trace-sized allocation slope that a short log
  can hide. The long fixture remains realistic transducer execution and does not require a toy
  performance-only evaluator.
  Date: 2026-07-31

- Decision: Benchmark strict scalar projections, not merely the outer detailed result. The
  compatibility projection forces successful completion; the detailed projection additionally
  folds every span, count, edge index, and mode into an `Int` checksum. Use `nf` on that scalar.
  Rationale: an `Int` has no hidden unevaluated structure, so the detailed row includes ordered
  trace production and consumption without requiring an `NFData` instance for `RegFile`. The
  checksum must depend on all attribution entries so GHC cannot omit the work being measured.
  Date: 2026-07-31

- Decision: Treat tasty-bench results as comparative evidence. A repeatable compatibility slowdown
  over 20% triggers investigation, and a positive allocation delta that grows with event count
  blocks completion until it is shown not to be discarded attribution. Do not gate the opt-in
  detailed/compatibility ratio.
  Rationale: tasty-bench itself describes its statistics as indicative and comparative; timing can
  be noisy, while same-build allocation deltas and the 32-versus-1,024 slope are stronger evidence
  for accidental trace construction. The nullary discard state and call graph remain the hard
  architectural guarantee.
  Date: 2026-07-31

- Decision: Keep detailed replay strict and settled-to-settled. Do not add a public streaming trace
  cursor in this plan.
  Rationale: a caller resuming from a bare public `InFlight` seed does not possess the prior edge or
  head index, so it cannot receive a complete attribution entry without a new resumable cursor
  contract. The requesting Keiro witness consumes complete typed chunks and needs only the strict
  surface.
  Date: 2026-07-31

- Decision: Replay traces contain no epsilon-output entries and satisfy both an empty-input law and
  a non-empty contiguous-partition law.
  Rationale: an event log contains no evidence that distinguishes zero, one, or many silent
  transitions. For every observed event, however, strict replay attributes it to exactly one
  completed non-empty output word; spans therefore partition `[0,n)` and form a state path.
  Date: 2026-07-31

- Decision: Preserve `EdgeRef` as a construction-local locator and do not promote it to a persisted
  semantic identifier.
  Rationale: `EdgeRef` is the source vertex plus the ordinal in `edgesOut t source`; declaration
  order changes that ordinal. Keiro owns stable semantic fingerprints and may map them to current
  local refs when generating a transducer.
  Date: 2026-07-31

- Decision: Extend `docs/adr/0002-event-logs-must-reproduce-forward-state.md` instead of creating a
  new ADR unless implementation reveals a genuinely separate durable choice.
  Rationale: detailed replay is an observational refinement of the replay contract already owned by
  ADR-0002. Its trace-factorization and erasure laws belong with that contract.
  Date: 2026-07-31

- Decision: Treat release as incomplete until Hackage and public upstream evidence agree.
  Rationale: the validated improvement request explicitly rejects local-only tags as release
  authority. The anticipated additive version is `0.6.1.0` if `0.6.0.0` remains Hackage-current,
  but the release workflow must recompute the version after refreshing both authorities.
  Date: 2026-07-31


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Keiki models an event-sourced aggregate as a symbolic extended finite-state transducer. A
transducer has a finite control vertex `s`, a typed heterogeneous register file `RegFile rs`, and
outgoing `Edge`s. An edge checks a guard against `(registers, command)`, applies a register update,
moves to a target vertex, and emits a list of typed output events. That list is the edge's output
word: `[]` is an epsilon (unobservable) output, a singleton is a one-event edge, and a longer list
is one generalized sequential machine transition that emits several events in order.

The public definitions live in `src/Keiki/Core.hs`. `EdgeMode` is `Live` or `ReplayOnly`. Forward
execution may select only `Live`; replay first searches all matching `Live` edges and searches
`ReplayOnly` only if the live phase has no match. `EdgeRef s` identifies one edge within one
concrete transducer construction by its source vertex and zero-based position in
`edgesOut t source`. It is suitable for diagnostics and runtime attribution, but not for
persistence.

`stepEither` currently enumerates outgoing edges, filters to matching live guards, constructs
`StepFailure` on zero or multiple matches, and on one match evaluates the update and output word.
Its `Right` is only `(s, RegFile rs, [co])`, so it loses the index already present during
selection. `step` is an older compatibility entry point built from `delta` and `omega`; this plan
leaves its signature and behavior alone.

Replay starts at a public wrapper `Settled s` or `InFlight s pendingEvents`. At `Settled`,
`applyEventStreamingEither` inverts the first output term of each outgoing edge, verifies the
recovered command against the guard, applies the selected update, and evaluates the remaining
output terms. A singleton edge returns `Settled target`; a multi-event edge returns
`InFlight target evaluatedTail`. At `InFlight`, each observed event is equality-checked against
the pending head until the queue empties. The current wrapper does not retain the selected edge.

`replayEvents` folds that streaming operation from an arbitrary public wrapper and reports
`ReplayFailure` with the zero-based event index and wrapper immediately before failure.
`applyEventsEither` starts from `Settled`, requires the final wrapper to be `Settled`, and turns a
remaining queue into `ReplayLogTruncated`. `reconstituteEither` supplies the transducer's initial
state and registers. The `Maybe` variants erase structured failures. Their current semantics are
the compatibility baseline and must not change.

Replay is a hot hydration path: a runtime may consume hundreds of thousands or millions of stored
events before serving a command. The current fold retains only the public wrapper, register file,
event index, and remaining input list; excluding the caller-owned input and evaluator data, its
auxiliary state is O(1). A detailed trace necessarily retains O(k) metadata for `k` completed
edges, but that cost must remain opt-in. The implementation therefore shares semantic work, not
the detailed accumulator, between compatibility and detailed calls.

The approved request is
`docs/improvement-requests/expose-successful-edge-attribution-for-forward-stepping-and-structured-replay.md`.
Its downstream purpose is the finite-witness conformance work in
`mori://shinzui/keiro/plans/159-generate-complete-reachable-state-holes-and-spec-behavioral-conformance`.
Keiro needs the edge Keiki actually selected; it must not duplicate guards or infer a replay-only
edge merely because replay reached the expected target.

The relevant tests are `test/Keiki/StepEitherSpec.hs` for structured forward failures,
`test/Keiki/ReplayEitherSpec.hs` for exact replay failures and strict truncation,
`test/Keiki/CoreInFlightSpec.hs` for multi-event queue behavior,
`test/Keiki/ReplayOnlySpec.hs` for live-first selection, and `test/Keiki/RoundTrip.hs` plus
`test/Keiki/RoundTripSpec.hs` for generated forward/replay agreement over real fixtures. The test
suite is registered in `keiki.cabal` and assembled by `test/Spec.hs`. `RegFile` has no whole-value
equality, so `RoundTripFixture.rtObserve` is the established per-slot observation seam.

Performance coverage lives in `jitsurei/bench/Bench.hs`, with operating notes in
`jitsurei/bench/README.md` and the `keiki-bench` stanza in `jitsurei/jitsurei.cabal`. The existing
suite benchmarks builder and AST forms of UserRegistration and OrderCart and already has
length-32 replay logs. Its tasty-bench dependency is registered by Mori as
`mori://Bodigrim/tasty-bench/packages/tasty-bench`. With `+RTS -T`, its CSV contains time,
allocated bytes, copied bytes, and peak memory. Baseline comparison consumes the timing columns;
the before/after allocation columns must also be inspected directly.

Two ADRs are relevant. `docs/adr/0001-structural-re-indexing-for-sound-replay.md` explains why
output inversion recovers a command through structurally aligned `InCtor` and `OutTerm` schemas;
the detailed trace must report the edge selected by that existing inversion, not create a second
inverse. `docs/adr/0002-event-logs-must-reproduce-forward-state.md` requires a validated
transducer's complete emitted log to rebuild the forward state and establishes the structured,
`InFlight`-aware replay APIs. This plan adds proof-relevant success information while preserving
that theorem and its failure vocabulary. No other ADR currently governs runtime edge attribution.

The completed
`docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md`
and its plans 71–73 explain the origin of the replay validator, structured failures, and permanent
round-trip harness. They are prior art, not an active parent. This plan must preserve their tests.

As of plan creation, `keiki.cabal` and `CHANGELOG.md` identify `0.6.0.0`, and Hackage serves that
version. The checked-out branch is ahead of public `origin/master`; the public tag set lacks
`v0.6.0.0`. This discrepancy is a release precondition, not permission to push or rewrite tags
without the normal release workflow.


## Plan of Work

### Milestone 0 — establish the compatibility performance baseline

Before editing `src/Keiki/Core.hs`, extend `jitsurei/bench/Bench.hs` rather than adding a new
benchmark target. Import `stepEither`, `applyEventsEither`, and `nf`. Add fully saturated,
`NOINLINE` benchmark projections that return a strict `Int`: the forward compatibility projection
must force a `stepEither` success and its output-list spine, and the replay compatibility projection
must force `applyEventsEither` to reach `Right`. Do not benchmark fixture construction.

Add a valid `urLongLog` of exactly 1,024 events: `RegistrationStarted`,
`ConfirmationEmailSent`, 1,020 sequential `ConfirmationResent` events, `AccountConfirmed` with the
last rotated code, and `AccountDeleted`. Retain `urLog` as the 32-event case. Add named
compatibility rows for builder and AST `stepEither`, and for builder and AST
`applyEventsEither` at both replay lengths. Keep benchmark paths stable after capture because
tasty-bench matches a later run to the CSV by full benchmark name.

Run the suite with `--csv` and `+RTS -T` before the Core refactor and keep the untracked baseline at
`/tmp/keiki-ep81-before.csv`. Record the GHC version, benchmark commit/worktree identity, command,
and compatibility rows in this plan's Progress or Outcomes. Confirm the CSV has `Allocated`,
`Copied`, and `Peak Memory` columns. Do not commit a developer-machine baseline or turn a single
timing run into a universal threshold.

Update `jitsurei/bench/README.md` enough to name the new compatibility rows and explain that they
are the pre-change probes for ExecPlan 81. Defer descriptions of the not-yet-existing detailed rows
until Milestone 3. Milestone 0 is complete only when the compatibility benchmark source compiles,
the CSV exists, and Core is still at its pre-refactor implementation.

### Milestone 1 — detailed forward success with one evaluator

In `src/Keiki/Core.hs`, add and export `StepSuccess` near `EdgeRef`. It contains the exact selected
`EdgeRef`, `EdgeMode`, resulting state, resulting `RegFile`, and ordered outputs. Add
`stepDetailedEither` with the same constraints and inputs as `stepEither`. Move the current indexed
edge selection, failure construction, update, and output evaluation into this function. On the
single match, retain its index and return `StepSuccess` with `Live`; do not re-enumerate the edge or
look it up after evaluating.

Replace `stepEither`'s body with erasure of `stepDetailedEither`: the `Left` passes through
unchanged, and a `Right StepSuccess` becomes the historical triple. Keep `step`, `delta`, `omega`,
all failure constructors, rejection summary order, and the inclusion of replay-only edges in
`NoMatchingEdge` summaries unchanged.

Keep this forward structure simple initially. The detailed record is constant-size and exists only
on an accepted command. Add an `INLINE` pragma only if it follows existing Core practice and the
compiler accepts it cleanly; do not introduce a second generic success-builder abstraction without
measurement showing a real forward allocation regression.

Extend `test/Keiki/StepEitherSpec.hs`. Retain all existing exact failure tests. Add a compact
fixture with two input constructors whose disjoint `PInCtor` guards lead to the same target, keep
the same empty register file, and emit equal event values through distinct edges. Separate inputs
must return `EdgeRef source 0` and `EdgeRef source 1` while their erased results are identical. Add
an accepted epsilon-output case and a replay-only-only case. At the end of this milestone, focused
step tests compile and show that `stepEither` and `stepDetailedEither` cannot disagree without the
single detailed implementation being wrong.

### Milestone 2 — completed replay attribution with one replay fold

In `src/Keiki/Core.hs`, add and export `ReplayEventSpan`, `ReplayAttribution`, and `ReplaySuccess`
near the replay failure types. Spans are zero-based and half-open. `ReplayAttribution` repeats its
event count deliberately so tests and consumers can check that `end - start`, event count, and the
selected edge's declared output-word length agree. Result types containing `RegFile` do not derive
`Eq` or `Show`; the span and attribution metadata do derive them.

Add private replay state that pairs the public `InFlight` wrapper with optional pending
attribution. A pending record contains the selected `EdgeRef`, selected phase/mode, settled source,
declared target, head index, and declared output count. It is created in the same branch where the
head event uniquely selects `(index, edge, recoveredCommand)`. A singleton edge completes an
attribution at once with `[i,i+1)`. A multi-event edge keeps the pending record while the existing
evaluated queue is consumed and appends one public attribution only when the last tail event makes
the wrapper `Settled`. Do not create a record for an edge whose output word is empty because replay
never selects such an edge.

Factor the event application and list fold so they remain the only authorities for inversion,
guard checking, update application, evaluated-tail construction, queue equality, failure index,
and failure wrapper. Parameterize only trace accumulation through a private state with two
constructors. `DiscardTrace` contains no pending record and no list. `CollectTrace` contains the
optional pending record and a strict reverse trace accumulator. Pattern-match on that state at the
point where an attribution would start or complete; the discard branch must return the same
nullary constructor without constructing attribution metadata.

`applyEventStreamingEither`, `replayEvents`, `applyEventsEither`, and `reconstituteEither` call the
shared internal machinery in `DiscardTrace` mode and return their current public shapes directly.
They do not call `applyEventsDetailedEither`. `applyEventsDetailedEither` uses `CollectTrace`,
rejects a final `InFlight` with the existing `ReplayLogTruncated` value, reverses the completed
trace once at successful settlement, and returns `ReplaySuccess`. `reconstituteDetailedEither`
supplies the initial seed and uses the same collecting path. The `Maybe` wrappers continue to
delegate to the same compatibility `Either` functions.

This design preserves a single semantic worker but two operational result policies. The
compatibility policy has O(1) auxiliary state with respect to event/edge count; the detailed policy
has O(k) retained trace storage for `k` completed edges, which is the explicit price of requesting
the trace. A single mode branch per replay advance is acceptable. Do not retain a dormant empty
list or a `Maybe PendingAttribution` in `DiscardTrace`, and do not build then discard entries.

The private cursor must also handle `replayEvents` starting from an arbitrary public `InFlight`
whose original selection metadata is unavailable. In discard mode, pending attribution is absent
and tail comparison proceeds exactly as today. Do not expose an incomplete or fabricated trace for
that case. At the end of this milestone, all pre-existing replay tests pass and new fixed examples
show one attribution per completed edge. Inspect the Core diff before leaving the milestone and
confirm every compatibility function seeds `DiscardTrace`, while only the two detailed functions
seed `CollectTrace`.

### Milestone 3 — executable laws and adversarial examples

Extend `test/Keiki/CoreInFlightSpec.hs` with a transducer that takes one two-event edge followed by
one one-event edge. `applyEventsDetailedEither` over three events must return two entries with
spans `[0,2)` and `[2,3)`, counts `2` and `1`, adjacent source/target states, and final state equal
to `applyEventsEither`. An empty event list must return the seed and an empty trace. A head-only
chunk must return exactly the same truncation failure as `applyEventsEither`, so no partial trace
escapes on `Right`.

Extend `test/Keiki/ReplayOnlySpec.hs` at the existing overlap fixture. When both a live edge and its
replay-only twin can invert an event, detailed replay must report the live edge and `Live`. When the
live guard cannot attribute historical input, the trace must report the twin's exact `EdgeRef` and
`ReplayOnly`. Retain the existing register-observation assertions so the test proves the detailed
phase matches the evaluator's actual update, not just a label.

Extend `test/Keiki/ReplayEitherSpec.hs` with paired detailed/compatibility calls for no inversion,
ambiguous inversion, queue mismatch, and truncation. Pattern-match or compare the `Left` values
directly; each detailed failure must equal the current compatibility failure in index, wrapper,
and reason.

Add a compatibility-path regression that replays a long synthetic list successfully through
`applyEventsEither` and `reconstituteEither`, then the same list through the detailed operation.
The behavioral assertions remain exact, but the operational guarantee is enforced primarily by
the private state shape and call graph: the compatibility calls must select the nullary
`DiscardTrace` branch, and only the detailed call may construct `CollectTrace` and public entries.
Do not add a timing threshold to Hspec; wall-clock thresholds are noisy and would not prove the
O(1) auxiliary-memory property.

Then finish the benchmark extension in `jitsurei/bench/Bench.hs`. Add strict scalar projections for
`stepDetailedEither` and `applyEventsDetailedEither`. The forward digest consumes the selected
edge index, mode, and output-list length. The replay digest uses `Data.List.foldl'` to consume every
trace entry's edge index, mode, span start, span end, and event count; it also distinguishes `Left`
from `Right`. Benchmark the detailed forward call beside its matching compatibility row and
detailed replay for both builder and AST over 32 and 1,024 events. Use `bcompare` only to display
the opt-in detailed/compatibility ratio in the same run; document that this ratio includes the
deliberate cost of materializing and consuming the trace and is not an erasure-law proof.

Run the completed suite against `/tmp/keiki-ep81-before.csv` with `+RTS -T`, write the post-change
CSV to `/tmp/keiki-ep81-after.csv`, and inspect both replay lengths. The compatibility rows retain
their exact pre-change names and therefore receive tasty-bench baseline comparisons. If a
compatibility row is more than 20% slower, repeat it under the same GHC/build conditions; a
repeatable regression must be explained and corrected or explicitly accepted in the Decision Log.
Compute the before/after allocation delta for 32 and 1,024 events. A delta whose slope grows with
completed edges is a blocking sign that compatibility replay is allocating trace-related data.
The detailed rows are expected to allocate O(k) trace storage and may be noticeably slower; record
their ratios as the measured cost of opting into attribution, not as a pass/fail threshold.

Extend `test/Keiki/RoundTrip.hs` with a third permanent property in `roundTripSpec` and
`roundTripSpecUnchecked`. Generate the existing command scripts, obtain the complete forward event
log, and call both detailed and compatibility replay. Compare the final state and
fixture-specific observation. For every detailed success, check:

the empty log has an empty trace and unchanged seed observation; a non-empty log has non-empty
spans starting at zero and ending at the log length; consecutive spans touch without gaps or
overlap; each span length equals the recorded count; the selected `EdgeRef` resolves within
`edgesOut t source`; the resolved edge's mode, target, and output length match the entry; adjacent
entry targets equal next sources; and the final entry target equals the returned state. These
checks turn the improvement request's theoretical laws into generated regression evidence.

### Milestone 4 — public contract, durable rationale, and lifecycle records

Write full Haddocks in `src/Keiki/Core.hs` for every new type, field, and operation. State that
`EdgeRef` is local to one transducer construction and changes with outgoing declaration order.
Define `[start,end)`, the empty-input law, the partition/path laws, live-first phase reporting,
multi-event completion, epsilon unobservability, and the fact that a failed strict replay returns
no trace. Document the exact erasure relationship beside both detailed and compatibility entry
points. Also document the cost model: compatibility replay does not collect attribution and keeps
O(1) auxiliary state, while detailed replay retains O(k) entries for `k` completed edges.

Update the relevant structured-decision/replay sections of `docs/guide/user-guide.md` and the
generalized sequential machine explanation in
`docs/foundations/04-projections-and-deriving-event-sourcing.md`. Explain why targets, outputs, or
post-state equality are not edge identity, and why the trace factors an observed event word rather
than reporting each tail as a transition.

Update `docs/adr/0002-event-logs-must-reproduce-forward-state.md` with the durable refinement: the
detailed operations are proof-relevant views whose erasure is the old execution; a successful
strict replay trace is a completed-edge factorization of the log; epsilon outputs remain
unobservable. Add ExecPlan 81 to the ADR's Plan(s) metadata. Do not add a new ADR unless a new
cross-cutting choice appears during implementation.

Add an `Unreleased` changelog entry for the new API. Keep
`docs/improvement-requests/expose-successful-edge-attribution-for-forward-stepping-and-structured-replay.md`
at `planned` until publication. Update `docs/improvement-requests/log.md` for material lifecycle
changes. At implementation completion but before release, record validation evidence in this
living plan; after authoritative publication, change IR-2 to `released`, update its compatibility
baseline, and log the status change.

Finish `jitsurei/bench/README.md` with the attribution group layout, strict-digest forcing rule,
pre/post CSV commands, allocation-slope interpretation, and the distinction between compatibility
regression evidence and expected opt-in detailed cost. Keep the general tasty-bench instructions
and existing head-to-head interpretation intact.

### Milestone 5 — repository validation

Format the tree, run the narrow detailed-success tests, rerun the completed tasty-bench comparison,
then run every Cabal suite, build Haddocks, and run the Nix flake gates. Validate the
improvement-request bundle with profile and log enforcement. Strict OKF currently reports only
IR-1's pre-existing missing recommended `reviews` field; do not silently edit that unrelated
document, but record whether the diagnostic remains. Inspect diff whitespace and tracked files.
Update Progress and Outcomes with exact test counts, benchmark ratios/allocation deltas, and
commands before declaring implementation complete.

### Milestone 6 — authoritative additive release

Release only after Milestone 5 is green and the user authorizes publication. Read and follow
`agents/skills/release/SKILL.md`; do not reproduce an ad hoc Hackage workflow. Refresh Hackage
preferred metadata and public upstream tags before choosing a version. If `0.6.0.0` remains the
latest package, the PVP-additive target is `0.6.1.0`; if another version exists, recompute the
smallest valid additive successor. Reconcile the missing public `v0.6.0.0` provenance through the
normal maintainer workflow before or as part of release; never force-move or fabricate a tag.

The release is complete only when the package page is public, the matching annotated upstream tag
resolves to the released source, the detailed API is present in that source, and the IR, changelog,
plan Progress, and Outcomes name the verified version and commit. Commits made while implementing
this plan use Conventional Commits and include the trailer
`ExecPlan: docs/plans/81-expose-detailed-step-success-and-replay-attribution-traces.md`.


## Concrete Steps

Run every command from `/Users/shinzui/Keikaku/bokuno/keiki`.

Before editing, preserve the current dirty worktree and verify the release/source baseline:

```bash
git status --short
mori registry show shinzui/keiki --full
curl -fsSL https://hackage.haskell.org/package/keiki/preferred.json
git ls-remote --tags origin
```

Expected baseline evidence includes Hackage `0.6.0.0`, public `v0.5.0.0`, and the already modified
IR-2 files. Do not discard those changes.

Before editing Core, locate the existing benchmark dependency, add only the Milestone 0
compatibility rows, and capture the performance baseline:

```bash
mori registry show Bodigrim/tasty-bench --full
cabal exec ghc -- --numeric-version
cabal bench jitsurei:keiki-bench \
  --benchmark-options='--csv /tmp/keiki-ep81-before.csv +RTS -T -RTS'
head -n 1 /tmp/keiki-ep81-before.csv
rg -n "compat" /tmp/keiki-ep81-before.csv
```

The header must include `Allocated,Copied,Peak Memory`. Record the compatibility rows and compiler
version in Progress before changing `src/Keiki/Core.hs`. If the file is lost after the refactor,
do not manufacture a "before" result from the new implementation; recover the recorded baseline
from the exact pre-refactor source in a separate clean worktree or repeat Milestone 0 before
continuing.

After Milestone 1, run the focused forward tests:

```bash
cabal test keiki:keiki-test \
  --test-options='--match Keiki.Core.stepEither' \
  --test-show-details=direct
```

After Milestones 2 and 3, run the focused replay and law groups:

```bash
cabal test keiki:keiki-test \
  --test-options='--match Keiki.Core.InFlight' \
  --test-show-details=direct

cabal test keiki:keiki-test \
  --test-options='--match Keiki.Core structured replay' \
  --test-show-details=direct

cabal test keiki:keiki-test \
  --test-options='--match Keiki.Core replay-only edges' \
  --test-show-details=direct

cabal test keiki:keiki-test \
  --test-options='--match Keiki.RoundTrip' \
  --test-show-details=direct
```

The focused runs must finish with zero failures and show the new edge-ref, span, live-first, exact
failure, and generated trace-law examples.

After focused replay tests, inspect the performance-sensitive call graph:

```bash
rg -n "DiscardTrace|CollectTrace|applyEventsDetailedEither|applyEventsEither|reconstituteEither|replayEvents" \
  src/Keiki/Core.hs
```

The output must show every compatibility list replay seeded with `DiscardTrace`, only detailed
entry points seeded with `CollectTrace`, and no compatibility call routed through a public detailed
operation. This static gate complements behavior tests; no flaky wall-clock threshold is used.

Run the completed benchmark suite against the pre-refactor CSV and retain allocation data in the
post-change CSV:

```bash
cabal bench jitsurei:keiki-bench \
  --benchmark-options='--baseline /tmp/keiki-ep81-before.csv --csv /tmp/keiki-ep81-after.csv --fail-if-slower 20 +RTS -T -RTS'
rg -n "compat|detailed" /tmp/keiki-ep81-before.csv /tmp/keiki-ep81-after.csv
```

New detailed rows have no pre-refactor baseline and therefore are not expected to print a baseline
comparison; their `bcompare` ratios are the within-run evidence. For compatibility rows, inspect
both timing and allocation columns at 32 and 1,024 events. Repeat any row reported more than 20%
slower before concluding that it regressed. A repeatable event-count-proportional allocation delta
blocks completion until its source is understood and shown not to be discarded attribution.

Format and run the complete implementation gates:

```bash
nix fmt
cabal build keiki
cabal test all --test-show-details=direct
cabal haddock keiki
nix flake check
```

The expected result is every package suite passing with zero failures, successful Haddock
generation for `Keiki.Core`, and green `treefmt` and `pre-commit` flake checks. Record exact suite
and example counts in Progress because the baseline count may change before implementation.

Validate the improvement-request lifecycle and inspect hygiene:

```bash
okf validate docs/improvement-requests \
  --profile mori/improvement-requests-profile.dhall \
  --profile-enforce \
  --log-enforce

okf validate docs/improvement-requests \
  --strict \
  --profile mori/improvement-requests-profile.dhall \
  --profile-enforce \
  --log-enforce

git diff --check
git status --short
git diff --stat
```

The non-strict OKF command must report `OK`. If the strict command still reports only IR-1's
pre-existing recommended-field diagnostic, record it as an unrelated repository condition; any
IR-2 or log diagnostic blocks completion.

Immediately before the release milestone, repeat the authoritative checks and inspect the release
skill:

```bash
sed -n '1,360p' agents/skills/release/SKILL.md
curl -fsSL https://hackage.haskell.org/package/keiki/preferred.json
git ls-remote --tags origin
git status --short
```

Then follow that skill's dry-run, versioning, tagging, and publication commands exactly. Do not put
credentials, one-time tokens, or upload commands into this plan's recorded transcripts.


## Validation and Acceptance

The implementation is accepted when all behavior below is observable.

For two disjoint guarded live siblings with identical target, output values, and per-slot register
observations, `stepDetailedEither` returns different exact `EdgeRef`s when their respective inputs
are supplied. Both results report `Live`. Erasing either result gives exactly the corresponding
`stepEither` success, and every existing `StepFailure` is byte-for-structure equal between the two
operations. An accepted epsilon-output live edge is attributable forward; a replay-only edge is
never attributable forward.

For a successful replay of no events, `applyEventsDetailedEither` returns the seed state/register
observation and `[]`. For a successful replay of three events emitted by a two-event edge followed
by a one-event edge, it returns exactly two attributions with spans `[0,2)` and `[2,3)`, counts `2`
and `1`, correct source/target path, correct edge modes, and the same final state/register
observation as `applyEventsEither`.

For every generated complete log in the permanent round-trip fixtures, spans form a non-empty,
gap-free, overlap-free partition of `[0,length events)` unless the log is empty; each entry resolves
to the reported edge in the same concrete transducer; the mode, target, and static output length
agree; adjacent entries form a path; and the last target is the detailed replay's final state.
This property must remain green for every validation-clean fixture and the existing explicitly
unchecked composition fixtures.

At a live/replay-only overlap, detailed replay reports the live edge. When no live edge can invert
the historical event, it reports the replay-only edge. A multi-event head does not produce a public
completed entry until its tail finishes. No replay trace ever invents an epsilon-output edge.

No-inverting-edge, ambiguous-inversion, queue-mismatch, and truncation examples return exactly the
same `ReplayFailure` index, pre-failure `InFlight` wrapper, and reason through detailed and
compatibility APIs. On any `Left`, no partial trace is exposed. Existing `replayEvents` behavior
from an arbitrary mid-chain seed remains green.

Compatibility replay retains O(1) auxiliary trace state regardless of log length: its call graph
uses the nullary `DiscardTrace` policy and cannot construct `PendingAttribution`,
`ReplayAttribution`, or a trace list. Detailed replay alone uses `CollectTrace` and retains O(k)
entries for `k` completed edges. The two policies call the same inversion/update/queue/failure
worker, so this performance separation does not create a second evaluator. Forward `stepEither`
may erase one constant-size `StepSuccess`; no stronger allocation promise is made without
measurement.

The existing `jitsurei:keiki-bench` suite contains stable compatibility rows captured before the
Core refactor and matching rows after it, plus opt-in detailed rows whose strict scalar digests
consume all attribution metadata. The post-change run uses the same GHC, optimization/alignment
settings, fixture values, and benchmark names as the baseline. No compatibility row has an
unexplained repeatable slowdown above 20%. More importantly, the before/after compatibility
allocation delta from 32 to 1,024 events has no positive slope attributable to pending records,
attribution records, or trace list cells. Detailed replay's timing ratio and O(k) allocation are
recorded as an explicit opt-in cost, not treated as a compatibility failure.

Haddocks and user/foundation documentation state all local-identity, half-open-span, partition,
path, live-first, multi-event completion, epsilon-observability, and erasure laws. ADR-0002 carries
the durable contract. The full Cabal, Haddock, Nix, OKF, and diff gates pass as described above.

The improvement request is fully complete only after Hackage exposes the new API and a matching
public upstream tag resolves to the released source. Before then its lifecycle remains `planned`,
not `released`.


## Idempotence and Recovery

Source, test, plan, ADR, changelog, and improvement-request edits are ordinary tracked text changes
and are safe to repeat. `nix fmt`, Cabal builds/tests/Haddocks, Nix checks, Mori queries, Hackage
metadata reads, OKF validation, and Git inspections can be rerun without changing external state.
Preserve unrelated working-tree changes and never use a destructive Git reset or restore to recover
from a failed test.

The benchmark commands are repeatable, but `/tmp/keiki-ep81-before.csv` is valid as a "before"
baseline only when produced from the Milestone 0 compatibility probes and pre-refactor Core under
the recorded compiler. Repeating it after Core changes would erase the comparison. The CSV files
are disposable, untracked evidence; record the significant rows in Progress or Outcomes before
removing them. If a later run uses a different compiler or optimization setting, capture a new
matched before/after pair rather than comparing unlike builds.

If the replay refactor fails partway, keep compatibility functions delegating to the last compiling
shared internal function in `DiscardTrace` mode and finish one call path at a time. Never restore a
green build by routing compatibility through `CollectTrace` and erasing the result; that masks the
performance invariant. A failed focused test requires only a code/test correction and rerun; no
database or generated state needs cleanup. Cabal's
`dist-newstyle` is disposable build output, but do not remove it unless a compiler cache problem is
actually diagnosed.

Release is not idempotent: Hackage versions are immutable and published Git tags must not be moved.
Before upload, verify the target version does not already exist and that the intended commit is
clean and tested. If publication succeeds but a later local step fails, do not retry the upload;
inspect Hackage and the public tag, resume the release skill at its documentation/recording step,
and record the partial outcome. If the target version already exists unexpectedly, stop and
recompute the release state rather than overwriting or force-tagging.


## Interfaces and Dependencies

No new library dependency is required. `src/Keiki/Core.hs` already owns `Edge`, `EdgeMode`,
`EdgeRef`, `RegFile`, `StepFailure`, `InFlight`, `ReplayFailure`, inversion, and all compatibility
entry points. `base` supplies the lists and integers needed for spans and trace accumulation.
The existing `jitsurei:keiki-bench` target already depends on
`mori://Bodigrim/tasty-bench/packages/tasty-bench` at `>=0.4 && <0.6`, exposes `nf`, `bcompare`,
CSV baselines, and RTS allocation reporting, and is compiled with `-fproc-alignment=64`. This plan
does not alter that bound or add tasty-bench to the library.

The public surface at the end of Milestones 1 and 2 is:

```haskell
data StepSuccess (rs :: [Slot]) s co = StepSuccess
  { stepSuccessEdge :: EdgeRef s
  , stepSuccessMode :: EdgeMode
  , stepSuccessState :: s
  , stepSuccessRegs :: RegFile rs
  , stepSuccessOutputs :: [co]
  }

stepDetailedEither ::
  BoolAlg phi (RegFile rs, ci) =>
  SymTransducer phi rs s ci co ->
  (s, RegFile rs) ->
  ci ->
  Either (StepFailure s) (StepSuccess rs s co)

data ReplayEventSpan = ReplayEventSpan
  { replaySpanStart :: Int
  , replaySpanEnd :: Int
  }
  deriving stock (Eq, Show)

data ReplayAttribution s = ReplayAttribution
  { replayAttributionEdge :: EdgeRef s
  , replayAttributionMode :: EdgeMode
  , replayAttributionSource :: s
  , replayAttributionTarget :: s
  , replayAttributionSpan :: ReplayEventSpan
  , replayAttributionEventCount :: Int
  }
  deriving stock (Eq, Show)

data ReplaySuccess (rs :: [Slot]) s = ReplaySuccess
  { replaySuccessState :: s
  , replaySuccessRegs :: RegFile rs
  , replaySuccessTrace :: [ReplayAttribution s]
  }

applyEventsDetailedEither ::
  (BoolAlg phi (RegFile rs, ci), Eq co) =>
  SymTransducer phi rs s ci co ->
  (s, RegFile rs) ->
  [co] ->
  Either (ReplayFailure s co) (ReplaySuccess rs s)

reconstituteDetailedEither ::
  (BoolAlg phi (RegFile rs, ci), Eq co) =>
  SymTransducer phi rs s ci co ->
  [co] ->
  Either (ReplayFailure s co) (ReplaySuccess rs s)
```

Field names may change only if compilation exposes a real collision with the module's duplicate
record-field conventions; any change must be recorded in the Decision Log and propagated through
Haddocks, tests, and this interface section. Do not add `Eq` or `Show` constraints to `RegFile` or
the operations merely to make result records derivable.

The private implementation introduces a trace policy shaped like the following; exact field names
may follow local conventions, but the nullary discard constructor is a requirement:

```haskell
data ReplayTraceState s
  = DiscardTrace
  | CollectTrace
      !(Maybe (PendingAttribution s))
      ![ReplayAttribution s]
```

`PendingAttribution` and the trace-aware replay cursor remain private. The `DiscardTrace` branch
must not allocate either. The public `InFlight`, `ReplayFailure`, `ReplayStepFailure`,
`StepFailure`, and existing operation signatures remain source-compatible. The public detailed
span and attribution metadata are strict enough to avoid retaining event values or commands
accidentally; use strict `Int` and state fields consistently with existing failure records where
appropriate.

`test/Keiki/RoundTrip.hs` remains the shared property harness and uses each fixture's existing
`rtObserve` function as the legal register comparison seam. Hspec and QuickCheck are already test
dependencies in `keiki.cabal`; no bound changes are needed. Mori identifies this package as
`mori://shinzui/keiki/packages/keiki` and the downstream consumer as
`mori://shinzui/keiro/packages/keiro-dsl`.


Revision note (2026-07-31): Revised the replay architecture after performance review. Compatibility
replay now uses a nullary `DiscardTrace` policy with O(1) auxiliary state, detailed replay alone
uses `CollectTrace`, and the plan explicitly rejects building then erasing a trace. Forward erasure
remains simple because its possible cost is one constant-size success record rather than a
log-length allocation.

Revision note (2026-07-31): Integrated the existing `jitsurei:keiki-bench` tasty-bench harness.
The plan now captures compatibility timing and allocation evidence before the Core refactor, uses
32- and 1,024-event logs to detect a trace-sized allocation slope, strictly consumes detailed trace
metadata, and records opt-in detailed cost separately from compatibility regression gates.
