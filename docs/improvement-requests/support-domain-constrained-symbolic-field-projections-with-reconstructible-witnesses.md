---
type: Improvement Request
title: Support domain-constrained symbolic field projections with reconstructible witnesses
description: >-
  Let a declaration-scoped projection describe its exact symbolic image and reconstruct concrete
  owners so finite enums and validated identifiers receive truthful proofs and counterexamples.
timestamp: 2026-08-01T04:37:32Z
requestId: IR-4
status: implemented
origin: mori://shinzui/keiro
plan: docs/plans/83-add-exact-reconstructible-symbolic-field-projection-domains.md
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
      Reviewed against Keiki 0.6.0.0 projection identity and solver APIs plus Keiro IR-12/IR-14;
      selected declaration-tagged exact domains and reconstruction over a global owner-type
      equality class.
---

# Improvement Request: Support Domain-Constrained Symbolic Field Projections with Reconstructible Witnesses

## Status

**Implemented.** ExecPlan 83 adds a backend-neutral exact-domain algebra,
`ExactFieldProjection`/`exactFieldWitness`, executable declaration laws, predicate-wide relational
exactness reporting, checked path-local model reconstruction, and shared detailed verification and
transducer-analysis results. The finite, conflicting-view, broken-inverse, under-declared-domain,
and complete TypeID-v7-shaped boundary fixtures pass, as do all Cabal tests/builds, native flake
checks, strict OKF validation, formatting, and whitespace checks. The change is recorded under
Unreleased; Hackage publication and the upstream tag remain separate release work and must precede
any downstream dependency-floor increase.

**Previously planned.** Accepted as the upstream prerequisite for exact nominal equality in Keiro
and specified by
[ExecPlan 83](../plans/83-add-exact-reconstructible-symbolic-field-projection-domains.md).
IR-3's conservative classification repair established the compatibility baseline that this request
selectively promotes through explicit evidence.

## Context

The released `FieldProjection` contract is intentionally one-way: a coherent projection tag names
a total getter from an owner to a symbolic result. `TFieldProj` memoizes the result by typed path,
but the solver sees the entire result carrier rather than the getter's concrete image and
`symSatExt` cannot reconstruct projected owners.

That is insufficient for finite or validated nominal domains. An enum projected to its wire `Text`
needs a finite membership constraint. A prefix-bearing ID projected to `Text` needs the declared
prefix, separator, suffix, normalization, and length domain. Without those constraints the solver
can invent impossible values; without reconstruction a reported model cannot become a concrete
counterexample.

Keiro needs this capability for
`mori://shinzui/keiro/okf/improvement-requests/concepts/IR-12` and
`mori://shinzui/keiro/okf/improvement-requests/concepts/IR-14`. Keiro's checked graph owns the
nominal declaration and its evolution metadata. Keiki should provide a domain-neutral exact
projection mechanism rather than learn Keiro-specific IDs or enums.

## Requested Change

Add a declaration-scoped exact projection witness, or an equivalent extension of
`FieldProjection`, that supplies all of the following as one coherent contract:

- a total projection from the concrete owner to a supported symbolic key;
- a symbolic-domain description whose satisfying keys are exactly the projection image;
- a partial reconstruction from a symbolic key to a concrete owner, successful for every
  domain-valid key; and
- stable projection identity suitable for memoization, diagnostics, and generated conformance.

The contract must be indexed by the projection tag, not solely by the owner or result type. Two
declarations may use the same Haskell owner and `Text` result while having different finite or
prefix domains. Normal typeclass coherence over the owner type alone would collapse those distinct
schema authorities.

The domain description must be declarative enough for Keiki to translate without executing an
opaque predicate. The minimum acceptance surface covers:

1. an unrestricted carrier when the projection is a total isomorphism onto the whole carrier;
2. a finite non-empty set for closed enums and other finite domains; and
3. a validated textual domain capable of expressing the versioned TypeID-style prefix contract
   requested by Keiro, without hard-coding Keiro declaration types into Keiki.

Exact translation allocates or reuses the projection variable, applies its domain constraint once
per memoized path, and translates equality structurally. `predicateTranslationExact` returns true
only when every projection has exact domain evidence and every other predicate node is exact.
Solver results must not be called exact if a domain form cannot be translated by the active
backend.

