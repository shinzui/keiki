---
title: "Opt-in symbolic (SBV + z3) analysis"
type: Capability
description: "Prove emptiness, single-valuedness, dead edges, and replay-inversion disjointness of a transducer's guards at build time with an SBV + z3 backend."
generated:
  by: adopt-capabilities/0.9.2
  at: "2026-08-08T00:00:00Z"
capabilityId: CAP-4
provider: mori://shinzui/keiki
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - keiki
interface:
  - Keiki.Symbolic
  - Keiki.ProjectionDomain
requires:
  - CAP-1
evidence:
  - kind: test
    resource: test/Keiki/SymbolicSpec.hs
    proves: sat / isBot / single-valuedness analyses return conservative verdicts against z3.
  - kind: test
    resource: test/Keiki/FullSymbolicReplayInversionSpec.hs
    proves: The opt-in replay-inversion ambiguity check only clears a warning on a definite Unsatisfiable result.
  - kind: test
    resource: test/Keiki/ProjectionDomainSpec.hs
    proves: Exact projection domains round-trip between concrete membership and their symbolic encoding.
  - kind: example
    resource: jitsurei/test/Jitsurei/LoanApplicationSymbolicSpec.hs
    proves: A worked aggregate is gated by the symbolic analyses end to end.
---

# Opt-in symbolic (SBV + z3) analysis

For CI gating that the pure validation pass (`CAP-3`) cannot decide, keiki offers
a solver-backed layer. It translates guards and terms
into SBV and asks z3 for satisfiability, emptiness, witnesses, dead edges,
single-valuedness, and replay-inversion disjointness. All solver work is
build-time; the forward and replay hot paths in [CAP-1](typed-transducer-core.md)
never call it.

## What you adopt

- **`Keiki.Symbolic`**: `sat`, `symIsBot`, `isSingleValuedSym`, dead-edge and
  determinism analyses, and `satResultIsProvablyUnsat`.
- **Predicate verification** (since 0.6.0.0): `verifyPredicate`,
  `predicateTranslationExact`, `PredicateVerification`, and the detailed
  `verifyPredicateDetailed` / `predicateTranslationReport` (0.7.0.0).
- **Exact projection domains** (since 0.4.0.0 / 0.7.0.0): `Keiki.ProjectionDomain`
  plus the `FieldProjection` surface in `Keiki.Core`, letting guards read one
  scalar field of a consumer-owned value and giving it an exact symbolic domain
  (`ExactFieldProjection`, `exactFieldWitness`).
- **Replay-inversion checks** (since 0.9.0.0): `checkInversionAmbiguitySym` /
  `checkInversionAmbiguitySymDetailed`.

## Shortest real usage

```haskell
-- z3 must be on PATH; the analyses run z3 through unsafePerformIO.
isSingleValuedSym transducer :: Bool
```

## Limits

- **Requires z3 on `PATH` at runtime.** These pure-looking APIs run z3 through
  `unsafePerformIO` and throw loudly if the solver is missing — an operational
  footgun for any consumer wiring them into CI. Install via `brew install z3` or
  `apt install z3`.
- **Only a definite `Unsatisfiable` proves anything.** `Unknown`, `ProofError`,
  and other inconclusive results never bless a guard pair as disjoint or an edge
  as dead; they fail conservatively.
- **Translation is a documented fragment.** Unsupported functions and
  projections are widened by dropping their relationships. `Int` is modelled as
  an unbounded `Integer`, so analyses whose truth depends on `Int` overflow must
  use an explicitly sized type; fixed-width `Word*`/`Int32`/`Int64` and
  picosecond `UTCTime` are exact.
- **The projection agreement is one-way.** Every concrete owner binds a matching
  symbolic projection value, but an arbitrary symbolic projection model need not
  correspond to a constructible owner; `symSatExt` will not reconstruct owners
  from free projection scalars.
- `since` here is the base symbolic surface (0.1.0.0); the projection-domain and
  inversion refinements arrived later as noted above, so a consumer pinning an
  early version gets less than this record describes.
