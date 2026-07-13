# ADR-0004: Composition uses snapshot updates and checked boundaries

- **Status:** Accepted
- **Date:** 2026-07-13
- **Plan(s):** `docs/plans/74-fix-compose-update-snapshot-semantics-and-multi-event-chain-expansion-under-stateful-transducers.md`; `docs/plans/75-composition-alignment-validation-and-forward-fragment-law-documentation-for-the-categorical-instances.md`

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

## Consequences

- Intra-edge updates cannot intentionally depend on a sibling write;
  split such work across edges or compute both values from the entry
  snapshot.
- Stateful single- and multi-event composition has a tested sequential
  homomorphism.
- Mapped categorical boundaries and slot overlap fail loudly rather than
  silently producing a dead pipeline.
- `Category`, `Choice`, `Strong`, and `Arrow` claims are documented per
  forward and replay observations; some fragments remain partial or
  forward-only rather than unqualified lawful instances.
