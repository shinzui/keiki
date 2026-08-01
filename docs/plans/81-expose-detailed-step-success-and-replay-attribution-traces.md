---
id: 81
slug: expose-detailed-step-success-and-replay-attribution-traces
title: "Expose detailed step success and replay attribution traces"
kind: exec-plan
created_at: 2026-07-31T20:29:39Z
intention: intention_01kywzfvmae5na5c26gybz51q7
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

Existing replay callers do not pay to build or thread a trace they discard. One private event
kernel owns inversion, guard verification, update application, output-tail evaluation, queue
comparison, and step failures. A compatibility loop gives that kernel pair-shaped success
continuations and has no trace type in its state or result. A detailed loop gives the same kernel
collecting continuations and retains O(number of completed edges) trace storage. `replayEvents`,
`applyEventsEither`, and `reconstituteEither` use the former; only callers that opt into detailed
replay use the latter. Forward `stepEither` keeps the simpler record-erasure implementation because
its one short-lived success record is constant-size and not an asymptotic cost.

The existing `jitsurei:keiki-bench` tasty-bench suite supplies before/after performance evidence.
Before changing Core, it gains compatibility rows for `stepEither` and strict replay over both the
existing 32-event log and a 1,024-event log, and captures a CSV baseline with allocation statistics.
After implementation, the same rows are compared against that file and new opt-in detailed rows
measure the real trace cost by strictly consuming a metadata checksum. The benchmark complements,
but does not replace, the semantic laws and the static no-trace call-graph gate.

The compatibility benchmark also uses 4,096- and 16,384-event logs against a matched pre-refactor
worktree. These larger scales exposed the original generic result's positive per-event allocation
slope and then verified that the pair-shaped specialization removed it.

This is one ExecPlan rather than a MasterPlan. The work has one implementation authority in
`src/Keiki/Core.hs`, one public API surface, and one release. Splitting forward and replay detail
into independent plans would force both plans to edit the same evaluator and compatibility laws,
while the completed architecture-hardening MasterPlan 16 is historical context rather than an
active parent initiative.


## Progress

- [x] (2026-07-31T21:01:36Z) Milestone 0: extended the existing tasty-bench suite with six stable
  compatibility probes and captured `/tmp/keiki-ep81-before.csv` before changing Core. GHC 9.12.4
  built commit `a52a5faa0228059be40d0f099d886dbe205ea8d0` plus the benchmark/plan worktree edits; all 30
  benchmark rows passed. The CSV header is `Name,Mean (ps),2*Stdev (ps),Allocated,Copied,Peak
  Memory`. Builder `stepEither`, 32-event replay, and 1,024-event replay measured 185,646 ps/1,702
  B, 16,777,453 ps/83,305 B, and 574,189,453 ps/2,821,008 B. AST counterparts measured 170,003
  ps/1,686 B, 16,097,210 ps/82,809 B, and 558,171,093 ps/2,804,675 B. The capture command was
  `cabal bench jitsurei:keiki-bench --benchmark-options='--csv /tmp/keiki-ep81-before.csv +RTS -T
  -RTS'`; `git diff -- src/Keiki/Core.hs` was empty afterward.
- [x] (2026-07-31T21:04:30Z) Milestone 1: added public `StepSuccess` and
  `stepDetailedEither`, made `stepEither` erase the detailed success, and added guarded-sibling,
  epsilon, replay-only, failure-erasure, and result-erasure examples. The focused command
  `cabal test keiki:keiki-test --test-options='--match Keiki.Core.stepEither'
  --test-show-details=direct` passed 9 examples with 0 failures under GHC 9.12.4.
- [x] (2026-07-31T21:08:45Z) Milestone 2: factored inversion, guard checking, update application,
  tail construction, queue comparison, and failures through `applyEventWithTrace` and
  `replayEventsWithTrace`; added the nullary `DiscardTrace`, collecting `CollectTrace`, public
  span/attribution/success records, and both detailed strict entry points. The 13 InFlight, 13
  structured-replay, and 22 replay-only focused examples passed with 0 failures. Static `rg`
  inspection showed `applyEventStreamingEither`, `replayEvents`, and `applyEventsEither` seeding
  `DiscardTrace`; `reconstituteEither` delegates to that strict compatibility path; and only
  `applyEventsDetailedEither` plus its `reconstituteDetailedEither` wrapper seed `CollectTrace`.
