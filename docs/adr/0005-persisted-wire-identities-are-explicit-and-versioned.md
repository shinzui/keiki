---
type: Architecture Decision Record
title: Persisted wire identities are explicit and versioned
description: >-
  Give persisted event and snapshot identities pinned, module-independent names and an
  explicit versioned wire envelope so Haskell refactors do not silently change stored data.
docId: ADR-5
status: Accepted
date: 2026-07-13
timestamp: 2026-08-04T20:31:10Z
generated:
  by: adopt-architecture-decisions/0.8.0
  at: 2026-08-04T16:35:24Z
---

# ADR-0005: Persisted wire identities are explicit and versioned

- **Plan(s):** `docs/plans/77-event-codec-schema-evolution-version-tags-wire-kind-pinning-and-default-on-missing-decoding.md`; `docs/plans/78-persistence-wire-format-hardening-golden-byte-fixtures-maybe-slot-coverage-and-stable-shape-hash-names.md`; `docs/plans/86-research-a-full-symbolic-replay-inversion-model.md`; `docs/plans/87-add-structural-wire-schemas-for-optional-symbolic-replay-inversion.md`

## Context

Persisted event discriminators and snapshot shape hashes outlive Haskell
module names, compiler versions, and source constructor renames. Deriving
those identities implicitly makes harmless refactors change stored data.
An unversioned event envelope also has no disciplined route for
structural schema migration.

## Decision

Built-in `CanonicalTypeName` instances use pinned,
module-independent names. Container names recurse through
`CanonicalTypeName`, so application overrides compose inside `Maybe`,
lists, `Either`, and tuples. Register-file shape hashes remain structural
snapshot discriminators, not semantic schema versions.

The optional JSON event codec emits an explicit wire kind and in-band
schema version. Applications may pin a constructor's historical wire
kind, provide additive missing-field defaults, and register a
compile-time-complete sequence of one-envelope-to-one-envelope upcasters.
One-to-many event migrations and semantic changes remain application
boundary responsibilities.

Persisted wire identity and `WireSchema` structural proof evidence serve different contracts.
A wire kind identifies durable encoded data across versions; it does not prove Haskell field-type
equality, matcher behavior, or ordered field correspondence between two `WireCtor` values. Full
symbolic replay inversion must carry separate typed structural evidence and must not overload
`wcName` or persisted wire-kind strings as proof.

## Consequences

- Adopting the pinned built-in names changes all existing non-empty
  shape hashes once; an old snapshot is a cache miss and the event log
  is replayed.
- User-defined types inside containers need their own stable
  `CanonicalTypeName` when the default module-qualified identity is not
  durable enough.
- Haskell constructor renames need not change persisted event kinds.
- Golden fixtures pin snapshot values, shape identities, and versioned
  event envelopes against accidental drift.
- Applications with an outer versioned envelope may keep the derived
  codec at version 1 and own migration entirely outside it.
- Structural replay evidence reuses Generic/TH schema derivation, but its typed proof remains
  process-local and distinct from the persisted discriminator and version envelope.
