---
type: Improvement Request
title: Provide a sanctioned event schema-evolution path for structural wires
description: >-
  Research and document an official upcasting/schema-evolution recipe so events persisted
  under an older event shape replay under the current transducer, now that ExecPlan 87's
  structural matching removes the (unsound) custom-Eq trick consumers could otherwise reach
  for.
timestamp: 2026-08-04T20:00:00Z
requestId: IR-7
status: proposed
origin: mori://shinzui/keiki
---

# Improvement Request: Provide a Sanctioned Event Schema-Evolution Path for Structural Wires

## Status

Proposed. Requires an ExecPlan-86-style research phase before implementation planning; it
must not begin against the pre-ExecPlan-87 representation.

## Context

ExecPlan 87 makes trusted wire matching structural: generated nullary wires move from
`Eq`-mediated matching (`mkWireCtor0`) to Generic structural matching (`mkWireCtor0Via`),
and trusted schemas are non-forgeable. A deliberate consequence, recorded in that plan's
Decision Log, is that a quotienting custom `Eq` instance no longer influences `wcMatch`.
That was the only mechanism — an unsound one, violating the documented `wcMatch` honesty
law — by which a consumer could make a legacy event value match a current wire.

With two active applications now and twenty-plus planned, long-lived event logs will
outlast event-type definitions. Adopters will need to rename constructors, add fields with
defaults, and split or merge events while old log entries still replay.
[ADR-0005](../adr/0005-persisted-wire-identities-are-explicit-and-versioned.md) already
separates persisted wire-kind strings from typed replay evidence, and
`docs/research/schema-evolution.md` sketches the design space, but there is no end-to-end,
recommended recipe. Without one, each adopting team will improvise — and the improvised
paths (custom `Eq`, dishonest `wcMatch`, codec-side rewriting without invariants) are
exactly the ones the structural boundary exists to prevent.

## Requested Change

Research, decide, and document one sanctioned schema-evolution path for Keiki event logs,
covering at least: constructor rename, field addition with default, field removal, and
event split/merge. Candidate shapes include versioned persisted wire identities plus an
explicit typed upcast step applied before replay, or codec-level migration in
`keiki-codec-json` with recorded invariants. The chosen path must:

- never weaken structural matching or reintroduce name/`Eq`-based match evidence;
- preserve ADR-0002's guarantee that produced logs reproduce forward state, stating
  explicitly what is guaranteed for upcast logs;
- state its interaction with replay inversion: whether upcasting happens before
  `solveOutput` sees the event, and what evidence survives;
- be exercised by at least one worked example in the repository.

If research concludes that part of the mechanism belongs in Keiro or in application codecs
rather than Keiki, record that boundary here and file the corresponding downstream request
rather than stretching Keiki's core.

## Acceptance

1. A research note in `docs/research/` compares the candidate mechanisms against real
   evolution scenarios and records a decision with rationale.
2. A follow-up ExecPlan (or an explicit decision not to change code) exists, and this
   request's status reflects it.
3. Documentation gives adopters a copyable recipe for each covered evolution scenario, and
   names the anti-patterns (custom `Eq` quotienting, dishonest `wcMatch`) with the reason
   they are rejected.
4. ADR-0002 and ADR-0005 are amended or explicitly reaffirmed by the outcome.

## Out of Scope

- Weakening the trusted-schema boundary or the `wcMatch` honesty law.
- General-purpose data migration tooling unrelated to event replay.
- The 0.9/0.11 release line itself; this request targets the release after the structural
  boundary is stable unless research finds a cheap documentation-only first step.

## Compatibility Baseline

Filed against the local working tree at Keiki 0.8.0.0 (commit `6fbce40`) with ExecPlans 87
and 85 accepted but not yet implemented. The request assumes the post-87 structural
representation as its starting point.

## References

- Structural boundary and custom-`Eq` tightening:
  `mori://shinzui/keiki/plans/87-add-structural-wire-schemas-for-optional-symbolic-replay-inversion`.
- Design-space sketch: `docs/research/schema-evolution.md`.
- Governing decisions:
  [ADR-0002](../adr/0002-event-logs-must-reproduce-forward-state.md),
  [ADR-0005](../adr/0005-persisted-wire-identities-are-explicit-and-versioned.md).
- Codec surface: `mori://shinzui/keiki/packages/keiki-codec-json`.
