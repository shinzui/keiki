---
type: Architecture Decision Record
title: Proof gates fail conservatively
description: >-
  Treat only a definite solver Unsatisfiable result as proof of predicate emptiness, keeping
  every proof gate, projection domain, and verification classification conservative under
  solver or encoding uncertainty.
docId: ADR-3
status: Accepted
date: 2026-07-13
generated:
  by: adopt-architecture-decisions/0.8.0
  at: 2026-08-04T16:35:24Z
---

# ADR-0003: Proof gates fail conservatively

- **Plan(s):** `docs/plans/76-symbolic-soundness-solver-unknown-handling-encoding-gap-caveats-and-a-stronger-pure-overlap-check.md`; `docs/plans/79-typed-symbolic-field-projections-over-mapped-consumer-owned-values.md`; `docs/plans/80-harden-natural-symbolic-validation-and-documentation.md`; `docs/plans/82-classify-unconstrained-symbolic-field-projections-conservatively.md`; `docs/plans/83-add-exact-reconstructible-symbolic-field-projection-domains.md`

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

Fixed-width integer types use their exact SBV bit-vector widths. Platform-sized
`Int` remains modeled as unbounded `Integer`; models whose truth depends on
overflow must use an explicit fixed-width type. `UTCTime` is encoded as
picoseconds through POSIX time, but that conversion clamps leap-second day
times and is not a whole-carrier isomorphism. `Text` also exceeds SMT-LIB's
U+2FFFF string ceiling. Consequently whole-carrier exact projection domains
are currently admitted only for `Bool`, `Integer`, `Natural`, and the curated
fixed-width integer types; finite domains remain exact when every literal is
representable. The fast pure validator proves overlaps only inside its
documented structural fragment and stays silent when it cannot prove one.

`Natural` uses an unbounded SMT integer constrained to be non-negative for
every allocated symbolic variable. Equality, ordering, addition, and
multiplication are structural. Subtraction has explicit total-monus semantics
in both interpreters: `a - b = max 0 (a - b)`. The fast pure validator models
`Natural` as the exact interval `[0, infinity)`.

A typed field projection over a consumer-owned value is modeled as a
free scalar with structural, nominal identity. Soundness is the one-way
concrete-to-symbolic simulation: for every concrete owner, constrain the
scalar to the total getter result and symbolic predicate evaluation must
agree with concrete evaluation. Keiki does not claim the converse. A
model containing free projection values need not correspond to any
constructible owner, and `symSatExt` does not reconstruct such owners.
This over-approximation may conservatively reject a valid proof gate; it
must not manufacture an unsatisfiability proof.

An `exactFieldWitness` opts a nominal projection tag into a stronger contract.
Its `ProjectionDomain` is a closed backend-neutral description of the getter's
exact image: a non-empty finite set, a validated full-string `TextPattern`, or
a whole carrier whose symbolic representation Keiki has classified as an
isomorphism. The same domain value drives concrete membership and the SBV
constraint. The declaration also supplies a partial inverse that must accept
every domain key and return a canonical owner whose getter round-trips to that
key. `checkFieldProjectionOwner` and `checkFieldProjectionKey` make both laws
executable for consumer and generated conformance suites.

Per-projection exactness is not predicate-global relational exactness. A base
path may use one nominal exact projection tag repeatedly, but two distinct
tags over one owner or a direct owner read combined with any projection remain
conservative: independent solver variables do not encode their joint owner
relation. Distinct structural bases remain independent. An input projection is
exact only when the complete predicate logically implies its matching
constructor guard. Projection arithmetic and ordering remain conservative;
the exact surface is structural equality and its negation.

Exact verification and compatibility emptiness therefore use different
classifications. `verifyPredicate` reaches `VerifiedSatisfiable` or
`VerifiedUnsatisfiable` only for a translation-exact predicate, meaning every
satisfying symbolic valuation corresponds to concrete values under the
documented carrier laws. A released one-way `fieldWitness` carries no exact
domain evidence, so any predicate containing its `TFieldProj` is
`UnverifiedOpaque`. By contrast, `symIsBot` may still prove that predicate
empty: definite unsatisfiability over the larger free-scalar domain also
proves the smaller concrete domain empty. Its `False` result means only “not
proved empty.”

`symSatExt` concretely evaluates every reconstructed candidate before
returning it. A free projection value, opaque `TApp1`/`TApp2` assignment, or
non-`Sym` equality fallback that cannot be realized by the reconstructed
registers and input yields `Nothing`. A constructor-guard violation during
that concrete check also yields `Nothing`. These outcomes mean “no concrete
witness recovered,” never proof of unsatisfiability.

`verifyPredicateDetailed` preserves solver status, translation strength, and
checked path-local `ProjectionModel` values. A satisfying exact projection
model is decoded only after domain membership, inverse success, and getter
round-trip checks; failure is a projection contract violation. A path-local
model is not by itself a complete `(RegFile, input)` witness. `symSatExt` may
install a relation-safe reconstructed owner at the matching structural path,
but still returns it only after the complete candidate passes concrete
evaluation. Detailed determinism and dead-edge analyses retain the same single
solver result and edge attribution used by their compatibility projections.

Exact projection declarations shift one proof boundary. Runtime model checks
can catch an inverse that rejects an admitted key or returns a non-round-
tripping owner. They cannot observe a domain that omits a key produced by a
real owner, because that under-declaration can manufacture a false UNSAT before
any satisfying model exists. Therefore `VerifiedUnsatisfiable`, `symIsBot`, a
determinism disjointness blessing, and a dead-edge proof for predicates using
`exactFieldWitness` are sound only conditional on the declaration laws.
Predicates using only the one-way `fieldWitness` retain the unconditional
over-approximation guarantee. Generators that emit exact witnesses must also
emit conformance tests exercising the owner-side law.

## Consequences

- A solver timeout or unsupported theory can produce a conservative CI
  failure instead of a false pass.
- `not . symIsBot` means only “not proved empty,” not “proved
  satisfiable”; callers needing that claim must request a witness.
- Fixed-width overflow and sub-second time guards agree with concrete
  execution.
- `Natural` equality, ordering, total-monus arithmetic, witnesses, and pure
  interval overlaps respect the non-negative domain.
- The pure validator has no false-positive overlap warnings in its
  supported fragment, but it can miss unsupported predicate shapes.
- One-way projection-backed satisfiability values are scalar abstractions.
  Exact projection models contain checked path-local reconstructed owners, and
  only relation-safe owners may contribute to a full `symSatExt` witness.
- Path identity and proof strength are separate: repeated projection reads
  remain one shared symbolic variable even when the containing predicate is
  not translation-exact.
- Every `Just` returned by `symSatExt` satisfies concrete `models`; callers
  needing proof of emptiness must continue to use `symIsBot`.
- Exact-domain proof strength is conditional on generated or consumer-owned
  declaration-law coverage, especially the owner-to-domain direction that no
  solver model can test.