- [x] (2026-07-31T21:28:15Z) Milestone 3: added exact detailed/compatibility failure pairs for
  no inversion, ambiguity, queue mismatch, and truncation; live-first and replay-only twin
  attribution examples; a 1,024-event compatibility/detailed regression; and generated P3 trace
  laws in all permanent round-trip fixtures. The focused structured suite passed 18 examples, the
  replay-only suite passed 22, InFlight passed 13, and RoundTrip passed 36 examples including 100
  generated P3 cases for each of four fixtures. Added six strict detailed benchmark rows. The
  final attribution-only command against `/tmp/keiki-ep81-before.csv` wrote
  `/tmp/keiki-ep81-after.csv` and passed all 12 rows with the 20% gate. Builder compatibility
  timing changes were +14% (`stepEither`), +13% (32 events), and +14% (1,024 events); AST changes
  were +8%, +9%, and +15%. Compatibility allocation deltas were +40 B, -144 B, and +65,387 B for
  builder and +40 B, -144 B, and +65,366 B for AST. The identical long-log residual is one 64 KiB
  measurement block plus small scalar variance, while static inspection proves the nullary branch
  cannot construct pending records, attribution records, or trace list cells. Detailed allocation
  above same-run compatibility was 0 B/7,593 B/245,479 B for builder and 0 B/7,593 B/245,494 B for
  AST; detailed timing ratios were 0.95x/0.99x/1.04x and 1.04x/1.05x/1.04x respectively.
- [x] (2026-07-31T21:51:27Z) Supplemental compatibility scale gate: added permanent 4,096- and
  16,384-event rows and compared the current implementation twice with commit `2b3bf6a` in a
  detached worktree under GHC 9.12.4. All eight rows passed. The repeat's builder allocation
  deltas at 32/1,024/4,096/16,384 events were -144/+65,384/+262,042/+1,081,321 B; AST deltas were
  -144/+65,413/+261,997/+1,081,075 B. The three larger rows are approximately 64/64/66 extra
  B/event, proving a positive compatibility allocation slope rather than a one-time 64 KiB
  measurement block. Repeat timing changes were builder +1.4%/+2.0%/+4.0%/+6.9% and AST
  +0.9%/+2.0%/+1.2%/+11.6%. Evidence is in `/tmp/keiki-ep81-scale-before.csv`,
  `/tmp/keiki-ep81-scale-after.csv`, and `/tmp/keiki-ep81-scale-after-repeat.csv`.
- [x] (2026-07-31T22:31:04Z) Milestone 3b: replaced runtime `DiscardTrace` threading with a
  pair-shaped compatibility fold and kept one continuation-shaped event kernel as the sole
  inversion/update/queue/step-failure authority. All four focused suites passed. The complete
  40-row benchmark passed, with detailed replay at 1.00--1.02x compatibility time. Against the
  matched pre-refactor scale CSV, builder allocation deltas at 32/1,024/4,096/16,384 events were
  0/-12/+37/+99 B and AST deltas were 0/0/-22/-79 B. The former 64--66 B/event slope is gone;
  evidence is in `/tmp/keiki-ep81-scale-3b.csv` and `/tmp/keiki-ep81-3b.csv`.
- [x] (2026-07-31T21:57:58Z) Milestone 4: drafted field-level Haddocks, user/foundation guidance,
  the ADR-0002 refinement, Unreleased changelog entries, IR lifecycle notes, and benchmark operating
  documentation. `cabal haddock keiki` completed successfully; its warnings are the existing
  project-wide link and `Keiki.Symbolic.SymEnv` coverage warnings. These records remain on
  `feat/detailed-attribution-traces` while Milestone 3b is unresolved.
