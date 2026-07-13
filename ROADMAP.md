# keiki — Roadmap

This is a living status document. It records **what is already implemented**, what
remains before the first Hackage release, and what is deliberately deferred or out of
scope. For the authoritative, version-stamped change log see [`CHANGELOG.md`](CHANGELOG.md);
for milestone-by-milestone execution detail see the master plans in
[`docs/masterplans/`](docs/masterplans/) and their child exec-plans in
[`docs/plans/`](docs/plans/).

_Last updated: 2026-05-22._

## Status at a glance

- **Pre-1.0, pre-Hackage.** The next published release is `0.1.0.0`.
- **All 13 master-plan initiatives are complete.** The planned v0.1 surface — the
  symbolic-register transducer formalism described in
  [`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`](docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md)
  — has shipped.
- **Validated end-to-end** by the downstream `jitsurei` package (eight worked-example
  aggregates) plus ~260 in-tree `hspec` assertions, on GHC 9.12.2 (macOS aarch64 and
  Linux x86_64).
- **Only remaining gate to `0.1.0.0`:** maintainer-held release steps (the
  `tested-with` matrix expansion and the actual Hackage upload — EP-37 M2).

## What's implemented

Everything below is shipped and under test. The "Initiative" column links each
capability to the master plan that delivered it.

### The pure core (`Keiki.Core`)

- The `RegFile rs` typed register file and the `SymTransducer` GADT — the slot /
  predicate / command / event / output algebra.
- **List-shaped edge output** (`output :: [OutTerm rs ci co]`): one transition can
  emit zero, one, or N events in declaration order — a Generalized Sequential Machine,
  not a letter FST.
- Streaming replay: the `InFlight s co` wrapper, `applyEvent` (letter-only),
  `applyEventStreaming` (InFlight-aware), and `applyEvents` (atomic chunk replay over
  command boundaries); `reconstitute` for the full fold.
- `solveOutput` — mechanical inversion of each edge's output term, with the
  build-time **hidden-input** / **non-injective-output** checks that are the reason the
  library exists. _(Initiatives: MP-1, MP-2, MP-6, MP-7)_

### Authoring & ergonomics

- `Keiki.Builder` — the monadic edge-authoring DSL: `from` / `onCmd` / `goto` / `emit`,
  the `.=` (and synonym `=:`) slot-assignment operators, the `slot @"name"` writer and
  `reg @"name"` register-read helpers. _(MP-3, MP-13)_
- `Keiki.Generics` — `RegFieldsOf`, `GRecord`, `mkInCtor` / `mkWireCtor` (+ `…Via`
  variants), `mkWireCtor0` for singleton events, and `EmptyRegFile`. _(MP-3)_
- `Keiki.Generics.TH` — Template-Haskell derivation: enumerated `deriveAggregateCtors`
  / `deriveWireCtors` / `deriveView`, the zero-enumeration `deriveAggregateCtorsAll` /
  `deriveWireCtorsAll`, and the fused `deriveAggregate` that covers an aggregate's
  command and event constructors in one splice. _(MP-3, MP-13)_

### Derived projections

- `Keiki.Acceptor` — input- and output-side acceptor projections
  (`inputAcceptor` / `outputAcceptor` / `runAcceptor` / `accepts`). _(MP-5)_
- B-presentation per-vertex views via the `deriveView` splice (the `View`/`SVertex`
  GADTs). _(MP-5)_

### Composition & the typeclass tower

- `Keiki.Composition` — `compose` (sequential), `alternative` (sum-input dispatch over
  `Either`), and `feedback1` (single-step aggregate ↔ stateless-policy reduction); plus
  the n-ary `wireCtor3At*` / `inCtor3At*` / `outTerm3At*` injectors for arity-3 event
  families. _(MP-4, MP-8, MP-13)_
