# Comparison: keiki vs. crem

[crem](https://github.com/tweag/crem) (Compositional Representable
Executable Machines) is a Haskell library by Marco Sampellegrini that
provides composable Mealy machines with type-level topology enforcement.
It has a built-in Decider pattern, visualization, and a rich profunctor /
category hierarchy.

This document compares the two architectures, identifies what each does
well, and considers what a synthesis might look like. It supersedes the
earlier comparison written when the project was called *fst-aggregate*
and most of keiki's user-facing surface was still proposed; that
prototype-era framing no longer matches what `Keiki.*` ships.

For a code-level comparison of the same trade-offs through a non-trivial
worked example, see
`worked-comparison-loanworkflow-keiki-vs-crem.md` — it walks the
three-aggregate LoanWorkflow (intake aggregate, downstream aggregate,
process manager, async cross-context wiring) through both libraries
side by side.

---

## Architectural overview

```
keiki                                               crem
─────                                               ────

SymTransducer phi rs s ci co                        BaseMachineT m topology input output
  edgesOut    :: s -> [Edge phi rs ci co s]           action :: state v -> input
  initial     :: s                                           -> ActionResult m topology state v output
  initialRegs :: RegFile rs                           initialState :: InitialState state
  isFinal     :: s -> Bool

Edge phi rs ci co s                                 StateMachineT m input output
  guard  :: phi                                       = Basic BaseMachineT
  update :: Update rs w ci  -- existential w          | Sequential SM SM
  output :: Maybe (OutTerm rs ci co)                  | Parallel SM SM
  target :: s                                         | Alternative SM SM
                                                      | Feedback SM SM
                                                      | Kleisli SM SM
Top-level pure-core entry points
  delta, omega, step, applyEvent                    Decider topology input output
  reconstitute, applyEvents                           decide :: input -> state v -> output
  solveOutput, checkHiddenInputs                      evolve :: state v -> output
                                                             -> EvolutionResult topology state v output
Façades / lenses on the transducer
  toDecider       (Chassaing-shape Decider)
  toMultiDecider  (multi-event Decider)
  inputProjection / outputProjection (Acceptors)

Composition (Keiki.Composition)
  compose, alternative, feedback1
  (parallel, Kleisli re-deferred)

Wrapper for the profunctor ecosystem (Keiki.Profunctor)
  SomeSymTransducer ci co
  Profunctor, Functor, Category, Choice, Strong, Arrow instances
  lmapCi, lmapMaybeCi, rmapCo, dimapTransducer, identityTransducer,
    firstSym, arrTransducer
  (ArrowChoice, Closed/Costrong/Cochoice out of scope)

Symbolic layer (Keiki.Symbolic)
  SymPred, BoolAlg via SBV/Z3
  sat, isBot, isSingleValuedSym, symSatExt

Authoring surface
  Keiki.Builder   — QualifiedDo edge DSL
  Keiki.Generics  — derive InCtor / WireCtor / RegFile
```

The core difference: **keiki models a symbolic-register transducer with
structurally-typed input/output alphabets and derives the decider via
projection. crem models a Mealy machine with type-level topology
constraints and provides the decider as a separate pattern.**

---

## Detailed comparison

### 1. State-transition enforcement

**crem: compile-time via type-level topology.**

```haskell
type RegTopology = 'Topology
  '[ '( 'PotentialCustomer, '[ 'RequiresConfirmation ])
   , '( 'RequiresConfirmation, '[ 'RequiresConfirmation, 'Confirmed, 'Deleted ])
   , '( 'Confirmed, '[ 'Deleted ])
   ]

action SConfirmed StartRegistration =
  -- ↑ TYPE ERROR: no AllowedTransition proof for Confirmed → RequiresConfirmation
```

Invalid transitions are compile-time errors. The `AllowTransition` GADT
provides an inductive proof that the transition exists in the topology,
discharged automatically by typeclass resolution.

**keiki: runtime via the edge guard.**

```haskell
edgesOut PotentialCustomer =
  [ Edge { guard = matchInCtor inpStartRegistration, …, target = RequiresConfirmation } ]
edgesOut Confirmed =
  [ Edge { guard = matchInCtor inpRequestDelete,    …, target = Deleted } ]
```

