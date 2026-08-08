---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# What keiki provides today

keiki is the **pure core** of event sourcing, workflow engines, and durable
execution, expressed as one formalism — the symbolic-register finite-state
transducer. A consumer declares an aggregate or workflow once as a typed
transducer and reads forward decisions, replay, validation, projections,
composition, diagrams, and optional solver-backed proofs out of that single
declaration. Serialization is deliberately not in the core: it lives in the
sibling `keiki-codec-json` and `keiki-codec-json-test` packages.

Every record below is backed by evidence a reader can open — an in-package spec,
a golden fixture, a benchmark, or a worked-example spec in the downstream
`jitsurei` package.

**Stability is uniform and deliberate.** keiki is pre-1.0 under the Haskell PVP,
and its changelog shows breaking changes at nearly every minor bump. Every
capability is therefore `stability: experimental`: usable today, but not yet
carrying a compatibility promise across releases. That uniformity is a fact about
the project's phase, not a gap in this catalog.

## Deliberately excluded

- **The `jitsurei` package is not a capability.** It is worked-example code used
  here as *evidence* for other capabilities, not a unit a consumer depends on.
- **No built-in serialization in the core.** JSON is a separate package
  ([CAP-11](json-codec.md)); CBOR/Protobuf codecs are intentionally absent.
- **Cross-repository, composed behaviour is out of scope by rule.** Anything only
  true when keiki and a consuming service cooperate (for example a specific
  runtime's durable-execution guarantees) belongs to that consumer as a use-case
  feature, not to keiki.
- **`Keiki.Operators` and `Keiki.NoThunks`** are folded into
  [CAP-1](typed-transducer-core.md) rather than split out, because a consumer
  adopts them together with the core and they are proven by the same evidence.

# Capabilities

| Handle | Capability | Since | Package |
|---|---|---|---|
| [CAP-1](typed-transducer-core.md) | Typed transducer authoring and forward execution | 0.1.0.0 | keiki |
| [CAP-2](event-log-replay.md) | Structured event-log replay and reconstitution | 0.1.0.0 | keiki |
| [CAP-3](replay-safety-validation.md) | Static replay-safety and determinism validation | 0.1.0.0 | keiki |
| [CAP-4](symbolic-analysis.md) | Opt-in symbolic (SBV + z3) analysis | 0.1.0.0 | keiki |
| [CAP-5](generic-th-derivation.md) | Generic and Template Haskell derivation | 0.1.0.0 | keiki |
| [CAP-6](b-presentation-views.md) | Per-vertex B-presentation projections | 0.1.0.0 | keiki |
| [CAP-7](composition-combinators.md) | Composition and profunctor combinators | 0.1.0.0 | keiki |
| [CAP-8](acceptors.md) | Input and output acceptors | 0.1.0.0 | keiki |
| [CAP-9](diagram-rendering.md) | Readable Mermaid and Markdown rendering | 0.1.0.0 | keiki |
| [CAP-10](snapshot-shape-hash.md) | Codec-independent snapshot shape discrimination | 0.1.0.0 | keiki |
| [CAP-11](json-codec.md) | Optional JSON codec for register files and events | 0.1.0.0 | keiki-codec-json |
| [CAP-12](codec-test-toolkit.md) | Codec property-test toolkit for downstream consumers | 0.1.0.0 | keiki-codec-json-test |
