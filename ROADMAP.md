# keiki — Roadmap

This is the living status document for the keiki workspace. It records what is
released, what is implemented on the current branch, what is a candidate for future
work, and what is deliberately outside the pure core. For version-stamped changes see
[`CHANGELOG.md`](CHANGELOG.md); for design and delivery history see the master plans in
[`docs/masterplans/`](docs/masterplans/) and their child exec-plans in
[`docs/plans/`](docs/plans/).

_Last updated: 2026-07-13._

## Status at a glance

- **Published, pre-1.0.** The current coordinated release is `0.2.0.0`, published on
  Hackage for [`keiki`](https://hackage.haskell.org/package/keiki-0.2.0.0),
  [`keiki-codec-json`](https://hackage.haskell.org/package/keiki-codec-json-0.2.0.0),
  and
  [`keiki-codec-json-test`](https://hackage.haskell.org/package/keiki-codec-json-test-0.2.0.0).
  The initial `0.1.0.0` release shipped on 2026-06-07; `0.2.0.0` shipped on
  2026-07-13.
- **The planned surface and the architecture-hardening pass are complete.** All 16
  master-plan initiatives are resolved. The latest initiative closed the builder,
  replay, composition, symbolic-analysis, and persistence defects found by the July
  2026 architecture review.
- **No release is currently queued.** The `Unreleased` sections are empty and there is
  no active `0.3` milestone. New work should begin with a concrete consumer need and a
  scoped plan rather than treating the deferred list below as a commitment.
- **Supported toolchain:** GHC 9.12 (`tested-with: GHC >=9.12 && <9.13`); CI runs GHC
  9.12.2 on Ubuntu. A local `cabal test all` on GHC 9.12.4 currently passes **735
  examples across four suites**: 498 core, 102 JSON codec, 13 codec-test toolkit, and
  122 `jitsurei` examples.

## Current release surface

### Pure transducer core and replay

- `Keiki.Core` provides the typed `RegFile rs`, the `SymTransducer` GADT, and the slot /
  predicate / command / event / output algebra.
- Edges have list-shaped output (`output :: [OutTerm rs ci co]`), so one command can
  emit zero, one, or many events in declaration order.
- Forward decisions are available through `step` and the diagnostic `stepEither` /
  `StepFailure` surface.
- Replay supports single events, strict chunks, complete logs, and resumable
  multi-event streams through `InFlight s co`, `applyEventStreamingEither`,
  `replayEvents`, `applyEventsEither`, and `reconstituteEither`. The historical
  `Maybe` entry points are compatibility wrappers over the structured `Either` path.
- Replay failures identify the event index, wrapper state, and exact reason, including
  failed or ambiguous inversion, an unexpected queued event, and a truncated
  multi-event chain.
- `solveOutput` mechanically inverts edge output terms. Hidden command inputs,
  ambiguous inversion, and non-injective output shapes can be detected before a
  transducer is admitted to a durable boundary. Derived event fields can use the
  recompute-and-verify path.
- `runUpdate` uses snapshot (parallel-assignment) semantics: every right-hand side
  reads the edge-entry register file.

### Authoring, derivation, and validation

- `Keiki.Builder` is the monadic authoring DSL (`from`, `onCmd`, `onEpsilon`, `goto`,
  `emit`, `noEmit`, `.=` / `=:` and `reg`). Every edge must declare its output intent.
- Builder finalization is eager. `buildTransducerEither` returns all located
  `BuilderError`s; `buildTransducer` preserves the exception-based convenience path.
  Missing or repeated `goto` and mismatched `emitWith` no longer hide behind lazy
  edge evaluation; duplicate `from` blocks merge in declaration order with stable
  per-vertex indices.
- The enclosing command schema is carried in `EdgeBuilder`, so passing another
  command's generated term-fields record to `emit` is a compile-time error. Register
  slot names are required to satisfy `DistinctNames`.
- `Keiki.Generics` and `Keiki.Generics.TH` provide record-derived input/wire
  constructors, singleton-event support, per-vertex views, zero-enumeration `*All`
  splices, the fused `deriveAggregate`, and the `*With` variants for per-constructor
  suffix overrides and exclusions.
- `validateTransducer` returns structured warnings from a pure default pass. Its
  default replay-safety checks cover hidden inputs, head-event recoverability,
  cross-edge inversion ambiguity, constructor guards before input-field reads,
  state-changing epsilon edges, determinism, and possibly-dead edges. Opaque guard
  auditing is opt-in.
- `Keiki.Operators` offers the predicate operators from a qualified namespace for
  projects that also use `lens` or `generic-lens` operators.

### Symbolic analysis

- `Keiki.Symbolic` provides SBV + z3-backed satisfiability, emptiness, witness, dead
  edge, and single-valuedness analyses. Solver work is build-time only; `delta`,
  `omega`, `step`, and replay use concrete evaluation.
- Solver uncertainty is conservative: only a definite `Unsatisfiable` result proves a
  predicate empty. `Unknown`, `ProofError`, and other non-definitive results do not
  bless a proof gate.
- The symbolic translator memoizes repeated reads, supports structural arithmetic,
  preserves fixed-width integer wraparound and `UTCTime` picosecond precision, and
  produces real `sat` witnesses.
- The pure overlap pass recognizes the common constructor-and-conjunction fragment.
  Unsupported boolean or opaque syntax remains unknown. The stronger symbolic gate
  requires z3 and remains bounded by the documented concrete encodings.

### Projections and composition

- `Keiki.Acceptor` derives input- and output-side acceptors. The output acceptor is
  `InFlight`-aware, so it agrees with multi-event replay on complete and truncated
  logs.
- `deriveView` supplies B-presentation per-vertex projections.
- `Keiki.Composition` provides checked sequential composition, `alternative`, and
  `feedback1`. `composeChecked` reports constructor-name, field-arity, and mapped
  boundary drift with source-edge locations. Stateful and multi-event sequential
  composition is covered by homomorphism tests.
- `alternative` uses concrete `PLeftArm` / `PRightArm` guards. `feedback1` is a
  two-copy cascade, not shared aggregate feedback.
- `Keiki.Profunctor` exposes `SomeSymTransducer`, variance combinators, and
  `Profunctor`, `Functor`, `Category`, `Strong`, `Choice`, and `Arrow` instances.
  Composite register evidence is derived structurally rather than fabricated with
  `unsafeCoerce`; overlapping slots and poisoned mapped boundaries fail loudly.
- The categorical surface is intentionally a documented fragment: `Strong` and
  `arr` preserve forward behavior but cannot preserve output inversion, and arbitrary
  function application is not added to the symbolic term AST merely to make `Arrow`
  fusion lawful.

### Persistence and JSON packages

- `Keiki.Shape` supplies codec-independent snapshot discrimination through
  `CanonicalTypeName`, `KnownRegFileShape`, canonical shape text, and SHA-256 hashes.
  Built-in and container names are pinned independently of GHC-internal module paths.
- `keiki-codec-json` provides strict and streaming `RegFile` JSON codecs plus TH
  derivation. Duplicate slot names are rejected at compile time and encoding an
  uninitialized register produces a slot-named failure.
- Its event codec supports explicitly pinned wire kinds, an in-band schema version,
  default-on-missing additive fields, and a compile-time-complete one-envelope to
  one-envelope upcaster chain. Semantic splits and merges remain application-owned.
- `keiki-codec-json-test` provides value-level round-trip properties, shape-sensitivity
  checks, per-slot goldens, and whole-register-file golden-file tests.
- Checked-in snapshot, shape-hash, current-event, and historical-event fixtures pin
  the persistence formats. The `0.2.0.0` shape-name change intentionally invalidates
  older non-empty snapshot hashes; consumers recover by replaying their event log.

### Inspection, rendering, and documentation tooling

- `Keiki.Render.Pretty` renders predicates, terms, and updates in domain-readable
  form while marking opaque functions and literal values honestly.
- `Keiki.Render.Inspector` produces deterministic Markdown edge inventories with
  source/target, command and event constructors, guards, and written slots.
- `Keiki.Render.Mermaid` covers single transducers, sequential composites,
  alternatives, feedback cascades, nested diagrams, multi-diagram atlases, readable
  guards, multiline labels, multi-event layouts, and stable state IDs separate from
  display labels. Historical default output remains byte-identical.
- `Keiki.Render.Markdown` replaces marked diagram blocks, and
  `Keiki.Render.Validate` provides pure heuristic validation for generated diagrams
  and atlases.

### Examples and regression posture

- The in-workspace `jitsurei` package exercises eight worked aggregates, including
  `UserRegistration`, `OrderCart`, `EmailDelivery`, `LoanApplication`, and the
  multi-stage loan workflow.
- The permanent decide/replay property harness checks that validation-clean
  transducers reproduce forward state from their emitted logs. Deliberately invalid
  fixtures remain as teeth for state-changing epsilon, hidden-input, derived-output,
  and composition failure modes.
- `Keiki.NoThunks` assertions cover strict evaluation of register files and
  per-vertex state.
- Persistence tests pin both encoder paths and historical migration behavior; the
  symbolic suite covers conservative solver handling and exact concrete encodings.

## Release history

| Version | Date | Summary |
|---------|------|---------|
| `0.1.0.0` | 2026-06-07 | Initial Hackage release of the symbolic-register transducer core and both JSON sibling packages. |
| `0.2.0.0` | 2026-07-13 | Architecture hardening: eager typed builder validation, replay-aligned validation and diagnostics, corrected stateful composition, conservative symbolic proof gates, stable persistence identities, and versioned event codecs. |

All three public packages are released together. The repeatable procedure is in
[`docs/research/release-procedure.md`](docs/research/release-procedure.md).

## What may come next

There is no committed `0.3` scope. The following are candidates or consciously
deferred designs, not scheduled deliverables:

- **First-class keyed collection registers.** EP-60 completed its design/prototype
  gate with a NO-GO because the motivating consumer was not blocked. Whole-list
  storage remains supported; opaque collection guards can be surfaced by the opt-in
  validation audit. Reopen the design only for a concrete keyed-collection consumer.
- **More composition forms.** `parallel`, `Kleisli`, and `ArrowChoice` (`+++` / `|||`)
  remain deferred. Any proposal must preserve or explicitly classify replay and
  symbolic-analysis behavior.
- **Alternative diagram formats.** DOT / Graphviz remains a possible sibling to the
  Mermaid renderer, with no plan currently open.
- **Additional codecs.** CBOR or Protobuf support should follow the sibling-package
  pattern rather than adding serialization dependencies to `keiki` core.
- **A wider GHC support matrix.** The release currently supports GHC 9.12 only. When
  support is deliberately widened, update `tested-with` and CI together and run the
  persistence golden gates on every supported compiler.

## Stable boundaries and non-goals

- `keiki` remains a **pure core**. Runtime effects, persistence drivers, timers,
  retries, process-manager orchestration, and deployment concerns belong in runtime
  packages such as keiro, not in `SymTransducer`.
- The core remains **codec-free**. `Keiki.Shape` exposes identity; sibling packages own
  concrete wire formats.
- Arbitrary Haskell functions remain opaque to symbolic analysis. The library will
  not weaken its inversion and proof model to make every categorical law total.
- Event schema evolution can automate structural one-event-to-one-event migrations;
  semantic migrations, splits, merges, and outer storage-envelope policy stay at the
  application boundary.

## Master-plan ledger

| # | Initiative | Status |
|---|------------|--------|
| 1 | Validate the symbolic-register direction with a Haskell prototype | Complete |
| 2 | Retire the first v1 escape hatches (`TInpProj`, SBV `BoolAlg`) | Complete |
| 3 | Generics and authoring DX follow-ups | Complete |
| 4 | Sequential composition on `SymTransducer` | Complete |
| 5 | Acceptor projections and B-presentation views | Complete |
| 6 | Retire the remaining v1 escape hatches | Complete |
| 7 | Multi-event command support (GSM widening) | Complete |
| 8 | Alternative and feedback composition | Complete |
| 9 | Profunctor and categorical instances | Complete |
| 10 | Mermaid topology rendering | Complete |
| 11 | JSON codec packages, persistence shape hash, and initial release | Complete |
| 12 | Symbolic arithmetic, memoization, and real witnesses | Complete |
| 13 | API improvements surfaced by the Rei migration | Complete |
| 14 | DSL, validation, and event-codec improvements from the keiro consumer audit | Complete; collection extension deferred at its gate |
| 15 | Mermaid and documentation rendering improvements from the diagram audit | Complete |
| 16 | Correctness, replay, composition, symbolic, and persistence hardening | Complete |

## Reading this alongside the other docs

| Document | Answers |
|----------|---------|
| `README.md` | What keiki is and a first taste. |
| `ROADMAP.md` (this file) | What is released, what may come next, and what is out of scope. |
| `CHANGELOG.md` | The authoritative version-stamped package changes. |
| `docs/masterplans/` + `docs/plans/` | How each initiative was designed and delivered. |
| `docs/adr/` | The stable architecture decisions extracted from that work. |
| `docs/foundations/` + `docs/guide/` | How to learn and use the library. |
