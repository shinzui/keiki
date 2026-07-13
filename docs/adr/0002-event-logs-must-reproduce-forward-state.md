# ADR-0002: Event logs must reproduce forward state

- **Status:** Accepted
- **Date:** 2026-07-13
- **Plan(s):** `docs/plans/71-align-build-time-validation-with-replay-head-recoverability-cross-edge-inversion-ambiguity-and-guard-implies-input-read-checks.md`; `docs/plans/72-structured-replay-diagnostics-reconstituteeither-strict-evolve-policy-and-multi-event-outputacceptor.md`; `docs/plans/73-decide-replay-round-trip-property-harness-across-all-fixtures.md`

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