- `Keiki.Profunctor` — the existential `SomeSymTransducer` wrapper with the variance
  combinators (`lmapCi` / `rmapCo` / `dimapTransducer` / `lmapMaybeCi`) and the
  `Profunctor` / `Functor` / `Category` / `Strong` / `Choice` / `Arrow` instances.
  _(MP-9)_
  - **`Category`** is complete. `id` is a sentinel constructor (so the identity laws
    hold by definition); `(.)` delegates to `compose` after a **runtime** slot-name
    overlap check — the wrapper hides `rs`, so the static `Disjoint` constraint can't
    be discharged at the boundary. Overlap raises `CategoryOverlapError`; otherwise the
    disjointness evidence is `unsafeCoerce`-fabricated. Laws are covered behaviourally
    in `CategorySpec`.
  - **`Choice`** (`left'` / `right'`) is the cleanest of the arrow-flavored instances:
    it is built on `Keiki.Composition.alternative`, whose `leftInCtor` / `rightInCtor`
    arm wrappers are invertible, so it **preserves the `solveOutput` round-trip** (more
    preservation than `lmapCi` / `rmapCo`, which poison `icBuild`). The `left' id = id`
    law holds by construction. (`+++` / `|||` are not `Data.Profunctor.Choice` methods —
    they belong to `ArrowChoice`, which is out of scope.)
  - **`Strong`** (`first'` / `second'`) threads an unrelated value through a transducer
    (`first'` via `firstSym`, `second'` via `swap`). It **drops the `solveOutput`
    round-trip** — `firstSym` poisons the paired-input `icBuild`, so events on those
    edges can't be inverted (forward `delta` / `omega` is unaffected).
  - **`Arrow`** ships `arr`, but an `arr`-lifted function is opaque to the symbolic
    `Term` AST, so `arr` (like `Strong`) **drops the round-trip**, and `arr f >>> arr g`
    does **not** fuse to `arr (g . f)` — `arr` is a standalone adapter, not a
    composition primitive. This is a by-design boundary, not a gap (see below).

### Symbolic analysis (build-time only)

- `Keiki.Symbolic` — SBV + z3-backed `sat` / `isBot` / `isSingleValuedSym` analyses for
  the opt-in symbolic-CI single-valuedness gate.
- A memoizing translator, structural **arithmetic terms** (`TArith` / `NumOp`,
  `tadd`/`tsub`/`tmul`) in the term language, and real `sat` witnesses via the `Sat`
  class (the placeholder witness is retired). _(MP-2, MP-12)_
- These run only at build time; `delta` / `omega` / `applyEvent` use concrete predicate
  evaluation with no solver in the hot path.

### Output-invertibility & recompute-and-verify

- The exact output-invertibility contract is documented in
  [`docs/guide/output-invertibility.md`](docs/guide/output-invertibility.md) (which
  term shapes round-trip, which abort, and the `Nothing`-not-exception semantics).
- `solveOutput` now **recomputes and verifies derived event fields** on replay (via
  `recomputeDerivedFields` + `Eq co`), so an edge can emit a computed value and still
  certify round-trip safety. _(MP-13)_

### Persistence-adjacent & codecs

- `Keiki.Shape` — a GHC-upgrade-safe shape hash for snapshot discrimination
  (`CanonicalTypeName`, `KnownRegFileShape`, `regFileShapeHash`, `renderStableTypeRep`,
  `sha256Hex`), reusable by any codec. _(MP-11)_
- **`keiki-codec-json`** (sibling package) — the `RegFileToJSON` codec, its TH
  derivation helpers, a property-test toolkit for downstream codec users, and
  `tasty-bench` baselines. _(MP-11)_

### Visualization

- `Keiki.Render.Mermaid` — renderers for single transducers and composites (flat
  cross-product and nested Shape B), shape-aware renderers for `alternative` and
  `feedback1`, the `toMermaidAtlas` multi-diagram entry point, and opt-in structural
  edge-summary annotations (`MermaidOptions` / `toMermaidWith`). _(MP-10, MP-13)_

### Strictness & examples

- `Keiki.NoThunks` — strict-evaluation assertions for the register file and per-vertex
  state. _(MP-3 era)_
