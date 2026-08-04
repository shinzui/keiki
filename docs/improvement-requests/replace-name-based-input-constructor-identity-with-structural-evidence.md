---
type: Improvement Request
title: Replace name-based input-constructor identity with structural evidence
description: >-
  Give InCtor typed structural identity so composition substitution and symbolic constructor
  reasoning stop trusting icName string equality and the unsafeCoerceTerm it currently
  authorizes, mirroring the trusted wire-schema evidence ExecPlan 87 adds for output heads.
timestamp: 2026-08-04T20:40:48Z
requestId: IR-6
status: planned
origin: mori://shinzui/keiki
---

# Improvement Request: Replace Name-Based Input-Constructor Identity With Structural Evidence

## Status

Planned. Implementation is specified by ExecPlan 88
(`docs/plans/88-add-structural-input-constructor-evidence-for-composition-and-symbolic-alignment.md`),
sequenced after ExecPlans 87 and 85. It lands locally without selecting a release line or
migrating adopters; a future user-authored release plan owns that coordinated rollout after all
breaking Keiki ExecPlans are complete.

## Context

Keiki 0.8.0.0 describes an input command constructor with `InCtor ci ifs` in
`src/Keiki/Core.hs`: a diagnostic `icName` string plus consumer-owned `icMatch`/`icBuild`
closures over a typed slot schema. Nothing ties the name to the constructor the closures
actually handle.

Two soundness-adjacent boundaries currently trust that name:

1. Composition substitution. `substInputField` in `src/Keiki/Composition.hs` accepts a
   t2-side field read whenever `icName ic2 == wcName wc1`, then realigns the substituted
   term with `unsafeCoerceTerm`, justified only by the assumption that the name-matched
   constructor mirrors the `OutFields` tuple shape. `composeGuard` likewise rewrites a
   `PInCtor` guard to `PTop` on the same name match. An accidental name collision between
   structurally different constructors is silently accepted and coerced rather than
   rejected.
2. Symbolic translation. `Keiki.Symbolic` translates `PInCtor` to
   `seInputCtor .== literal (icName ic)`, making the name string the symbolic identity of
   the constructor. Two distinct constructors sharing a diagnostic name are conflated into
   one symbolic tag, and mutual exclusion between differently named constructors is
   assumed from the strings rather than witnessed structurally.

[ADR-0001](../adr/0001-structural-re-indexing-for-sound-replay.md) forbids names and casts
as replay evidence, and
[ADR-0004](../adr/0004-composition-uses-snapshot-updates-and-checked-boundaries.md)
requires composition to preserve proof evidence only at checked structural boundaries.
ExecPlan 87 closes exactly this hazard class for output heads by adding non-forgeable
`WireSchema` evidence to `WireCtor`; input constructors are the remaining name-trusting
boundary. Closing the input side before any coordinated release lets adopters migrate once to
the final structural surface chosen after all breaking ExecPlans are complete.

## Requested Change

Give `InCtor` typed structural evidence equivalent in trust and non-forgeability to
ExecPlan 87's `WireSchema`: an abstract trusted Generic constructor path plus a typed slot
spine, produced only by trusted Generic/Template Haskell producers, with an explicit
unavailable value for manual closure construction. Then consume it at both boundaries:

- Composition substitution accepts a field substitution only through a checked structural
  alignment between the t1 wire and the t2 input constructor. Name equality alone must
  never authorize `unsafeCoerceTerm`; an unwitnessed or mismatched alignment must produce
  a loud structural diagnostic (or an unsatisfiable poison leaf), never a coerced term.
- Symbolic `PInCtor` identity comes from structural evidence when both constructors carry
  it, with the name string only as a fallback for unwitnessed constructors. The fallback
  must keep conservative polarity: conflation may only widen results (retain warnings and
  overlap reports), never manufacture mutual exclusion or disjointness.

Runtime stepping and replay semantics must not change. The shared structural-path
abstraction should be reused from, not duplicated beside, ExecPlan 87's representation.

## Acceptance

1. Two distinct trusted input constructors with equal diagnostic names are not conflated
   by the symbolic translator: their `PInCtor` conjunction is unsatisfiable, and
   determinism/inversion analyses treat them as different constructors.
2. A composition whose t2-side `InCtor` name-collides with a structurally different t1
   wire produces a structural diagnostic instead of an `unsafeCoerceTerm`-realigned term;
   correctly shaped compositions behave exactly as before and all composition, category,
   choice, and profunctor law suites pass unchanged.
3. Trusted input-constructor evidence cannot be forged through the public API; manual
   `InCtor` construction states its unavailability explicitly.
4. Unwitnessed constructors preserve current name-based behavior where it is conservative
   and lose it where it is not: no analysis suppresses a warning or authorizes a coercion
   from name equality alone.
5. The source break lands and is verified locally without changing package versions, bounds,
   or dependent repositories; the future release plan migrates consumers only after the full
   breaking surface is complete.

## Out of Scope

- The output-head `WireCtor`/`WireSchema` representation and solver (owned by ExecPlan 87).
- The pure shared-register disjointness proof (owned by ExecPlan 85 / IR-5).
- Persisted wire identities and codec-level naming
  ([ADR-0005](../adr/0005-persisted-wire-identities-are-explicit-and-versioned.md)).
- Version selection, Keiro/application migration, and release work (owned by the future
  user-authored Keiki release plan after all breaking ExecPlans are complete).

## Compatibility Baseline

Verified against the local working tree at Keiki 0.8.0.0 (commit `6fbce40`) and the
matching Hackage 0.8.0.0 release. `InCtor` is a public record-syntax GADT, so adding
evidence is a source-breaking change. No release version is selected here; the future release
plan will choose one after all breaking ExecPlans are complete.

## References

- Implementing plan:
  `docs/plans/88-add-structural-input-constructor-evidence-for-composition-and-symbolic-alignment.md`.
- Prerequisite structural boundary:
  `mori://shinzui/keiki/plans/87-add-structural-wire-schemas-for-optional-symbolic-replay-inversion`.
- Keiki implementation: `src/Keiki/Core.hs` (`InCtor`), `src/Keiki/Composition.hs`
  (`substInputField`, `composeGuard`), `src/Keiki/Symbolic.hs` (`seInputCtor`, `PInCtor`
  translation).
- Governing decisions: [ADR-0001](../adr/0001-structural-re-indexing-for-sound-replay.md),
  [ADR-0004](../adr/0004-composition-uses-snapshot-updates-and-checked-boundaries.md).
