# ADR-0003: Proof gates fail conservatively

- **Status:** Accepted
- **Date:** 2026-07-13
- **Plan(s):** `docs/plans/76-symbolic-soundness-solver-unknown-handling-encoding-gap-caveats-and-a-stronger-pure-overlap-check.md`; `docs/plans/79-typed-symbolic-field-projections-over-mapped-consumer-owned-values.md`

## Context

keiki uses emptiness checks to bless two guards as disjoint and to
classify an edge as dead. Treating solver uncertainty as proof of
unsatisfiability can accept a nondeterministic model. Approximate numeric
or time encodings can make the symbolic question differ from concrete
Haskell execution.

## Decision

Only a definite solver `Unsatisfiable` result proves a predicate empty.
`Unknown`, `ProofError`, `DeltaSat`, and every other inconclusive result
mean “not proved empty.” They may reject or warn on a valid model, but
they must never bless an unsafe one.

Fixed-width integer types use their exact SBV bit-vector widths, and
`UTCTime` uses lossless picoseconds. Platform-sized `Int` remains modeled
as unbounded `Integer`; models whose truth depends on overflow must use
an explicit fixed-width type. The fast pure validator proves overlaps
only inside its documented structural fragment and stays silent when it
cannot prove one; the z3-backed check is the exact gate.

A typed field projection over a consumer-owned value is modeled as a
free scalar with structural, nominal identity. Soundness is the one-way
concrete-to-symbolic simulation: for every concrete owner, constrain the
scalar to the total getter result and symbolic predicate evaluation must
agree with concrete evaluation. Keiki does not claim the converse. A
model containing free projection values need not correspond to any
constructible owner, and `symSatExt` does not reconstruct such owners.
This over-approximation may conservatively reject a valid proof gate; it
must not manufacture an unsatisfiability proof.

## Consequences

- A solver timeout or unsupported theory can produce a conservative CI
  failure instead of a false pass.
- `not . symIsBot` means only “not proved empty,” not “proved
  satisfiable”; callers needing that claim must request a witness.
- Fixed-width overflow and sub-second time guards agree with concrete
  execution.
- The pure validator has no false-positive overlap warnings in its
  supported fragment, but it can miss unsupported predicate shapes.
- Projection-backed satisfiability witnesses are scalar abstractions,
  not reconstructed consumer-owned values. Callers that need a concrete
  owner must provide it and bind its getter result explicitly.
