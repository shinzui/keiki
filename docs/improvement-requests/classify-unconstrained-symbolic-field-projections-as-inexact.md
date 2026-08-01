---
type: Improvement Request
title: Classify unconstrained symbolic field projections as inexact
description: >-
  Stop reporting one-way field projections as exact symbolic translations when the solver can
  invent projected values that no concrete owner can produce.
timestamp: 2026-08-01T03:52:03Z
requestId: IR-3
status: implemented
origin: mori://shinzui/keiro
plan: docs/plans/82-classify-unconstrained-symbolic-field-projections-conservatively.md
reviews:
  - kind: model
    reviewer: codex
    reviewed_at: 2026-08-01T00:14:56Z
    document_timestamp: 2026-08-01T00:14:56Z
    scope: technical-accuracy
    outcome: approved
    provider: openai
    model: gpt-5
    effort: unspecified
    context: >-
      Reviewed against Keiki 0.6.0.0 FieldProjection, symbolic translation, exactness
      classification, projection extraction, and finite-carrier counterexamples discovered while
      validating Keiro nominal enum equality.
---

# Improvement Request: Classify Unconstrained Symbolic Field Projections as Inexact

## Status

**Implemented.** ExecPlan 82 now classifies every projection created by the released one-way
`fieldWitness` as inexact, preserves path-stable conservative emptiness proofs, and concretely
rechecks every `symSatExt` candidate before returning it. The focused projection and verification
suites, all repository tests and builds, native flake checks, and strict OKF validation pass. The
change is recorded under Unreleased; publication is separate release work. This request remains
deliberately smaller than
[IR-4](support-domain-constrained-symbolic-field-projections-with-reconstructible-witnesses.md),
which supplies the richer domain contract needed for selected projections to regain exactness.

## Context

[IR-1](support-typed-symbolic-field-projections-over-mapped-consumer-values.md) introduced
`FieldProjection`, `FieldWitness`, and `TFieldProj`. Concrete evaluation applies the declared total
getter. Symbolic translation does something weaker: it allocates a memoized free variable of the
projection result type. `FieldProjection` does not describe the getter's image, and the symbolic
environment cannot reconstruct an owner from the projected result.

That implementation is a sound over-approximation for some analyses, but it is not an exact
translation for a non-surjective getter. A finite two-constructor enum projected to `Text`, for
example, has two concrete keys. An unconstrained symbolic `Text` can satisfy `x /= first && x /=
second` with a third value that no enum owner can produce. Similar counterexamples exist for
validated ID text, bounded numeric fields, and normalized projections.

Despite that gap, `predicateTranslationExact` currently returns `True` for every `TFieldProj` whose
result carrier is in Keiki's symbolic registry. `verifyPredicate` may therefore return
`VerifiedSatisfiable` for a predicate that has no concrete projected witness. Projection variables
are also deliberately absent from `symSatExt`, so the claimed result cannot be checked by
reconstructing a concrete owner.

Keiro discovered this while validating nominal ID and enum equality for
`mori://shinzui/keiro/okf/improvement-requests/concepts/IR-12`. Treating a nominal enum as a
`Text` projection would make aggregate syntax compile while overstating what Keiki proved.

## Requested Change

Make exactness depend on evidence that a projection's symbolic domain matches the concrete getter's
image. A `TFieldProj` backed only by today's one-way `FieldProjection` contract must not make
`predicateTranslationExact` return `True`.

The compatibility translator may continue using a memoized free symbolic result as a conservative
over-approximation. The structured verification surface must distinguish that outcome from an
exact proof. Keiki may reuse `UnverifiedOpaque` or add a more specific additive result such as
`UnverifiedProjectionDomain`; the public result must never be `VerifiedSatisfiable` or
`VerifiedUnsatisfiable` solely on the strength of an unconstrained one-way projection.

Repeated reads must retain their current path identity. This request does not make projections
opaque applications: `proj x == proj x` should still share one symbolic variable, concrete
evaluation still uses the getter, and projection diagnostics still name the structural path. The
repair changes the strength attributed to the symbolic result, not projection evaluation or memo
identity.

When IR-4 later supplies exact domain evidence, those projections may regain exact verification.
The exactness test must therefore be expressed in terms of projection evidence rather than a
permanent blanket rejection of `TFieldProj`.

The same distinction applies to `symSatExt`. Because its current model reader does not reconstruct
projection owners, it must concretely re-evaluate every candidate before returning `Just`. An
unrealizable projection assignment yields `Nothing`, which remains “no witness recovered” and must
not be interpreted as proof of unsatisfiability.

## Acceptance

1. A finite owner projected into a larger scalar carrier has a regression test where the
   unrestricted symbolic carrier finds a spurious value; `verifyPredicate` reports the result as
   unverified rather than verified satisfiable.
2. `predicateTranslationExact` returns `False` for a projection carrying only the released
   one-way contract.
3. Concrete `evalTerm`, repeated-read memoization, dotted projection paths, hidden-input checks,
   replay behavior, and `ProjectionResultUnsupported` diagnostics retain their documented
   behavior.
4. Compatibility solver operations that intentionally accept over-approximation document it and
   do not silently flow into an exact-verification gate.
5. Tests pin the distinction between unsupported result carriers, supported-but-unconstrained
   projection carriers, opaque `TApp` terms, and ordinary exact scalar terms.
6. Release notes identify the prior `predicateTranslationExact` result as an overclaim and explain
   how callers can detect the corrected outcome.
7. Every pair returned by `symSatExt` satisfies concrete `models`; a free projection value that
   disagrees with the reconstructed default owner is discarded without affecting `symIsBot`.

## Out of Scope

- Defining finite, validated-text, or other exact projection domains; IR-4 owns that capability.
- Keiro DSL syntax, nominal binding, fingerprints, or generated projection instances.
- Changing concrete predicate semantics or rejecting `FieldProjection` from ordinary evaluation.
- Treating an arbitrary `Eq` instance as symbolic-domain evidence.

## Compatibility Baseline

The requesting audit verified Keiki 0.6.0.0 against the authoritative Hackage release and upstream
tag. Implementation must repeat that registry/tag check before selecting a release number or
dependency bound.