- [x] (2026-07-31T22:14:19Z) Released the unrelated `v0.6.0.0` work without Plan 81. Validated the
  exact tagged commit `c8f2c343ce03f42e10de77d684769f15ad30feda` through formatting, repository
  and clean-room source-distribution builds/tests, package checks, and Nix gates; advanced
  public `master` only to that commit; published the existing annotated tag and GitHub release; and
  resumed this branch at `1b5256f`.
- [x] (2026-07-31T22:37:15Z) Milestone 5: `nix fmt`, `cabal build keiki`, all four focused suites,
  the 40-row benchmark, `cabal test all`, `cabal haddock keiki`, and `nix flake check` passed under
  GHC 9.12.4. Full-suite counts were Keiki 586, Jitsurei 122, codec 104, and codec-test 13 examples,
  all with zero failures. Haddock retained only the existing project-wide link and coverage
  warnings. Profile/log-enforced OKF validation reported `OK: 2 concepts`; strict validation still
  reports only IR-1's pre-existing missing recommended `reviews` field. Diff whitespace is clean.
- [x] (2026-08-01T00:01:39Z) Integrated the validated branch into `master`. Commit `d1bdd9a`
  explicitly reverted the temporary release deferral, and merge commit `4cadca3` brought in the
  Milestone 3b specialization; its tree was byte-identical to `b2e8745`. The four focused suites
  passed 13/18/22/36 examples. The repeated scale benchmark stayed below the 20% timing threshold;
  builder allocation deltas at 32/1,024/4,096/16,384 events were 0/-11/0/+105 B and AST deltas were
  0/0/-49/-93 B. `nix flake check` passed on the merge.
- [x] (2026-08-01T12:39:09Z) Audited improvement-request lifecycle metadata against the current
  source, tests, Hackage preferred metadata, and public upstream tags. Advanced IR-2 from `planned`
  to `implemented`; `released` remains gated on Milestone 6.
- [ ] Milestone 6: reconcile release authority, publish the additive release through the repository
  release workflow, and record the final tag/version evidence.


## Surprises & Discoveries

- The first generic replay worker compiled without inlining preserved O(1) retained trace state
  but added 171,914 B to the builder's 1,024-event compatibility row and slowed it by 33%. Marking
  the shared worker and its two trace transitions `INLINE` let GHC specialize the known nullary
  `DiscardTrace` branch: a repeat passed all six compatibility rows and reduced the long-row delta
  to one 64 KiB allocation block at 1,024 events. A continuation-return experiment produced the
  same allocation and noisier timing, so it was discarded. The later 4,096- and 16,384-event scale
  gate showed that interpreting the residual as a one-time allocator block was wrong: the delta
  grew to approximately 256 KiB and 1.03 MiB, or about 64--66 B/event. Evidence:
  `/tmp/keiki-ep81-inline.csv` passed all six original rows; the retained final
  `/tmp/keiki-ep81-after.csv` passed all 12 original attribution rows; and the matched scale CSVs
  are recorded in Progress.

- Specializing only the result shape was sufficient. An inlined continuation-shaped event kernel
  lets compatibility replay construct the historical pair while detailed replay constructs its
  trace-bearing result. Separate list folds share that kernel and the failure-index constructor.
  The exact four-size allocation deltas collapsed from approximately 64--66 B/event to values
  between -79 B and +99 B for the whole run, with no event-count-proportional slope.

- Cabal 3.16 splits `--test-options` on spaces after the shell has processed the outer quoting. A
  focused Hspec match containing spaces must preserve embedded quotes, for example
  `--test-options='--match "Keiki.Core structured replay"'`; the plan's original form passed
  `structured` as an unexpected standalone argument. The corrected command passed 13 examples.

- The package registry and Git release authorities were temporarily out of sync. Hackage already
  listed `0.6.0.0`, while public Git exposed tags only through `v0.5.0.0`. After validating the
  exact local annotated tag, public `master`, `v0.6.0.0`, and the GitHub release were published at
  `c8f2c343ce03f42e10de77d684769f15ad30feda`; the authorities now agree without exposing Plan 81.

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

