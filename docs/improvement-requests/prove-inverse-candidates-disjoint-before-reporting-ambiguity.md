---
type: Improvement Request
title: Prove inverse candidates disjoint before reporting inversion ambiguity
description: >-
  Make inversion-ambiguity validation suppress a same-head warning only when Keiki can soundly
  prove that the reconstructed candidates' guards cannot both hold, while retaining conservative
  warnings for opaque or unproved pairs.
timestamp: 2026-08-04T16:24:05Z
requestId: IR-5
status: proposed
origin: mori://shinzui/mori
reviews:
  - kind: model
    reviewer: codex
    reviewed_at: 2026-08-04T16:24:05Z
    document_timestamp: 2026-08-04T16:24:05Z
    scope: technical-accuracy
    outcome: approved
    provider: openai
    model: gpt-5
    effort: unspecified
    context: >-
      Reviewed against Keiki 0.8.0.0 inversion, replay-attribution, guard-evaluation, and validation
      code; Mori's Workflow transducer supplies the concrete same-head, disjoint-register-guard
      reproducer.
---

# Improvement Request: Prove Inverse Candidates Disjoint Before Reporting Inversion Ambiguity

## Status

Proposed as a soundness-preserving precision improvement to Keiki's default validation.

## Context

Keiki 0.8.0.0 reports `InversionAmbiguity` whenever two same-mode outgoing edges have the same
first wire-constructor name, unless either guard is literal bottom. The implementation in
`src/Keiki/Core.hs` deliberately does not inspect whether the two candidates' guards can both hold
after each head output is inverted back into its command.

That conservative rule catches real replay ambiguity, but it also reports pairs that replay can
prove unique from register predicates. The motivating case is
`mori://shinzui/mori/plans/176-rewrite-the-workflow-aggregate-with-real-step-completion-and-causation`.
Mori's non-final and final step commands both emit `WorkflowStepCompleted` or
`WorkflowStepFailed` first. Their reconstructed commands are different constructors, while their
state guards require respectively `openSteps > 1` and `openSteps == 1`. Those predicates are
disjoint for every register file, so replay always has one candidate, yet default validation
returns two `InversionAmbiguity` warnings.

Disabling the whole inversion check at an event-stream boundary loses useful coverage for every
other edge pair. Downstream exact-warning tests limit that risk, but the producer can give a
stronger answer when disjointness is structurally provable.

## Requested Change

Refine `inversionAmbiguityWarnings` so it reports a same-head, same-mode pair unless Keiki can
soundly prove that no register file and observed head event can make both reconstructed candidates
eligible.

The proof must model replay's actual candidate semantics:

- invert the shared observed head independently through each edge's `OutTerm`;
- evaluate each edge guard against the same pre-event register file and its own reconstructed
  command;
- account for the output inversion constraints that determine reconstructed command fields; and
- prove the conjunction of both candidate conditions unsatisfiable before suppressing the
  warning.

It is acceptable to begin with a deliberately small pure fragment that proves register-only
comparisons such as `x > n` versus `x == n`. Unknown, opaque, unsupported, or solver-failure cases
must remain warnings. A proof must never be inferred merely from different input constructors:
one observed event may reconstruct a different command for each edge, so both top-level
constructor guards can hold in their respective candidate evaluations.

Preserve the existing live/replay-only phase distinction, literal-bottom exemption, head-only
streaming inversion rule, and structured `InversionAmbiguity` diagnostic. If a new structured
proof or uncertainty result is exposed, keep the existing validation API source-compatible.

## Acceptance

1. A fixture matching Mori Workflow's shape—same source, same mode, same head wire constructor,
   different reconstructed command constructors, and register guards `openSteps > 1` versus
   `openSteps == 1`—produces no `InversionAmbiguity` warning.
2. Replacing the second guard with `openSteps > 0` restores the warning because the candidates
   overlap at `openSteps > 1`.
3. Opaque `TApp` guard fragments, unsupported terms, and solver-unknown/failure results retain the
   warning; the analysis has no unsound "probably disjoint" outcome.
4. Different input constructors alone do not suppress a same-head warning.
5. Cross-mode pairs remain exempt because live-first replay attribution already separates them;
   same-mode replay-only pairs receive the same disjointness treatment as live pairs.
6. Property tests compare every suppressed pair against concrete candidate evaluation over a
   bounded generated domain and find no state/event with two candidates.
7. Haddocks explain that warning suppression is a proof of candidate disjointness, not a claim
   that equal head names are generally safe.
8. The change is released on Hackage and tagged upstream so Keiro and Mori can adopt it from an
   authoritative version.

## Out of Scope

- Changing live-first replay semantics or permitting ambiguous replay.
- Treating multi-event tails as inversion keys; streaming replay still inverts only the head.
- Suppressing warnings from reachability evidence alone when candidate overlap remains possible.
- A general theorem prover for opaque Haskell predicates.
- Keiro DSL syntax or generated validation-policy configuration; that is tracked by
  `mori://shinzui/keiro/okf/improvement-requests/concepts/IR-17`.

## Compatibility Baseline

The request was verified against Hackage Keiki 0.8.0.0 and the matching public `v0.8.0.0` tag.
That release's `inversionAmbiguityWarnings` compares edge mode, literal-bottom status, and head
wire-constructor name only. The requested behavior is an additive validation-precision change;
runtime stepping and replay semantics remain unchanged.

## References

- Requesting initiative:
  `mori://shinzui/mori/masterplans/23-extend-functional-keiki-aggregates-to-every-mori-domain`.
- Reproducer and consumer acceptance:
  `mori://shinzui/mori/plans/176-rewrite-the-workflow-aggregate-with-real-step-completion-and-causation`.
- Keiki package: `mori://shinzui/keiki/packages/keiki`.
- Keiki implementation: `src/Keiki/Core.hs` (`solveOutput`, replay candidate selection,
  `inversionAmbiguityWarnings`, and `validateTransducer`).
- Keiki tests: `test/Keiki/ReplayOnlySpec.hs` and
  `test/Keiki/ValidationReplayAlignmentSpec.hs`.
