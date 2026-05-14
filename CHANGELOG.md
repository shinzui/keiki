# Changelog

All notable changes to this package are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to the
[Haskell PVP](https://pvp.haskell.org).


## [Unreleased]

(Pre-Hackage. The next published release is 0.1.0.0.)


## [0.1.0.0] — TBD

Initial Hackage release. Public surface stabilised around the
symbolic-register transducer formalism described in
`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`.

### Added

- `Keiki.Core` — the foundational `RegFile rs` register file, the
  `SymTransducer` GADT, and the slot / predicate / command / event /
  output algebra.
- `Keiki.Acceptor` — input- and output-side acceptor projections.
- `Keiki.Builder` — the monadic edge-authoring DSL.
- `Keiki.Composition` — sequential, alternative, and single-step
  feedback combinators on `SymTransducer`s.
- `Keiki.Decider` — the Chassaing-shape `Decider` facade
  (`decide` / `evolve` / `initialState` / `isTerminal`) derived
  mechanically from a `SymTransducer`.
- `Keiki.Generics` — `RegFieldsOf`, `GRecord`, `mkInCtor` /
  `mkInCtorVia`, `mkWireCtor` / `mkWireCtorVia`, plus `EmptyRegFile`.
- `Keiki.Generics.TH` — `deriveAggregateCtors`, `deriveWireCtors`,
  `deriveView` for record-payload aggregates.
- `Keiki.NoThunks` — strict-evaluation discipline assertions for
  the register file and per-vertex state.
- `Keiki.Profunctor` — `Profunctor` / `Category` / `Strong` /
  `Choice` instances on the existential `SymTransducer` wrapper.
- `Keiki.Render.Mermaid` — Mermaid renderers for single and
  composite `SymTransducer` diagrams.
- **`Keiki.Shape`** — GHC-upgrade-safe shape hash for snapshot
  discrimination. `class CanonicalTypeName a`, `class
  KnownRegFileShape (rs :: [Slot])`, `regFileShapeHash`,
  `regFileShapeCanonical`, `renderStableTypeRep`, `sha256Hex`.
  Reusable by any codec; the optional JSON codec lives in the
  sibling package `keiki-codec-json`.
- `Keiki.Symbolic` — SBV-backed `sat` / `isBot` /
  `isSingleValuedSym` analyses for symbolic CI gating.

### Out of scope (intentional)

- No built-in serialization. JSON / CBOR / Protobuf codecs are
  runtime concerns and live in sibling packages — currently
  `keiki-codec-json`. The pure core talks only typed Haskell
  values; the shape hash discriminates snapshots regardless of
  codec choice.

### Validated against

- GHC 9.12.4 on macOS aarch64 and Linux x86_64 (CI matrix; see
  `.github/workflows/ci.yml`).
- 186 hspec assertions in the in-tree test suite, including 11
  `Keiki.ShapeSpec` golden assertions for the shape hash.