- Decision: Inline the shared replay worker and trace-state transitions, while retaining the
  explicit `DiscardTrace`/`CollectTrace` branches and one source fold.
  Rationale: GHC 9.12.4 otherwise retained generic trace-policy plumbing in compatibility replay.
  Inlining preserved the single semantic authority and allowed the nullary branch to specialize,
  eliminating the measured timing regression and most of the allocation delta without adding a
  second evaluator. A continuation-return variant did not improve allocation and was reverted.
  Date: 2026-07-31

- Decision: Treat the larger-scale compatibility allocation slope as a release blocker and
  specialize the discard result shape before publication, while retaining one event-level
  inversion/update/queue/failure authority.
  Rationale: matched 1,024-, 4,096-, and 16,384-event rows repeatedly allocate approximately
  64--66 additional bytes per event through compatibility replay. The nullary trace state prevents
  attribution-record construction but does not recover the old pair-shaped result and fold. A
  specialized compatibility result path is therefore required even though timing remains below
  the provisional 20% threshold.
  Date: 2026-07-31

- Decision: Replace the runtime trace-policy sum with one inlined, continuation-shaped event
  kernel plus two result-specific list folds. Compatibility success continuations construct only
  `(InFlight, RegFile)`; detailed continuations alone update `ReplayTraceState`. Both folds use the
  same helper to attach event indices to step failures.
  Rationale: this is the smallest design that restores the pre-feature pair-shaped hot path while
  retaining one authority for inversion, live-first selection, guards, updates, evaluated tails,
  queue comparison, and step failures. The matched four-size gate removed the former 64--66
  B/event allocation slope, while all erasure and exact-failure laws stayed green.
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
  for accidental trace construction. The pair-shaped compatibility fold, detailed-only trace
  state, and shared event-kernel call graph remain the hard architectural guarantee.
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

- Decision: Preserve the incomplete attribution work on `feat/detailed-attribution-traces`, remove
  Plan 81's implementation commits from `master`, release the unrelated accumulated changes, and
  resume the performance decision from the feature branch afterward.
  Rationale: the confirmed compatibility allocation slope blocks this feature's acceptance but
  should not block unrelated, already releasable work. A named branch plus ordinary revert commits
  preserves all source, tests, documentation, and benchmark evidence without rewriting history.
  Date: 2026-07-31


## Outcomes & Retrospective

Interim outcome: the requested attribution semantics, laws, documentation, and benchmark evidence
are integrated into `master`. Milestone 3b removed the approximately 64--66 additional bytes per
event from compatibility replay while preserving one semantic event kernel; the performance
blocker is cleared. The feature remains deliberately absent from published `v0.6.0.0`; all
Milestone 5 and post-merge gates are green, so only the separately authorized additive release
remains. The IR is `implemented`, and no Plan 81 API has been published in a versioned release.


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

### Milestone 2 — completed replay attribution with one event kernel

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

Factor event application into one inlined continuation-shaped kernel. It remains the sole authority
for inversion, live-first selection, guard checking, update application, evaluated-tail
construction, queue equality, and step failures. A head-success continuation receives the selected
source, edge index, edge, evaluated tail, next wrapper, and registers. A tail-success continuation
receives the remaining queue, next wrapper, and registers. The continuations choose only the result
shape; they must not repeat semantic decisions.

`applyEventStreamingEither`, `replayEvents`, `applyEventsEither`, and `reconstituteEither` supply
compatibility continuations that construct the historical `(InFlight, RegFile)` pair. Their list
fold has no trace type in its accumulator or result and never calls `applyEventsDetailedEither`.
`applyEventsDetailedEither` uses a separate collecting fold whose private `ReplayTraceState` holds
the optional pending record and a strict reverse trace accumulator. It rejects a final `InFlight`
with the existing `ReplayLogTruncated` value, reverses the completed trace once at successful
settlement, and returns `ReplaySuccess`. `reconstituteDetailedEither` supplies the initial seed and
uses that collecting path. The `Maybe` wrappers continue to delegate to the compatibility `Either`
functions.

