# ADR-0002: Event logs must reproduce forward state

- **Status:** Accepted
- **Date:** 2026-07-13
- **Plan(s):** `docs/plans/71-align-build-time-validation-with-replay-head-recoverability-cross-edge-inversion-ambiguity-and-guard-implies-input-read-checks.md`; `docs/plans/72-structured-replay-diagnostics-reconstituteeither-strict-evolve-policy-and-multi-event-outputacceptor.md`; `docs/plans/73-decide-replay-round-trip-property-harness-across-all-fixtures.md`; `docs/plans/81-expose-detailed-step-success-and-replay-attribution-traces.md`

## Context

An event-sourced transducer has two observable executions: run a
command forward to obtain new state and events, or rebuild state from
those persisted events. Before the July 2026 review, default validation
could accept models for which those executions diverged. Examples
included state-changing output-free edges, multi-event edges whose
command was recoverable only from a tail event, and two edges that could
both invert the same head event. Replay also collapsed all failures to
`Nothing`, and the former Decider façade could retain the old state after
a failed evolve.

## Decision

For a transducer accepted by `validateTransducer
defaultValidationOptions`, replaying every complete log it produces must
reproduce its forward vertex and register file, subject to the documented
honesty laws of `InCtor` and `WireCtor`.

Default validation therefore checks head recoverability, inversion
ambiguity, constructor guards before input-field reads, and
state-changing epsilon edges in addition to hidden inputs,
determinism, and reachability. The first emitted event of a multi-event
edge must recover every required command field; tail events only verify
the already selected edge. An output-free edge may not change persisted
state.

The primary replay API is structured and `InFlight`-aware:
`applyEventStreamingEither`, `replayEvents`, `applyEventsEither`, and
`reconstituteEither`. The `Maybe` variants are compatibility wrappers.
The lossy `Keiki.Decider` façade is not part of the release API.

`stepDetailedEither`, `applyEventsDetailedEither`, and
`reconstituteDetailedEither` are proof-relevant views of those same
executions. Erasing a detailed success yields the corresponding compatibility
success, and failures are identical. Forward evidence records the exact local
outgoing edge selected by the evaluator. A successful strict replay trace is
an ordered factorization of the complete observed log into completed,
non-empty edge output words: half-open spans partition the event positions and
their sources and targets form a path to the returned state. Multi-event tails
complete the attribution selected by their head; they are not separate
transitions. Live-first inversion records the phase that actually selected the
edge.

`EdgeRef` remains local to one concrete transducer construction and changes
with outgoing declaration order. It is diagnostic evidence, not a persisted
semantic identifier. Epsilon-output edges remain unobservable during replay
because they consume no log position, though detailed forward stepping can
identify them. Compatibility and detailed replay use one event kernel for
inversion, updates, queue advancement, and failures. Compatibility supplies
pair-shaped success continuations and retains O(1) auxiliary state; only the
detailed fold carries pending metadata and O(k) entries for k completed edges.

## Consequences

- Persisted models must emit an event for every state change. Pure,
  non-persisted machines may explicitly opt out of the epsilon check.
- Runtime integrations can distinguish no inversion, ambiguous
  inversion, queue mismatch, and truncation at an exact event index.
- Multi-event schemas sometimes repeat command data in their head event
  to make streaming replay possible.
- New validation constructors and option fields are source-breaking for
  exhaustive matches and record construction; callers should update
  `defaultValidationOptions` rather than construct options positionally.
- The round-trip property suite is permanent regression evidence for
  the decision.
- Callers that need conformance evidence can distinguish guarded siblings and
  live/replay-only selection without duplicating Keiki's guards or inverter.
- Detailed replay has an explicit O(number of completed edges) metadata cost;
  compatibility hydration does not construct and erase that trace.
