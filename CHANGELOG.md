# Changelog

All notable changes to this package are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to the
[Haskell PVP](https://pvp.haskell.org).


## [Unreleased]

### Changed

- `Keiki.Profunctor` no longer fabricates method-carrying `WeakenR` and
  `KnownSlotNames` dictionaries with `unsafeCoerce`. Nested stateful Category
  composition previously misindexed register reads and writes and hid slot names
  from `CategoryOverlapError`. `SomeSymTransducer` now carries the exported
  `KnownSlots`/`SlotListWitness` evidence from `Keiki.Composition`, and composite
  evidence is derived by structural induction. The smart constructor's structural
  constraints are now expressed as `KnownSlots rs`.


## [0.1.0.0] — 2026-06-07

Initial Hackage release. Public surface stabilised around the
symbolic-register transducer formalism described in
`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`.

### Added

- `Keiki.Core` — the foundational `RegFile rs` register file, the
  `SymTransducer` GADT, and the slot / predicate / command / event /
  output algebra. Edges carry a *list-shaped* output
  (`output :: [OutTerm rs ci co]`) so one transition can emit
  zero, one, or N events in declaration order — a Generalized
  Sequential Machine, not a letter FST. The `InFlight s co`
  wrapper exposes the streaming-replay state for event-by-event
  replay through length-N edges; `applyEvent` (letter-only) and
  `applyEventStreaming` (InFlight-aware) cover the two regimes,
  while `applyEvents` does atomic chunk replay over command
  boundaries.
- `Keiki.Acceptor` — input- and output-side acceptor projections.
- `Keiki.Builder` — the monadic edge-authoring DSL.
- `Keiki.Composition` — sequential, alternative, and single-step
  feedback combinators on `SymTransducer`s.
- `Keiki.Decider` — the Chassaing-shape `Decider` facade
  (`decide` / `evolve` / `evolveStreaming` / `initialState` /
  `isTerminal`) derived mechanically from a `SymTransducer`.
  `decide` returns the full event list directly, including
  length-2+ chains from multi-event edges; `evolveStreaming`
  threads the `Keiki.Core.InFlight` wrapper through length-N
  edges for event-by-event streaming replay.
- `Keiki.Generics` — `RegFieldsOf`, `GRecord`, `mkInCtor` /
  `mkInCtorVia`, `mkWireCtor` / `mkWireCtorVia`, plus `EmptyRegFile`.
- `Keiki.Generics.TH` — `deriveAggregateCtors`, `deriveWireCtors`,
  `deriveView` for record-payload aggregates, plus zero-enumeration
  `*All` splices that retire the hand-typed
  `(constructorName, shortName)` spec list in the common case where
  the short name equals the constructor name:
  - `deriveAggregateCtorsAll ''Cmd ''Regs` — enumerates every command
    constructor and emits `inCtor<Ctor>` / `inp<Ctor>` / `is<Ctor>`
    (singletons omit `inp<Ctor>`), defaulting each short-name suffix to
    the constructor name.
  - `deriveWireCtorsAll ''Event` — the event-side dual, emitting
    `wire<Ctor>` plus, for record-payload events, the `<Ctor>TermFields`
    record and its `ToOutFields` instance.
  - `deriveAggregate ''Cmd ''Regs ''Event` — fuses both `*All` variants
    into one splice covering an aggregate's command and event
    constructors.
  The enumerated `deriveAggregateCtors` / `deriveWireCtors` remain for
  abbreviated short names that differ from the constructor name.
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

- GHC 9.12.2 locally on macOS aarch64 and in CI on Ubuntu Linux
  x86_64 (see `.github/workflows/ci.yml`).
- 278 hspec assertions in the in-tree test suite, including 11
  `Keiki.ShapeSpec` golden assertions for the shape hash, 10
  `Keiki.CoreInFlightSpec` assertions for the GSM streaming
  replay path, and 3 `Keiki.CompositionMultiEventSpec`
  assertions for multi-event composition. The downstream
  `jitsurei` package adds 96 more assertions exercising eight
  worked-example aggregates against the public surface.
