---
type: Architecture Decision Record
title: Composition uses snapshot updates and checked boundaries
description: >-
  Give UCombine parallel-assignment, entry-snapshot semantics and require composeChecked to
  validate constructor, arity, and projection boundaries so composition matches sequential
  execution.
docId: ADR-4
status: Accepted
date: 2026-07-13
timestamp: 2026-08-04T23:57:10Z
generated:
  by: adopt-architecture-decisions/0.8.0
  at: 2026-08-04T16:35:24Z
---

# ADR-0004: Composition uses snapshot updates and checked boundaries

- **Plan(s):** `docs/plans/74-fix-compose-update-snapshot-semantics-and-multi-event-chain-expansion-under-stateful-transducers.md`; `docs/plans/75-composition-alignment-validation-and-forward-fragment-law-documentation-for-the-categorical-instances.md`; `docs/plans/79-typed-symbolic-field-projections-over-mapped-consumer-owned-values.md`; `docs/plans/87-add-structural-wire-schemas-for-optional-symbolic-replay-inversion.md`; `docs/plans/88-add-structural-input-constructor-evidence-for-composition-and-symbolic-alignment.md`

## Context

Stateful composition previously disagreed with sequential execution.
`UCombine` let later right-hand sides see earlier writes from the same
edge, while composition assumed a common entry snapshot; multi-event
expansion also failed to thread downstream writes into later guards and
outputs. Constructor-name or field-shape drift at an alphabet boundary
could produce dead or misleading pipelines.

## Decision

`UCombine` has parallel-assignment semantics: every right-hand side
reads the edge-entry register file and writes are applied left to right.
Sequential `compose` symbolically threads downstream register writes
between events in a multi-event chain so the composite agrees with
stepping its two parts event by event.

Durable pipelines should use `composeChecked`, which validates
constructor names, field arities, unmatched expectations, and mapped or
poisoned boundary provenance before returning a composite. `compose`
remains the unchecked construction primitive. `feedback1` is explicitly
a two-copy cascade, not shared-state feedback.

When a typed field projection crosses a mapped composition boundary,
composition preserves it if the mapped owner is still a direct register
or input read, folds it if the owner is a literal, and otherwise lowers
the getter to an opaque unary application. Raw `compose` remains
forward-correct under that lowering, but symbolic precision is lost.
`composeChecked` rejects that boundary with a structured
`NonStructuralProjectionBoundary` warning, including pending-write cases
in multi-event chains.

Structural output-wire evidence follows the same checked-boundary rule. `leftWireCtor` and
`rightWireCtor` prefix a trusted constructor path across their proven `Either` arms, and Builder
emission preserves the supplied schema unchanged. Transformations that replace the matcher,
change field meaning, or cannot prove the typed relationship—including identity, Strong/Arrow,
and output-map paths—set the schema to unavailable rather than forwarding stale proof evidence.

Input constructors carry the matching abstract structural path and typed slot spine. Composition
may substitute a downstream input-field read or discharge its `PInCtor` guard only when the
upstream wire schema and downstream input schema have equal paths and position-by-position field
types. Equal diagnostic names are never evidence. A witnessed mismatch produces
`StructurallyDifferentInputWire`; unavailable evidence produces
`UnwitnessedInputWireAlignment`; and the unchecked primitive leaves a loud poison leaf rather
than coercing a result type from the name match.

Generic and TH producers create trusted evidence, `Either` lifters prefix it, and manual or
meaning-changing constructors explicitly report unavailable. Polymorphic categorical identity
has a hidden one-field capability used only for checked composition; it remains unavailable to
general schema observers and symbolic constructor-identity proofs.

## Consequences

- Intra-edge updates cannot intentionally depend on a sibling write;
  split such work across edges or compute both values from the entry
  snapshot.
- Stateful single- and multi-event composition has a tested sequential
  homomorphism.
- Mapped categorical boundaries and slot overlap fail loudly rather than
  silently producing a dead pipeline.
- Typed projections retain nominal symbolic identity only across
  structural boundaries; computed and pending-write owners require an
  explicit unchecked, forward-only choice.
- Output-wire schemas survive only structure-preserving checked boundaries; lossy transformations
  remain usable but cannot authorize cross-edge observed-field sharing.
- Input-to-wire substitution is typed and checked; name collisions and unavailable evidence fail
  loudly instead of authorizing an unchecked result-type coercion.
- `Category`, `Choice`, `Strong`, and `Arrow` claims are documented per
  forward and replay observations; some fragments remain partial or
  forward-only rather than unqualified lawful instances.