This design preserves one semantic event worker but two operational list folds. Compatibility has
O(1) auxiliary state with respect to event/edge count; detailed replay has O(k) retained trace
storage for `k` completed edges, which is the explicit price of requesting the trace. Share a small
helper that attaches the current event index and wrapper to a kernel step failure so the folds
cannot drift in failure classification. Do not build and then erase a trace entry.

`replayEvents` must still accept an arbitrary public `InFlight` whose original selection metadata
is unavailable; its pair fold simply continues tail comparison exactly as today. Detailed strict
replay starts from a settled seed, so it never fabricates prior attribution. At the end of this
milestone, all pre-existing replay tests pass and new fixed examples show one attribution per
completed edge. Inspect the Core diff and confirm compatibility uses only the pair fold, detailed
entry points alone carry `ReplayTraceState`, and both paths instantiate the same event kernel.

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
the private state shape and call graph: compatibility calls must use the pair-shaped fold, and only
the detailed call may construct `ReplayTraceState` and public entries.
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

Before accepting an apparent single-block compatibility delta, add compatibility-only 4,096- and
16,384-event rows and compare them with the same rows applied to pre-refactor commit `2b3bf6a` in a
detached worktree. If the byte delta divided by event count remains positive across the three
larger sizes, treat it as a release-blocking slope and specialize the discard result path before
rerunning the matched scale gate.

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
at `implemented` after implementation validation and until publication. Update
`docs/improvement-requests/log.md` for material lifecycle changes. At implementation completion but
before release, record validation evidence in this living plan; after authoritative publication,
change IR-2 to `released`, update its compatibility baseline, and log the status change.

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
rg -n "ReplayTraceState|applyEventKernel|applyEventsDetailedEither|applyEventsEither|reconstituteEither|replayEvents" \
  src/Keiki/Core.hs
```

The output must show compatibility replay using the pair-shaped `replayEvents` fold, detailed
entry points alone using `ReplayTraceState`, and both paths calling `applyEventKernel`. No
compatibility call may route through a public detailed operation. This static gate complements
behavior tests; no flaky wall-clock threshold is used.

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

For the supplementary scale gate, use a detached worktree at commit `2b3bf6a`, apply the same
4,096- and 16,384-event fixture rows there, and capture only the compatibility replay leaves:

```bash
cabal bench jitsurei:keiki-bench \
  --benchmark-options='-p /applyEventsEither/ --csv /tmp/keiki-ep81-scale-before.csv +RTS -T -RTS'

cabal bench jitsurei:keiki-bench \
  --benchmark-options='-p /applyEventsEither/ --baseline /tmp/keiki-ep81-scale-before.csv --csv /tmp/keiki-ep81-scale-after.csv +RTS -T -RTS'