`delta` returns `Just` only when exactly one outgoing edge fires. An
attempted invalid transition simply has no edge — `delta` returns
`Nothing`. The symbolic layer (§6) compensates partially by making
guard satisfiability machine-checkable at build time.

**Trade-off (refreshed):**

| Aspect              | crem (type-level)         | keiki (edge-guarded + symbolic) |
|---------------------|---------------------------|--------------------------------|
| Invalid transition  | Compile error             | Runtime `Nothing`              |
| Empty edge set      | Type error at the call site | Runtime `Nothing` (statically detectable per vertex) |
| Compile time        | Heavy (singletons, GADT proof search) | Fast |
| Topology changes    | Recompile downstream      | Edit `edgesOut`                 |
| Dependencies        | singletons-base, singletons-th | sbv (z3 at runtime), profunctors, nothunks |
| Build-time analysis | None                      | `checkHiddenInputs`, `isBot`, `isSingleValuedSym` (SBV) |

### 2. Rich data types: commands, events, and states

This is the most consequential structural difference between the two
libraries, and the one the previous version of this note glossed over.

**State.** Both libraries can attach data to the lifecycle position:

- crem fuses position and data into a vertex-indexed GADT
  `AggregateState (vertex :: AggregateVertex)`, where each constructor
  carries the data appropriate for that vertex
  (`CollectedUserData :: UserData -> AggregateState 'CollectedUserDataVertex`).
- keiki separates them: a plain `s` vertex value rides alongside a
  typed register file `RegFile rs` indexed by a slot list `[Slot]` (a
  `Symbol`-keyed heterogeneous tuple). Slots are written via
  `Update rs w ci`, whose `w :: [Symbol]` index records the set
  written; the smart `combine` requires `Disjoint w1 w2`, so writing
  the same slot twice on one edge is a *compile-time* error.

The shape is different but both capture per-vertex typed data. crem's
fusion is more compact when all per-vertex data is mandatory; keiki's
register-file separation makes per-slot lifetimes (when a slot becomes
defined, when it is overwritten) a first-class authoring concern and
enables generic snapshot codecs.

**Commands.** Here the libraries diverge sharply.

- crem's commands are a plain monomorphic `Type`. `BaseMachineT m
  topology (input :: Type) (output :: Type)` says nothing about the
  structure of `input`. The RiskManager example is just
  `data RiskCommand = RegisterUserData UserData | …`. Authors hand-
  pattern-match every (state, command) pair inside `action`. There is
  no per-constructor field schema, no per-edge constructor binding,
  and commands are *not* indexed by vertex — every `state` arm of
  `action` must handle every constructor of `input`.
- keiki's commands are also a plain user ADT (`ci :: Type`), but the
  framework binds individual constructors to individual edges via
  `InCtor ci ifs`. The `ifs :: [Slot]` is the constructor's field
  schema; the carried `icMatch :: ci -> Maybe (RegFile ifs)` and
  `icBuild :: RegFile ifs -> ci` form a typed round-trip (laws:
  `icMatch (icBuild rf) == Just rf`). An edge that wants to read a
  command's payload uses `inpCtor ic ix` (or `#fieldName` via
  `OverloadedLabels`), typed by slot name. `Keiki.Generics` derives the
  `InCtor` mechanically from the user's `Generic` instance.

The practical implication is that, in keiki, the command alphabet has a
structural type-level handle that the framework can analyse:
`solveOutput` walks an `OPack` against an `InCtor` to invert events
back to commands; `checkHiddenInputs` flags edges whose update reads a
command field that the output doesn't carry; the symbolic layer can
express constructor mutual exclusion directly as `PInCtor` and have
SBV recognise it. In crem, commands are opaque Haskell values that
only the `action` lambda's hand-written pattern matches understand.

**Events.** Symmetric to commands.

- crem's `output :: Type` is a plain ADT. The author writes events by
  hand inside `action`; nothing is automatically derivable from an
  event back to its producing state or command. `rebuildDecider` folds
  events through the user's `evolve`, which the user must keep
  consistent with `decide`.
