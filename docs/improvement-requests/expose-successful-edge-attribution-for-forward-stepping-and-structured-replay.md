---
type: Improvement Request
title: Expose successful edge attribution for forward stepping and structured replay
description: >-
  Add structured success APIs that identify the selected edge during forward stepping and each
  completed edge attribution during replay, without duplicating Keiki's evaluator or changing the
  existing compatibility entry points.
timestamp: 2026-08-01T12:39:09Z
requestId: IR-2
status: implemented
origin: mori://shinzui/keiro
plan: docs/plans/81-expose-detailed-step-success-and-replay-attribution-traces.md
reviews:
  - kind: model
    reviewer: codex
    reviewed_at: 2026-07-31T20:03:30Z
    document_timestamp: 2026-07-31T20:03:30Z
    scope: technical-accuracy
    outcome: approved
    provider: openai
    model: gpt-5
    effort: unspecified
    context: >-
      Reviewed against released Keiki 0.5.0.0 Core stepping and replay APIs and the downstream
      Keiro behavioral-conformance requirement for distinguishing guarded siblings and live-first
      replay-only attribution.
  - kind: model
    reviewer: codex
    reviewed_at: 2026-07-31T20:35:30Z
    document_timestamp: 2026-07-31T20:35:30Z
    scope: technical-accuracy
    outcome: approved
    provider: openai
    model: gpt-5
    effort: unspecified
    context: >-
      Revalidated against Hackage Keiki 0.6.0.0, the upstream-tag discrepancy, the GSM word-output
      and event-log round-trip foundations, live-first replay, and Keiro's finite-witness boundary;
      strengthened the request with trace-partition, path-continuity, epsilon-observability, and
      erasure laws, then confirmed ExecPlan 81 preserves those requirements.
  - kind: model
    reviewer: codex
    reviewed_at: 2026-08-01T12:39:09Z
    document_timestamp: 2026-08-01T12:39:09Z
    scope: technical-accuracy
    outcome: approved
    provider: openai
    model: gpt-5
    effort: unspecified
    context: >-
      Audited every request status against its linked ExecPlan, current source and tests, Hackage
      preferred-version metadata, and public upstream tags. Confirmed the detailed attribution API
      is implemented on public master but absent from the latest authoritative release, so the
      correct lifecycle is implemented rather than planned or released.
---

# Improvement Request: Expose Successful Edge Attribution for Forward Stepping and Structured Replay

## Status

**Implemented.** ExecPlan 81 added the detailed Core API, permanent erasure and replay-trace laws,
documentation, and matched compatibility/detailed performance evidence. The implementation is on
public `master`, and its focused and full repository gates passed. Publication remains separate
release work: Hackage and the matching public upstream tag still expose `0.6.0.0`, which does not
contain these APIs. The request must not advance to `released`, and Keiro must not select a
dependency bound from an unreleased checkout or infer a transition from targets or emitted values.

**Previously planned.** The request was accepted and specified by
[ExecPlan 81](../plans/81-expose-detailed-step-success-and-replay-attribution-traces.md). It moved to
implemented after the attribution semantics, laws, documentation, performance gate, and repository
validation were integrated into `master`.


## Context

Keiki `0.6.0.0` has strong structured failure information but deliberately compact success
results. `stepEither` returns `Either (StepFailure s) (s, RegFile rs, [co])`. Its failures identify
outgoing edges through `EdgeRef`, `RejectedEdgeSummary`, and `MatchedEdgeSummary`, but its success
does not say which edge was selected. `applyEventsEither` and `reconstituteEither` return a final
state and register file or a structured `ReplayFailure`; a successful replay does not expose which
edge attributed each observed event chain.

Target and event equality are not a sound substitute for edge attribution. Two outgoing guarded
edges can consume the same command constructor, share a target, and emit the same event
constructor while differing in guard, update, event field values, or live/replay-only role. A
caller comparing only the final state and events cannot prove which declared alternative ran.

