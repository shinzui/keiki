---
type: Improvement Request
title: Gate the opt-in symbolic inversion checker in consumer CI
description: >-
  Ship a documented, copyable CI gate recipe for ExecPlan 87's opt-in symbolic
  replay-inversion checker so its output-dependent precision is actually exercised by
  adopters, with explicit behavior when z3 is unavailable.
timestamp: 2026-08-04T20:00:00Z
requestId: IR-8
status: proposed
origin: mori://shinzui/keiki
---

# Improvement Request: Gate the Opt-In Symbolic Inversion Checker in Consumer CI

## Status

Proposed. Blocked on ExecPlan 87 delivering `checkInversionAmbiguitySym`; the recipe work
itself is small and should land in the first release after the 0.9/0.11 line.

## Context

ExecPlan 87 deliberately keeps the full symbolic replay-inversion checker out of
`validateTransducer`: default validation stays pure, microsecond-scale, and z3-free per
[ADR-0003](../adr/0003-proof-gates-fail-conservatively.md). The consequence is that the
checker's output-dependent precision only materializes where a consumer explicitly calls
`checkInversionAmbiguitySym` in its own test or CI gate with a supported solver installed.
Keiki's own spec exercises it, but nothing tells the twenty-plus planned application
adopters how to wire it into their gates, and nothing defines what a gate should do when
z3 is missing from the environment.

An undefined missing-solver policy is the sharp edge: a gate that silently passes without
z3 reads as "proved" when nothing ran, while one that hard-fails makes solver installation
a hidden build dependency for every consumer.

## Requested Change

- Add a documented, copyable recipe — a `just` target in Keiki plus a documentation page —
  for running the opt-in checker as a distinct CI gate: which function to call, how to
  select the transducers to check, and how to read the detailed result.
- Define the missing-solver policy explicitly: the gate must distinguish "checked and
  clean", "checked and findings remain", and "not checked (no solver)", and must never
  report the third state as the first. Recommended default: skip loudly with a visible
  notice locally, fail in CI environments that declare the solver required.
- Provide guidance (or a scaffolded gate) for Keiro-generated projects, in coordination
  with Keiro's conformance surface; if the consumer-facing half belongs in Keiro, file the
  corresponding Keiro request and record the split here.

## Acceptance

1. A fresh consumer can add the gate by copying a documented recipe, without reading
   Keiki's own test suite.
2. Running the gate without z3 produces an explicit not-checked outcome that cannot be
   mistaken for a clean pass, in both local and CI modes.
3. Keiki's repository runs the recipe itself (outside default `cabal test` if needed) so
   the documented commands cannot rot.
4. The Keiro-side ownership decision is recorded, with a filed Keiro request if the
   scaffolded gate lands there.

## Out of Scope

- Adding the checker to `validateTransducer` or `ValidationOptions` (rejected by ExecPlan
  87's design; ADR-0003).
- Changing the checker's API or verdicts.
- Solver distribution/packaging beyond documenting the requirement.

## Compatibility Baseline

Filed against the local working tree at Keiki 0.8.0.0 (commit `6fbce40`) with ExecPlan 87
accepted but not yet implemented; the referenced checker API is that plan's pinned
interface.

## References

- Checker and its deliberate opt-in boundary:
  `mori://shinzui/keiki/plans/87-add-structural-wire-schemas-for-optional-symbolic-replay-inversion`.
- Fail-conservative policy:
  [ADR-0003](../adr/0003-proof-gates-fail-conservatively.md).
- Keiro adoption surface: `mori://shinzui/keiro/packages/keiro-dsl`.