- keiki's events are produced by
  `OPack :: InCtor ci ifs -> WireCtor co fields -> OutFields rs ci fields -> OutTerm rs ci co`.
  The `WireCtor` gives the event's structural schema; `OutFields` is a
  typed HList of the fields. Because `OPack` records both the producing
  input constructor (`InCtor`) and the field structure, `solveOutput`
  mechanically inverts an observed event back to the command that
  produced it — which is exactly what `applyEvent` and `reconstitute`
  use to rebuild state from an event log without storing the producing
  command.

**The vertex-indexing question.** Neither library indexes commands or
events by vertex at the type level. crem doesn't because they're plain
`Type`s. keiki doesn't either — `ci` and `co` are uniform across the
machine. The closest analogue in keiki is that each edge can guard on
`matchInCtor ic`, restricting the constructors that can fire that edge;
the SBV-backed `BoolAlg` recognises these constructor guards as
mutually exclusive. So per-vertex *constructor restrictions* are
expressible *and provable*, but the constructor's payload type is not
vertex-dependent.

**Summary:** state is rich in both. Commands and events are richly
*structured* in keiki (per-constructor field schemas, mechanical
inversion, generic derivation, symbolic guards) but are plain Haskell
ADTs in crem.

### 3. Composition

**crem: GADT tree with six constructors plus the full profunctor
hierarchy:**

```haskell
data StateMachineT m a b where
  Basic       :: BaseMachineT m topology a b -> StateMachineT m a b
  Sequential  :: StateMachineT m a b -> StateMachineT m b c -> StateMachineT m a c
  Parallel    :: StateMachineT m a b -> StateMachineT m c d -> StateMachineT m (a,c) (b,d)
  Alternative :: StateMachineT m a b -> StateMachineT m c d -> StateMachineT m (Either a c) (Either b d)
  Feedback    :: StateMachineT m a (n b) -> StateMachineT m b (n a) -> StateMachineT m a (n b)
  Kleisli     :: StateMachineT m a (n b) -> StateMachineT m b (n c) -> StateMachineT m a (n c)
```

Plus `Category`, `Profunctor`, `Strong`, `Choice`, `Arrow`, and
`ArrowChoice` instances on `StateMachineT`.

**keiki: three primitive combinators plus a profunctor wrapper.**

`Keiki.Composition` exports:

- `compose` — sequential composition. The `Disjoint (Names rs1) (Names rs2)`
  constraint statically rejects slot-name collisions between the two
  composed register files.
- `alternative` — `Either` dispatch on the input alphabet.
- `feedback1` — single-step feedback (`feedback1 t f = compose t (compose f t)`)
  modelling one round of an aggregate ↔ policy loop.

`Keiki.Profunctor` exports the existential wrapper
`SomeSymTransducer ci co` (hiding `s` and `rs`) plus `Profunctor` and
`Functor` instances and the standalone variance combinators (`lmapCi`,
`lmapMaybeCi`, `rmapCo`, `dimapTransducer`).

**Combinator parity:**

| Combinator   | crem                  | keiki                                     | DDD meaning                       |
|--------------|-----------------------|-------------------------------------------|-----------------------------------|
| Sequential   | `Category (.)`         | `compose`                                  | Saga / pipeline                   |
| Alternative  | `Alternative` / `Choice` | `alternative` + `Choice SomeSymTransducer` (EP-29 M1) | Command routing       |
| Feedback     | `Feedback`             | `feedback1` (single-step)                  | Aggregate ↔ policy loop           |
| Profunctor   | `Profunctor`           | `Profunctor SomeSymTransducer`             | Variance / contramap routing      |
| Parallel     | `Parallel` / `Strong`  | `Strong SomeSymTransducer` via in-house `firstSym` (EP-29 M2; MP-8 declined a general `parallel`) | Independent invariants |
| Kleisli      | `Kleisli`              | Re-deferred (MP-8 EP-24)                   | Multi-event pipeline              |
| Category     | `Category`             | `Category SomeSymTransducer` (EP-28)       | Composition identity              |
| Arrow        | `Arrow`                | `Arrow SomeSymTransducer` (EP-29 M3)       | Arrow notation / ecosystem hook   |
| ArrowChoice  | `ArrowChoice`          | Out of scope (EP-29 Decision Log)          | Arrow + Choice tower              |