Replay adds a second ambiguity. Keiki deliberately attributes an observed event in two phases:
matching `Live` edges first, then considering `ReplayOnly` edges only when no live edge matches.
Reaching the expected target does not prove that a replay-only retention edge was exercised; a
live twin may have claimed the event. Multi-event edges also attribute on the head event and then
consume the remaining events from an in-flight queue, so a useful trace must associate the whole
completed input span with one selected edge rather than report every tail event as a separate
transition.

Keiro's reachable-state conformance work needs these facts to distinguish guarded alternatives and
prove that historical witnesses actually use replay-only edges. The requesting plan is
`mori://shinzui/keiro/plans/159-generate-complete-reachable-state-holes-and-spec-behavioral-conformance`.
That artifact URI is intentional even if a local Mori registry has not yet refreshed plan
resolution.


## Requested Change

Add an additive structured-success surface in `src/Keiki/Core.hs`. Exact names may follow Keiki's
conventions, but the API must provide the following information without changing the signatures or
semantics of `step`, `stepEither`, `applyEventsEither`, `reconstituteEither`, or `replayEvents`.

For forward execution, add a detailed step operation whose successful result includes:

- the selected `EdgeRef s`;
- the resulting state and register file;
- the ordered emitted output list; and
- enough mode information to assert that forward stepping selected a `Live` edge, either directly
  on the success value or through a documented lookup from the returned edge.

The detailed operation must share the same selection and evaluation implementation as
`stepEither`. It must not re-run guard selection independently, zip a second edge enumeration, or
permit a result that can disagree with the compatibility operation.

For replay, add a strict detailed operation whose successful result includes the final settled
state/register file and an ordered attribution trace. Each trace entry identifies:

- the selected `EdgeRef s` and `EdgeMode`;
- the settled source and target states;
- the zero-based half-open input event span consumed by that edge; and
- the number of observed events in the completed output chain.

For a successful replay of zero observed events, the trace is empty and the returned state/register
file equals the seed. For a successful replay of `n > 0` observed events, the entry spans are
non-empty, ordered, and form a gap-free, overlap-free partition of `[0,n)`. The first entry starts
at `0`; every entry ends where the next begins; and the last entry ends at `n`. Each entry's event
count equals both its span length and the selected edge's declared non-empty output-word length.
The first source is the supplied settled seed, adjacent entries satisfy
`previous.target == next.source`, and the last target is the returned final state.

Each entry is internally consistent with the concrete transducer used for the call:
`edgeSource selectedRef == entry.source`, and resolving `edgeIndex` in `edgesOut t entry.source`
yields the entry's reported mode, target, and output-word length. That resolution is a law used to
check the returned witness, never an alternative way to infer attribution. These are laws of the
result type, not merely presentation conventions.

A single-event edge produces one one-event span. A multi-event edge produces exactly one completed
trace entry covering its head and tail. Replay cannot observe or attribute an output-free
(epsilon-output) edge, so such an edge produces no replay trace entry; the detailed forward step
can still identify an accepted epsilon-output edge. A chunk that ends in flight remains the
existing structured truncation failure, and no partial attribution may appear as a completed trace
entry. Live-first selection remains authoritative, and the trace must report the phase that
actually attributed the event.

The detailed replay implementation may maintain an internal trace-aware in-flight wrapper, but it
must use the same inversion, guard verification, update, output-tail evaluation, queue comparison,
and failure constructors as the released replay path. Compatibility functions should delegate to
or erase detail from the new shared implementation so the two surfaces cannot drift. Attribution
must be captured when the head event selects the edge, together with that head's input index, and
carried until its tail queue is exhausted; reconstructing an edge afterward from the target state
or another enumeration is not sound.

The detailed operations are observational refinements of the compatibility operations, not new
semantics. Erasing a detailed forward success must commute exactly with `stepEither`; erasing a
detailed strict-replay success must commute exactly with `applyEventsEither`; and both detailed
operations must preserve the corresponding `Left` value without translation or reclassification.

