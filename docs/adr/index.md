---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Architecture Decision Record

- [Structural re-indexing of `Term`/`OutFields` for sound replay](0001-structural-re-indexing-for-sound-replay.md) - Recover replay indices by type-level structural re-indexing of Term and OutFields schemas instead of runtime coercion, eliminating unsound unsafeCoerce-based index recovery.
- [Event logs must reproduce forward state](0002-event-logs-must-reproduce-forward-state.md) - Require that replaying any log accepted by default validation reproduces the same forward vertex and register file, backed by structured replay APIs and default validation checks.
- [Proof gates fail conservatively](0003-proof-gates-fail-conservatively.md) - Treat only a definite solver Unsatisfiable result as proof of predicate emptiness, keeping every proof gate, projection domain, and verification classification conservative under solver or encoding uncertainty.
- [Composition uses snapshot updates and checked boundaries](0004-composition-uses-snapshot-updates-and-checked-boundaries.md) - Give UCombine parallel-assignment, entry-snapshot semantics and require composeChecked to validate constructor, arity, and projection boundaries so composition matches sequential execution.
- [Persisted wire identities are explicit and versioned](0005-persisted-wire-identities-are-explicit-and-versioned.md) - Give persisted event and snapshot identities pinned, module-independent names and an explicit versioned wire envelope so Haskell refactors do not silently change stored data.
- [Readable business semantics are the primary rendering contract](0006-readable-business-semantics-are-the-primary-rendering-contract.md) - Make TLit carry Show evidence so primary Mermaid renderers show full guard and update semantics by default, while TOpaqueLit and topology mode remain the explicit routes to redact or omit them.