MP-9 closes the typeclass tower: `Profunctor`, `Functor`, `Category`,
`Choice`, `Strong`, and `Arrow` all ship on `SomeSymTransducer`.
`ArrowChoice` and the wider profunctor classes (`Closed`, `Costrong`,
`Cochoice`) stay out of scope until a real authoring need surfaces.
`parallel` and `Kleisli` remain re-deferred per MP-8's design
milestone — `Strong` is implemented from primitives in EP-29 M2
rather than waiting for or reviving `parallel`.

/Lossy-`solveOutput` caveat:/ transducers produced by `lmapCi`,
`rmapCo`, `dimapTransducer`, `first'`, `second'`, and `Arr.arr` ship
with a documented inversion gap — `Keiki.Core.solveOutput` returns
`Nothing` on these. Forward processing (`delta`, `omega`, `evalPred`,
`evalTerm`) is unaffected. Replay-from-events users who need the
inversion path should construct their transducers without going
through these combinators.

### 4. Decider pattern

**crem: separate pattern; `decide` returns the output, `evolve` consumes it.**

```haskell
data Decider topology input output = forall state. Decider
  { deciderInitialState :: InitialState state
  , decide :: forall v. input -> state v -> output
  , evolve :: forall v. state v -> output -> EvolutionResult topology state v output
  }

rebuildDecider :: [output] -> Decider … -> Decider …
```

The user defines `decide` and `evolve` independently and is responsible
for keeping them consistent.

**keiki: Chassaing-shape Decider derived from the SymTransducer.**

```haskell
-- Keiki.Decider
data Decider c e s = Decider
  { decide       :: c -> s -> [e]
  , evolve       :: s -> e -> s
  , initialState :: s
  , isTerminal   :: s -> Bool
  }

toDecider      :: BoolAlg phi (RegFile rs, ci)
               => SymTransducer phi rs s ci co
               -> Decider ci co (s, RegFile rs)

toMultiDecider :: BoolAlg phi (RegFile rs, ci)
               => SymTransducer phi rs s ci co
               -> DriverConfig s ci
               -> Decider ci [co] (s, RegFile rs)
```

