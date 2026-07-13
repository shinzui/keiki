# ADR-0005: Persisted wire identities are explicit and versioned

- **Status:** Accepted
- **Date:** 2026-07-13
- **Plan(s):** `docs/plans/77-event-codec-schema-evolution-version-tags-wire-kind-pinning-and-default-on-missing-decoding.md`; `docs/plans/78-persistence-wire-format-hardening-golden-byte-fixtures-maybe-slot-coverage-and-stable-shape-hash-names.md`

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