```

The first command runs in the pre-refactor worktree and the second in the current repository. Run
the second command twice. Compare exact `Allocated` columns rather than rounded console units.

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

Compatibility replay retains O(1) auxiliary state regardless of log length: its pair-shaped fold
and success continuations cannot construct `ReplayTraceState`, `PendingAttribution`,
`ReplayAttribution`, or a trace list. Detailed replay alone carries `ReplayTraceState` and retains
O(k) entries for `k` completed edges. Both folds call the same inlined
inversion/update/queue/step-failure kernel, so this result specialization does not create a second
evaluator. Forward `stepEither` may erase one constant-size `StepSuccess`; no stronger allocation
promise is made without measurement.

The existing `jitsurei:keiki-bench` suite contains stable compatibility rows captured before the
Core refactor and matching rows after it, plus opt-in detailed rows whose strict scalar digests
consume all attribution metadata. The post-change run uses the same GHC, optimization/alignment
settings, fixture values, and benchmark names as the baseline. No compatibility row has an
unexplained repeatable slowdown above 20%. More importantly, the before/after compatibility
allocation deltas at 32, 1,024, 4,096, and 16,384 events have no positive event-count-proportional
slope. Detailed replay's timing ratio and O(k) allocation are recorded as an explicit opt-in cost,
not treated as a compatibility failure.

Haddocks and user/foundation documentation state all local-identity, half-open-span, partition,
path, live-first, multi-event completion, epsilon-observability, and erasure laws. ADR-0002 carries
the durable contract. The full Cabal, Haddock, Nix, OKF, and diff gates pass as described above.

The improvement request is fully complete only after Hackage exposes the new API and a matching
public upstream tag resolves to the released source. Before then its lifecycle remains
`implemented`, not `released`.


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

If the replay refactor fails partway, keep compatibility functions on the pair-shaped fold around
the last compiling shared event kernel and finish one call path at a time. Never restore a green
build by routing compatibility through `ReplayTraceState` and erasing the result; that masks the
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

The private implementation introduces a cursor used only by detailed replay; exact field names may
follow local conventions:

```haskell
data ReplayTraceState s
  = ReplayTraceState
      !(Maybe (PendingAttribution s))
      ![ReplayAttribution s]
```

`PendingAttribution` and the trace-aware replay cursor remain private and must be unreachable from
the pair-shaped compatibility fold. The public `InFlight`, `ReplayFailure`, `ReplayStepFailure`,
`StepFailure`, and existing operation signatures remain source-compatible. The public detailed span
and attribution metadata are strict enough to avoid retaining event values or commands
accidentally; use strict `Int` and state fields consistently with existing failure records where
appropriate.

`test/Keiki/RoundTrip.hs` remains the shared property harness and uses each fixture's existing
`rtObserve` function as the legal register comparison seam. Hspec and QuickCheck are already test
dependencies in `keiki.cabal`; no bound changes are needed. Mori identifies this package as
`mori://shinzui/keiki/packages/keiki` and the downstream consumer as
`mori://shinzui/keiro/packages/keiro-dsl`.


Revision note (2026-07-31): Recorded the initial replay architecture after performance review.
Compatibility replay used a nullary `DiscardTrace` policy with O(1) auxiliary state, detailed
replay alone used `CollectTrace`, and the plan rejected building then erasing a trace. Milestone 3b
later superseded the runtime policy with a pair-shaped compatibility fold after scale benchmarks
exposed residual per-event allocation. Forward erasure remains simple because its possible cost is
one constant-size success record rather than a log-length allocation.

Revision note (2026-07-31): Integrated the existing `jitsurei:keiki-bench` tasty-bench harness.
The plan now captures compatibility timing and allocation evidence before the Core refactor, uses
32- and 1,024-event logs to detect a trace-sized allocation slope, strictly consumes detailed trace
metadata, and records opt-in detailed cost separately from compatibility regression gates.

Revision note (2026-07-31): Expanded the compatibility allocation gate to 4,096 and 16,384 events
after the 1,024-event delta could be mistaken for one runtime-system allocation block. Matched
pre-refactor measurements prove approximately 64--66 extra allocated bytes per event, so discard
result specialization is now an explicit pre-release blocker.

Revision note (2026-07-31): Recorded the decision to preserve Plan 81 on
`feat/detailed-attribution-traces`, release unrelated work from `master` without the attribution
changes, and resume the specialized-discard investigation from this branch afterward.

Revision note (2026-07-31): Recorded the completed intervening `v0.6.0.0` release, including exact
tag validation, public Git/GitHub reconciliation, exclusion of Plan 81, and return to the feature
branch at Milestone 3b.

Revision note (2026-07-31): Completed Milestone 3b with a pair-shaped compatibility fold and one
continuation-shaped event kernel. The matched four-size gate shows no event-count-proportional
allocation delta, so the performance release blocker is cleared.

Revision note (2026-08-01): Recorded the explicit restoration and clean merge into `master`, plus
the focused, allocation, timing-repeat, and Nix evidence from the exact merged tree.