`decide` is built on `omega`; `evolve` is built on `applyEvent`, whose
inverse step (`solveOutput`) is mechanically derived from the producing
edge's `OPack`. The two directions agree on every non-ε edge by
construction. Two semantic gaps remain (documented in
`Keiki.Decider`'s haddock):

- ε-edges (`output = Nothing`) advance state through `delta` but are
  invisible to `evolve` — the Decider façade omits them. Use
  `Keiki.Core.delta` directly when ε-driven transitions matter.
- A single command produces at most one event under `toDecider`; the
  multi-event façade (`toMultiDecider`) drives chains of letter edges
  through user-declared internal vertices via a `DriverConfig`.

| Aspect                  | crem                                 | keiki                                     |
|-------------------------|--------------------------------------|-------------------------------------------|
| Decider is              | Independently defined                | Derived from `SymTransducer`              |
| Consistency             | User must keep `decide`/`evolve` in agreement | Guaranteed by derivation (modulo ε-edges) |
| Topology constraints    | Enforced in `EvolutionResult`        | None at this layer (runtime guard)        |
| Snapshot / rebuild      | `rebuildDecider` returns a Decider   | `reconstitute`, `applyEvent`, `applyEvents` |
| Multi-event support     | List output via `Sequential` shaping | First-class `toMultiDecider` + `DriverConfig` |

### 5. Automata-theoretic operations

`Keiki.Acceptor` ships first-class projections of a `SymTransducer`:

- `inputProjection  :: SymTransducer phi rs s ci co -> Acceptor ci (s, RegFile rs)`
  — the input acceptor (π₁), accepting iff a sequence of commands runs
  to a final vertex.
- `outputProjection :: SymTransducer phi rs s ci co -> Acceptor co (s, RegFile rs)`
  — the output acceptor (π₂), accepting iff a sequence of events
  replays to a final vertex; this is the formal underpinning of event
  sourcing as projection.

crem has no concept of projecting a machine onto its input or output
language, no `Acceptor` type, and no separate notion of accepting a
sequence without running the full machine.

### 6. Symbolic analysis (keiki only)

`Keiki.Symbolic` translates `HsPred rs ci` to SBV expressions and
discharges them through Z3. The SBV-backed `BoolAlg (SymPred rs ci)`
instance gives:

- `sat`   — produce a concrete `(RegFile rs, ci)` witness for a guard.
- `isBot` — prove a guard is unsatisfiable (an edge that can never fire).
- `isSingleValuedSym` — prove an output term is single-valued
  (deterministic) for the satisfying inputs.
- `symSatExt` — extract a witness restricted to one named `InCtor`
  (used by builder-time pattern checks).

This is the cleanest `keiki`-only capability. crem has no symbolic
layer; guards (when modelled at all) are opaque Haskell `Bool`s, and
there is no way to ask "can this edge ever fire?" or "is this output
deterministic?" without testing.

### 7. Authoring surface

**crem:** authors write `BaseMachineT` records by hand, with the
`action` field as a nested `\case … \case …` over (state, input). The
topology singleton is defined separately and threaded through types.

**keiki:** two authoring layers.

- `Keiki.Builder` is a `QualifiedDo` edge DSL with `goto`, `emit`,
  `requireEq`, field-keyed `(.=)` writes, multi-event chains, and
  compile-time checks for duplicate slot writes, missing `goto`, and
  multiple `goto`s per edge.
- `Keiki.Generics` derives `InCtor`, `WireCtor`, and a `RegFile`
  template from the user's `Generic` instance, removing the field-
  schema boilerplate that the structural alphabets would otherwise
  require.

crem has no equivalent authoring DSL or generics derivation.

### 8. State representation

**crem: vertex-indexed GADT, existentially quantified.**

```haskell
data RegState (v :: RegVertex) where
  SPotentialCustomer    :: RegState 'PotentialCustomer
  SRequiresConfirmation :: Email -> RegState 'RequiresConfirmation
```

State carries data and encodes the current lifecycle position at the
type level. The vertex index determines which transitions are valid.
State is existentially quantified inside `BaseMachineT` — consumers
can't inspect it without running the machine.

**keiki: separate vertex `s` plus typed register file `RegFile rs`.**

```haskell
data SymTransducer phi rs s ci co = SymTransducer
  { edgesOut    :: s -> [Edge phi rs ci co s]
  , initial     :: s
  , initialRegs :: RegFile rs
  , isFinal     :: s -> Bool
  }
```

The vertex `s` is plain (typically a sum type). Per-vertex data lives
in the register file as named slots. Both are visible to consumers
(useful for reconstitution, testing, snapshotting).

**Trade-off:** crem's indexed state is more expressive in one specific
sense — the vertex statically narrows which slots exist. keiki's
register file is uniform across vertices but compensates with the
slot-name disjointness checks on writes (`Disjoint`), the symbolic
analyses on reads, and the generic snapshot codec
(EP-36 `RegFile` JSON + shape hash).

### 9. Effects

**crem: monad-parameterised from the start.**

```haskell
data BaseMachineT m topology input output = …
type BaseMachine topology a b = forall m. Monad m => BaseMachineT m topology a b
hoist :: (forall x. m x -> n x) -> StateMachineT m a b -> StateMachineT n a b
```

**keiki: pure core + runtime adapter (settled boundary).**

`Keiki.Core` is intentionally `IO`-free. The contract pinned in
`docs/research/effects-boundary.md` is: the pure layer computes
`step`, `reconstitute`, `applyEvent`, the analyses; the runtime layer
(future `Keiki.Runtime`) handles the event store, dispatch, timers,
subscriptions, snapshotting.

The trade-off: crem mixes effects directly into the machine type;
keiki keeps the machine pure and lets the runtime monomorphise the
effect context.

### 10. Visualization

Both libraries render Mermaid.

- crem's `Crem.Render.*` walks the topology and the composition tree
  to produce both per-machine state diagrams and composition flow
  diagrams; composed machines use graph products and transitive
  closure to compute the effective topology.
- keiki's `Keiki.Render.Mermaid` ships single-machine renderers and
  shape-aware composite renderers (`compose`, `alternative`,
  `feedback1`, plus right-associative 3-deep `compose` and shape-B
  nested subgraphs). `docs/guide/diagrams/` carries the canonical
  example outputs.

### 11. Production readiness

| Aspect                   | crem                          | keiki                                              |
|--------------------------|-------------------------------|----------------------------------------------------|
| Effect support           | Built-in (`m` parameter)      | Pure core + runtime adapter (boundary settled)     |
| NoThunks                 | Yes                           | `Keiki.NoThunks` (RegFile + SymTransducer state)   |
| machines integration     | Yes (`AutomatonM`)             | No                                                 |
| Streaming                | Via `machines` `ProcessT`      | No                                                 |
| Visualization            | Built-in Mermaid               | Built-in Mermaid (composite-aware)                 |
| Compile-time safety      | Type-level topology            | Disjoint slot writes, structural InCtor, symbolic `isBot` |
| Snapshot support         | `rebuildDecider` from any point | `reconstitute`, `applyEvents`, EP-36 RegFile JSON codec |
| Symbolic analysis        | None                          | SBV / Z3 (`sat`, `isBot`, `isSingleValuedSym`)    |
| Authoring DSL            | None                          | `Keiki.Builder` (QualifiedDo)                     |
| Generic derivation       | None                          | `Keiki.Generics` (InCtor / WireCtor / RegFile)    |
| Dependencies             | Heavy (singletons, profunctors, machines, nothunks) | Moderate (sbv + z3, profunctors, nothunks, template-haskell) |

---

## What each architecture does best

### crem excels at

1. **Compile-time transition safety** — invalid transitions are type
   errors, not runtime failures.
2. **Profunctor / category ecosystem** — the full `Strong`, `Choice`,
   `Arrow`, `ArrowChoice` tower on the existential wrapper, idiomatic
   Haskell composition with Arrow notation.
3. **Effect monad parameterisation** — machines are first-class
   effectful computations; `hoist` swaps the effect context.
4. **machines integration** — drop into existing streaming pipelines.
5. **Vertex-indexed state** — state can carry different data per
   lifecycle position, enforced by types, with no separate
   register-file machinery.

### keiki excels at

1. **Structurally-typed alphabets** — `InCtor` and `WireCtor` make
   commands and events first-class structural objects with field
   schemas, not opaque Haskell values. Mechanical inversion
   (`solveOutput`), build-time analysis (`checkHiddenInputs`), and
   symbolic guards (`PInCtor`) all fall out of this.
2. **Mathematical foundation** — grounded in automata theory with
   formal operations (input/output projection, sequential composition,
   alternative, single-step feedback).
3. **Derivation over assumption** — the Decider is derived from the
   transducer via projection, not independently defined; consistency
   between `decide` and `evolve` is structural rather than user-
   maintained.
4. **Symbolic analysis** — SBV/Z3 lets the framework prove guard
   unsatisfiability, output single-valuedness, and constructor mutual
   exclusion at build time.
5. **Compile-time slot discipline** — `Disjoint` on `combine` rejects
   double-writes; `KnownSlotNames` carries slot names for diagnostics
   and snapshot codecs.
6. **Authoring ergonomics** — the `Keiki.Builder` QualifiedDo DSL plus
   `Keiki.Generics` removes nearly all boilerplate from authoring
   structural alphabets.

---

## What each could learn from the other

### crem could adopt from keiki

| Concept                                   | Value                                                                 |
|-------------------------------------------|-----------------------------------------------------------------------|
| `inputProjection` / `outputProjection`    | Validate command/event sequences independently of the full machine.   |
| Structural `InCtor` / `WireCtor`          | Per-edge field schemas; mechanical inverse for event replay.          |
| Formal projection proof for `evolve`      | Mathematical guarantee that `decide` and `evolve` agree.              |
| Symbolic `BoolAlg`                        | Guard satisfiability and constructor mutual-exclusion proofs.         |
| Generic-derived alphabets                 | Remove the boilerplate cost of structurally typing commands/events.   |

### keiki could adopt from crem

| Concept                                   | Value                                                                 |
|-------------------------------------------|-----------------------------------------------------------------------|
| Type-level topology                       | Compile-time transition enforcement, not just runtime guard failure.  |
| Vertex-indexed state GADTs                | Per-vertex typed state data without a separate register-file layer.   |
| `ArrowChoice`, `Closed`, `Costrong`, `Cochoice` | Wider profunctor / arrow tower; out of scope for MP-9. |
| `Parallel` / `Kleisli` combinators        | Two re-deferred composition shapes (MP-8 EP-24 decision log; `Strong` ships from primitives in EP-29 M2 instead). |
| Effect monad parameterisation in the core | `hoist` to swap effect contexts; today keiki's effect story lives entirely in the runtime layer. |
| `machines` integration                    | Streaming via `ProcessT`.                                             |

---

## Synthesis: how converged are the two now?

The original version of this note proposed a layered synthesis under
the assumption that nothing of crem's combinator/typeclass tower
existed in fst-aggregate. That picture has shifted:

- **Layer 1 (core machine).** keiki ships
  `SymTransducer phi rs s ci co` with structural `InCtor`/`WireCtor`,
  register-file with disjoint writes, and edge-guarded transitions.
  The compile-time topology slot remains crem's; importing it would
  require singletons or a similar type-level encoding.
- **Layer 2 (automata operations).** keiki ships `inputProjection`,
  `outputProjection`, `Acceptor`, `toDecider`, `toMultiDecider`. crem
  has none of these.
- **Layer 3 (composition).** keiki ships `compose`, `alternative`,
  `feedback1`, plus the typeclass tower `Profunctor`, `Functor`,
  `Category`, `Choice`, `Strong`, `Arrow` on the existential wrapper
  `SomeSymTransducer` (MP-9 closed 2026-05-09). `parallel` and
  `Kleisli` remain re-deferred per MP-8's design milestone (`Strong`
  ships from in-house primitives in EP-29 M2 rather than waiting for
  `parallel`). `ArrowChoice` and the wider profunctor tower
  (`Closed`, `Costrong`, `Cochoice`) stay out of scope until a real
  authoring need surfaces.

