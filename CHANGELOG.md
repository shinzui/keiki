# Changelog

All notable changes to this package are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to the
[Haskell PVP](https://pvp.haskell.org).


## [Unreleased]

### Added

- `Keiki.Builder.buildTransducerEither` returns all eagerly located builder
  defects as structured `BuilderError` values. `BuilderDefect` and
  `renderBuilderErrors` expose the same validation and historical message format
  without exception plumbing.
- `DistinctNames` provides the canonical compile-time duplicate register-slot
  check, and `slotNamesOf` is now exported from `Keiki.Core` for structural
  constructor validation.
- Structured replay diagnostics are available through
  `applyEventStreamingEither`, `replayEvents`, `applyEventsEither`, and
  `reconstituteEither`. `ReplayStepFailure`, `ReplayFailureReason`, and
  `ReplayFailure` identify the failing event index, wrapper state, and exact
  reason, including ambiguous inversion, queue mismatch, and truncated
  multi-event chains. The existing `Maybe` functions remain compatibility
  wrappers over this primary surface.

### Changed

- `validateTransducer defaultValidationOptions` now enforces four additional
  replay-safety checks: head-event recoverability, cross-edge inversion
  ambiguity, constructor guards before input-field reads, and state-changing
  ε-edges. The corresponding warning constructors are `HeadUnrecoverable`,
  `InversionAmbiguity`, `UnguardedInputRead`, and `StateChangingEpsilon`; the
  new default-on option fields are `checkHeadRecoverability`,
  `checkInversionAmbiguity`, `checkGuardImpliesInputRead`, and
  `checkStateChangingEpsilon`. Code that exhaustively matches
  `TransducerValidationWarning` must add these four cases, and code that
  constructs `ValidationOptions` should record-update `defaultValidationOptions`
  so future checks remain enabled.
- `checkHiddenInputs` now requires the first event of a multi-event edge to
  recover every consumed command field. Coverage spread across the union of the
  head and tail is no longer accepted because streaming replay inverts only the
  head; tail-only fields produce `HeadUnrecoverable` through
  `validateTransducer` and an equivalent legacy string warning through
  `checkHiddenInputs`.
- The canonical User Registration pre-confirmation deletion now emits
  `AccountDeleted` instead of changing vertex and registers silently, so its
  forward result is recoverable from its persisted log.
- `Keiki.Builder` now requires every `onCmd`/`onEpsilon` edge body to
  declare its output intent explicitly. A body that reaches `goto` without
  calling `emit`/`emitWith` or `noEmit` is an eager construction error instead
  of silently becoming an ε-edge; deliberately silent edges keep working by
  calling `noEmit`.
- `Keiki.Builder` now validates every declared edge when the returned transducer
  is evaluated to weak head normal form. Missing/multiple `goto` calls and
  mismatched explicit `emitWith` constructors no longer remain latent until an
  affected `edgesOut` branch is demanded; duplicate `from` blocks merge in
  declaration order with stable per-vertex edge indices.
- The builder pins the enclosing `onCmd` input schema in `EdgeBuilder`. Passing
  another command's term-fields record to `emit`, or calling `emit` inside
  `onEpsilon`, is now a compile-time error. `emitWith` remains the explicit form
  for `onEpsilon` and must agree with the enclosing constructor inside `onCmd`.
- `buildTransducer` and `buildTransducerEither` require
  `DistinctNames (Names rs)`, rejecting register files with duplicated slot
  names instead of silently resolving the first occurrence. Vertex grouping now
  requires `Eq v`; the unused `Bounded v` and `Enum v` constraints were removed.
- Current keiro authoring remains source-compatible: the standard
  `B.emit wireCtorX XTermFields {..}` shape and both build call forms are
  unchanged for valid aggregates.
- `Keiki.Profunctor` no longer fabricates method-carrying `WeakenR` and
  `KnownSlotNames` dictionaries with `unsafeCoerce`. Nested stateful Category
  composition previously misindexed register reads and writes and hid slot names
  from `CategoryOverlapError`. `SomeSymTransducer` now carries the exported
  `KnownSlots`/`SlotListWitness` evidence from `Keiki.Composition`, and composite
  evidence is derived by structural induction. The smart constructor's structural
  constraints are now expressed as `KnownSlots rs`.
- `Keiki.Acceptor.outputAcceptor` now carries
  `(InFlight s co, RegFile rs)` and steps with `applyEventStreaming`, so its
  acceptance result agrees with `reconstitute` for multi-event and truncated
  logs as well as letter-only logs.

### Removed

- `Keiki.Builder` no longer uses `unsafeCoerce` to reinterpret the input schema
  recovered by `emit`; the schema relationship is represented in its types.
- The lossy pre-release Decider facade has been removed. Use `stepEither` for
  forward decisions and the structured `Keiki.Core` replay functions for
  hydration; there is no letter-only replay facade that silently retains the
  input state after a failure.


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
