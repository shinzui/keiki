---
type: Improvement Request
title: Expose successful edge attribution for forward stepping and structured replay
description: >-
  Add structured success APIs that identify the selected edge during forward stepping and each
  completed edge attribution during replay, without duplicating Keiki's evaluator or changing the
  existing compatibility entry points.
timestamp: 2026-07-31T20:03:30Z
requestId: IR-2
status: proposed
origin: mori://shinzui/keiro
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
---

# Improvement Request: Expose Successful Edge Attribution for Forward Stepping and Structured Replay

## Status

Proposed for the next additive Keiki API release. Keiro must not infer a selected transition from
its target or emitted values while this capability is absent.


## Context

Keiki `0.5.0.0` has strong structured failure information but deliberately compact success
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

A single-event edge produces one one-event span. A multi-event edge produces exactly one completed
trace entry covering its head and tail. A chunk that ends in flight remains the existing structured
truncation failure; it must not emit a completed trace entry for the partial edge. Live-first
selection remains authoritative, and the trace must report the phase that actually attributed the
event.

The detailed replay implementation may maintain an internal trace-aware in-flight wrapper, but it
must use the same inversion, guard verification, update, output-tail evaluation, queue comparison,
and failure constructors as the released replay path. Compatibility functions should delegate to
or erase detail from the new shared implementation so the two surfaces cannot drift.

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
- Keiro DSL obligation derivation, witness formats, scaffold records, or conformance reports.
- Exposing register values in failure summaries or diagnostic messages.
- Changing live-first replay semantics or allowing `ReplayOnly` edges to participate in forward
  stepping.


## Acceptance

The request is complete when all of the following are demonstrated in Keiki:

1. A detailed forward success identifies the exact `EdgeRef` for each of two disjoint guarded
   siblings that share a target and output constructor when separate inputs select each sibling.
2. `stepEither` and the detailed step agree on every failure and on the state, per-slot register
   observations, and outputs of every success in a property test; the implementation has one
   selection/evaluation authority.
3. Forward stepping never reports a `ReplayOnly` edge.
4. Detailed replay reports a `Live` edge when both a live edge and replay-only twin can attribute
   an event, and reports the replay-only edge when no live edge can attribute it.
5. A multi-event edge produces one trace entry with the exact half-open input span; a second edge
   after it starts at the next index.
6. Queue mismatch, ambiguous inversion, no inverting edge, and truncated multi-event input retain
   the existing `ReplayFailure` index, wrapper state, and reason.
7. Erasing the detailed replay trace yields exactly the same result as `applyEventsEither` for
   successes and failures, covered by property tests over generated command/event scripts.
8. Haddocks state the local, non-durable nature of `EdgeRef`, the event-span convention, the
   live-first phase rule, and the treatment of in-flight multi-event chains.
9. The capability is released on Hackage and tagged upstream so downstream projects can select a
   bound from an authoritative release rather than an unreleased checkout.


## Compatibility Baseline

The requesting audit verified on 2026-07-31 that Hackage preferred-version metadata lists Keiki
`0.5.0.0` and upstream tag `v0.5.0.0` dereferences to commit
`3250780cffa1397cb320ebae69a326ee7554685f`. The requested APIs are additive. Implementation must
repeat both release-authority checks before choosing a version or declaring the request released.


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
