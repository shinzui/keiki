---
title: "Structured event-log replay and reconstitution"
type: Capability
description: "Reconstruct aggregate state by replaying a persisted event log, with structured diagnostics that pinpoint the failing event and reason."
generated:
  by: adopt-capabilities/0.9.2
  at: "2026-08-08T00:00:00Z"
capabilityId: CAP-2
provider: mori://shinzui/keiki
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - keiki
interface:
  - Keiki.Core
requires:
  - CAP-1
evidence:
  - kind: test
    resource: test/Keiki/ReplayEitherSpec.hs
    proves: replayEvents / reconstituteEither reproduce state and return structured ReplayFailure values on bad logs.
  - kind: test
    resource: test/Keiki/CoreInFlightSpec.hs
    proves: InFlight streaming replay handles event-by-event hydration through multi-event edges.
  - kind: test
    resource: test/Keiki/ReplayOnlySpec.hs
    proves: ReplayOnly edges invert stored events without being taken by forward stepping.
  - kind: test
    resource: test/Keiki/CoreApplyEventsSpec.hs
    proves: Atomic chunk replay respects command boundaries.
---

# Structured event-log replay and reconstitution

Event sourcing and durable execution both rest on the same operation: fold a
persisted log back into current state. keiki inverts a transducer's output
relation to recover the forward transitions a log implies, then replays them.
This is the hydration half of the library; the forward half is
[CAP-1](typed-transducer-core.md).

## What you adopt

- **Replay entry points**: `applyEvent` (letter-only), `applyEventStreaming` /
  `applyEventStreamingEither` (`InFlight`-aware, for multi-event edges),
  `applyEvents` / `applyEventsEither` (atomic chunk replay over command
  boundaries), `replayEvents`, and `reconstituteEither`.
- **Structured diagnostics**: `ReplayStepFailure`, `ReplayFailureReason`, and
  `ReplayFailure` identify the failing event index, wrapper state, and exact
  reason — failed or ambiguous inversion, an unexpected queued event, or a
  truncated multi-event chain.
- **Guard evolution for logs** (since 0.3.0.0): `EdgeMode` (`Live` /
  `ReplayOnly`) and `Keiki.Builder.replayOnly`. A `ReplayOnly` twin retains the
  removed region of a tightened guard so events stored under the old rule still
  have an inverting edge. Inversion is two-phase, judging ambiguity within the
  phase that produced candidates.
- **Attribution** (since 0.7.0.0): `applyEventsDetailedEither` /
  `reconstituteDetailedEither` expose an ordered, half-open span factorization of
  a successful replay.

## Shortest real usage

```haskell
reconstituteEither transducer initialVertex emptyRegFile eventLog
  :: Either ReplayFailure (vertex, RegFile rs)
```

## Limits

- **`since` is the earliest form, not the current one.** Replay shipped in
  0.1.0.0 as `Maybe`-returning functions; the structured `Either` surface named
  above became primary in 0.2.0.0 (the `Maybe` functions are now compatibility
  wrappers), and `ReplayOnly` edges arrived in 0.3.0.0. A consumer pinning
  0.1.0.0 gets replay but not the structured diagnostics this record documents.
- **Replay-safety is not automatic.** Recoverability of a log is a property the
  transducer must be validated for; the static gate that proves it is a separate
  capability, `CAP-3`. Hidden command inputs,
  ambiguous inversion, and non-injective output shapes make a log unrecoverable
  and must be caught before a transducer reaches a durable boundary.
- **Deleting a deployed `ReplayOnly` twin re-creates the break it fixed.** Only
  remove a twin once every stream containing the region's events is terminal or
  truncated.
- Derived event fields rely on the recompute-and-verify path
  (`test/Keiki/RecomputeVerifySpec.hs`); they are not free-form invertible.