Per-projection evidence is necessary but not sufficient for predicate-wide exactness. Two exact
projection tags over the same owner path may describe correlated fields, while independent solver
variables admit key pairs that no single owner realizes. A direct symbolic read of an owner and a
projection from that owner has the same missing relation. The first implementation must therefore
classify a predicate as exact only when each owner path has at most one nominal projection view
(which may be repeated) and is not also read directly. Alternatively, a future implementation may
accept several views only when it carries an explicit exact joint owner-domain relation and can
reconstruct one owner satisfying every view. Domain evidence alone must never imply joint
realizability.

Detailed satisfiability and transducer-analysis results must expose enough typed projection-model
information for a caller to reconstruct and attribute a concrete value. Reconstruction failure for
a supposedly domain-valid model is a contract violation surfaced explicitly, not a dropped field
or an invented default. Compatibility APIs may erase this detail, but the detailed operation and
the compatibility operation must share one translation and solving implementation.

Keiki cannot prove an arbitrary hand-written getter or inverse lawful. It must publish the laws and
test helpers; generators such as Keiro supply schema provenance and mutation tests. Required laws
include:

```haskell
domainAccepts (toKey owner)
domainAccepts key == isJust (fromKey key)
toKey <$> fromKey key == Just key -- for every domain-valid key
```

`fromKey` may return a canonical owner when the concrete owner contains data that the projection
does not preserve. If a consumer additionally defines equality of owners through the key, it must
establish injectivity and the stronger law `fromKey (toKey owner) == Just owner`. Keiki's exact
projection result proves predicates over the projected key; it must not silently promote a
normalizing or many-to-one getter into equality of complete owners.

## Acceptance

1. A two-constructor enum projected to `Text` proves `x /= A && x /= B` unsatisfiable and can
   reconstruct every satisfiable model to one of the two concrete constructors.
2. Two values of the same finite projection compare equal and unequal through structural `PEq`;
   repeated paths share one constrained symbolic variable.
3. A validated textual projection never reports a model outside its declared domain, with positive
   and negative prefix/suffix boundary tests.
4. Two projection tags with the same owner and result types but different domains remain distinct
   in memoization, diagnostics, and extracted models.
5. Missing or unsupported domain evidence produces the conservative IR-3 outcome rather than a
   verified result.
6. Concrete evaluation, symbolic translation, domain membership, and reconstruction agreement are
   covered by reusable property helpers plus adversarial broken-witness tests.
7. Projection-origin counterexamples identify the structural path and stable projection shape;
   multi-edge determinism/dead-edge diagnostics preserve their existing `EdgeRef` attribution.
8. Existing `FieldProjection` instances remain source-compatible or receive a documented migration
   path whose default is conservative, never falsely exact.
9. The capability is released on Hackage and tagged upstream before Keiro raises its dependency
   floor.
10. Repeated uses of one exact tag on one path may be exact, but two different tags on one owner
    path and a direct-plus-projected read are conservative unless an explicit joint owner relation
    proves and reconstructs their combined values.
11. The validated-text fixture describes its complete lexical language. TypeID-style coverage
    includes the alphabet, total suffix length, overflow-leading character, version, variant,
    prefix, separator, and full-string boundaries rather than only a prefix regex.
12. `symSatExt` keeps its existing full-carrier constraints and returns only a pair that passes
    concrete evaluation. When possible it installs relation-safe reconstructed projection owners
    at their structural paths; inability to construct a complete pair yields `Nothing`, not a false
    witness or an UNSAT claim.

## Out of Scope

- Keiro's nominal declaration syntax, language versions, codecs, fingerprints, or migration rules.
- Ordering or arithmetic for nominal projections.
- Proving laws for arbitrary Haskell functions without generated/property evidence.
- A global `NominalEquality owner` class; schema-declaration identity remains projection-tagged.

## Compatibility Baseline

The requesting audit verified Keiki 0.6.0.0 against the authoritative Hackage release and upstream
tag. The released `FieldProjection` API and its existing users form the compatibility baseline.