- Worked aggregates driving the suite: `UserRegistration`, `OrderCart`,
  `EmailDelivery`, the cross-context `LoanApplication`, and more in the downstream
  `jitsurei` package (eight aggregates total). _(MP-1, MP-4, MP-7, MP-13)_

### Master-plan ledger

| #  | Initiative | Status |
|----|------------|--------|
| 1  | Validate symbolic-register direction via Haskell prototype | ✅ Complete |
| 2  | Retire v1 escape hatches (TInpProj + SBV BoolAlg) | ✅ Complete |
| 3  | `Keiki.Generics` DX follow-ups (TH, Decider facade) | ✅ Complete |
| 4  | Composition combinators on `SymTransducer` (`compose`) | ✅ Complete |
| 5  | Acceptor projections and `genView` TH splice (B-presentation) | ✅ Complete |
| 6  | Retire remaining escape hatches (OFn, PMatchC, `unsafeCombine`) | ✅ Complete |
| 7  | Multi-event command support (GSM widening) | ✅ Complete |
| 8  | Composition beyond sequential (`alternative`, `feedback1`) | ✅ Complete |
| 9  | Profunctor / Category / Strong / Choice / Arrow instances | ✅ Complete |
| 10 | Mermaid topology renderer | ✅ Complete |
| 11 | `keiki-codec-json` package — implementation and rollout | ✅ Complete |
| 12 | Symbolic arithmetic terms, memoization, real `sat` witnesses | ✅ Complete |
| 13 | API improvements surfaced by the Rei migration | ✅ Complete |

## What's next

### Toward `0.1.0.0` (the immediate milestone)

The public surface is frozen and the changelog drafted; the coordinated Hackage release
(EP-37) is held for the maintainer. Remaining steps:

- Expand the `tested-with` GHC matrix and run it (EP-37 M2).
- Add `source-repository head` stanzas (deferred during metadata polish).
- Publish `keiki` and `keiki-codec-json` to Hackage per
  [`docs/research/release-procedure.md`](docs/research/release-procedure.md).

### Deferred by design / candidate future work

These were considered and consciously deferred, not forgotten:

- **`parallel` and `Kleisli` composition combinators** — re-deferred in MP-8 after the
  design milestone admitted only `alternative` and `feedback1`.
- **`ArrowChoice`** (`+++` / `|||`) on `SomeSymTransducer` — declared out of scope in
  MP-9.
- **Law-faithful `Arrow` fusion** (`arr f >>> arr g == arr (g . f)`) — *won't-do, by
  design.* Honoring it would require putting arbitrary function application into the
  symbolic `Term` AST, which would make terms untranslatable to SBV and break the
  build-time invertibility / single-valuedness guarantees keiki exists to provide.
  `arr` stays an adapter, not a composition primitive.
- **DOT / Graphviz rendering** — listed as a future Mermaid-alternative format,
  deferred in MP-10.
- **Schema evolution** — the design note
  ([`docs/research/schema-evolution.md`](docs/research/schema-evolution.md)) is written;
  the contract is still being sharpened against real consumers.

### Explicitly out of scope for the pure core

These are runtime concerns by design and live (or will live) in sibling packages, not
in `keiki`:

- **Serialization** — JSON / CBOR / Protobuf codecs. JSON ships today as
  `keiki-codec-json`; other formats would follow the same sibling-package pattern. The
  `Keiki.Shape` hash discriminates snapshots regardless of codec.
- **Runtime, effects, persistence, timers, and the process-manager driver** — I/O and
  durability concerns the pure transducer deliberately does not own (see
  [`docs/research/effects-boundary.md`](docs/research/effects-boundary.md)).

## Reading this alongside the other docs

| Document | Answers |
|----------|---------|
| `README.md` | What keiki is and a first taste. |
| `ROADMAP.md` (this file) | What's done, what's next, what's out of scope. |
| `CHANGELOG.md` | The authoritative, version-stamped change log. |
| `docs/masterplans/` + `docs/plans/` | How each capability was designed and delivered. |
| `docs/foundations/` + `docs/guide/` | How to learn and use the library. |