The synthesis question that remains genuinely interesting is
**topology safety**: whether keiki should add an optional type-level
topology layer on top of the existing register-file core, paying the
singletons cost only for users who want compile-time transition
enforcement. The boundary note is silent on this; it's a candidate
research thread rather than a planned milestone.

---

## Summary

| Dimension                  | crem                                              | keiki                                                       |
|----------------------------|---------------------------------------------------|-------------------------------------------------------------|
| Core idea                  | Composable Mealy machines with type-level topology | Symbolic-register transducer with structural alphabets      |
| Transition safety          | Compile-time (GADTs)                              | Runtime guard + symbolic analysis                           |
| Command/event richness     | Plain `Type`; user-pattern-matched                 | `InCtor`/`WireCtor` field schemas; mechanically inverted    |
| State                      | Vertex-indexed GADT                                | Plain vertex + typed `RegFile`                              |
| Composition                | 6 combinators + full profunctor tower              | `compose`, `alternative`, `feedback1`, `Profunctor` (more planned) |
| Event sourcing             | Decider pattern (assumed consistent)               | `toDecider` / `toMultiDecider` derived via projection       |
| Formal operations          | None                                              | Projection, composition, single-step feedback              |
| Symbolic analysis          | None                                              | SBV / Z3 (`sat`, `isBot`, `isSingleValuedSym`)             |
| Authoring                  | Hand-written `BaseMachineT`                        | `Keiki.Builder` DSL + `Keiki.Generics`                     |
| Effects                    | Built-in (monad parameter)                         | Pure core + runtime adapter (boundary settled)              |
| Visualization              | Built-in (Mermaid)                                 | Built-in (Mermaid, composite-aware)                         |
| Dependencies               | singletons, profunctors, machines                  | sbv (z3), profunctors, nothunks, template-haskell          |
| Best for                   | Production systems wanting compile-time topology   | Structurally-typed alphabets, symbolic analysis, derived event sourcing |

Neither library is strictly better. crem still wins on type-level
topology enforcement and the full profunctor/category tower. keiki has
substantially closed the original "missing combinators" gap and now
clearly leads on structural alphabets, symbolic analysis, derived
event sourcing, and authoring ergonomics. The remaining synthesis
question is whether keiki should import an opt-in type-level topology
layer on top of its current core.