`EdgeRef` remains a locator within one concrete `SymTransducer` construction: source vertex plus
outgoing-edge index. Documentation must explicitly state that it is not a durable semantic ID, may
change when edge declaration order changes, and must not be persisted as an application contract.
Generators may map their own stable semantic keys to current `EdgeRef` values at build time.


## Out of Scope

- A durable or globally stable transition identifier inside Keiki.
- Domain-specific rejection or no-op reasons; Keiki's current `StepFailure` distinctions remain
  unchanged.
- Event codecs, encoded-byte spans, or persistence metadata. Keiki traces typed output values and
  typed replay input positions only.
- Attributing epsilon-output edges during replay. They consume no observed event, so the event log
  contains no evidence that can distinguish zero, one, or several such steps.
- Keiro DSL obligation derivation, witness formats, scaffold records, or conformance reports.
- Exposing register values in failure summaries or diagnostic messages.
- Changing live-first replay semantics or allowing `ReplayOnly` edges to participate in forward
  stepping.


## Acceptance

The request is complete when all of the following are demonstrated in Keiki:

1. A detailed forward success identifies the exact `EdgeRef` for each of two disjoint guarded
   siblings that share a target and produce equal output values and equal per-slot register
   observations when separate inputs select each sibling.
2. `stepEither` and the detailed step agree on every failure and on the state, per-slot register
   observations, and outputs of every success in a property test; the implementation has one
   selection/evaluation authority.
3. Detailed forward stepping identifies an accepted epsilon-output live edge, and forward stepping
   never reports a `ReplayOnly` edge.
4. Detailed replay reports a `Live` edge when both a live edge and replay-only twin can attribute
   an event, and reports the replay-only edge when no live edge can attribute it.
5. A multi-event edge produces one trace entry with the exact half-open input span; a second edge
   after it starts at the next index.
6. For every successful generated replay script, the empty-input law holds, non-empty trace spans
   partition the full input exactly, counts equal span and declared output-word lengths, entry
   metadata resolves to the selected edge, sources and targets form a path from the seed to the
   returned state, and no epsilon-output attribution is invented.
7. Queue mismatch, ambiguous inversion, no inverting edge, and truncated multi-event input retain
   the existing `ReplayFailure` index, wrapper state, and reason.
8. Erasing the detailed replay trace yields exactly the same result as `applyEventsEither` for
   successes and failures, covered by property tests over generated command/event scripts.
9. Haddocks state the local, non-durable nature of `EdgeRef`, the event-span and partition laws,
   the live-first phase rule, the unobservability of epsilon-output edges during replay, and the
   treatment of in-flight multi-event chains.
10. The capability is released on Hackage and tagged upstream so downstream projects can select a
   bound from an authoritative release rather than an unreleased checkout.


## Compatibility Baseline

The validation audit verified on 2026-07-31 that Hackage preferred-version metadata lists Keiki
`0.6.0.0`, whose published source still has the compact success surfaces described above. Public
`master`, the annotated `v0.6.0.0` tag, its GitHub release, and Hackage now agree on commit
`c8f2c343ce03f42e10de77d684769f15ad30feda`; the attribution implementation is deliberately absent
from that release. The requested APIs are additive. Implementation must repeat both
release-authority checks before choosing a later version or declaring the request released, and
must not treat a local-only tag as authoritative.


## References

- Requesting project and package: `mori://shinzui/keiro` and
  `mori://shinzui/keiro/packages/keiro-dsl`.
- Requesting ExecPlan:
  `mori://shinzui/keiro/plans/159-generate-complete-reachable-state-holes-and-spec-behavioral-conformance`.
- Keiki package: `mori://shinzui/keiki/packages/keiki`.
- Keiki implementation surface: `src/Keiki/Core.hs` (`EdgeRef`, `StepFailure`, `stepEither`,
  `InFlight`, `applyEventStreamingEither`, `replayEvents`, `applyEventsEither`, and
  `reconstituteEither`).
- Replay-only contract and tests: `CHANGELOG.md` version `0.3.0.0` and
  `test/Keiki/ReplayOnlySpec.hs`.
