# Comparison: fst-aggregate vs. crem

[crem](https://github.com/tweag/crem) (Compositional Representable
Executable Machines) is a Haskell library by Marco Sampellegrini that
provides composable Mealy machines with type-level topology enforcement.
It has a built-in Decider pattern, visualization, and a rich profunctor/
category hierarchy.

This document compares the two architectures, identifies what each does
well, and considers what a synthesis might look like.

---

## Architectural Overview

```
fst-aggregate                               crem
────────────                                ────

Transducer s c e                            BaseMachineT m topology input output
  delta :: s -> c -> Maybe s                  action :: state v -> input
  omega :: s -> c -> Maybe e                         -> ActionResult m topology state v output
  initial :: s                                  initialState :: InitialState state
  isFinal :: s -> Bool
                                            StateMachineT m input output
     │                                        = Basic BaseMachineT
     ├── inputProjection → Acceptor             | Sequential SM SM
     ├── outputProjection → Acceptor            | Parallel SM SM
     ├── toDecider → Decider                    | Alternative SM SM
     ├── union                                  | Feedback SM SM
     └── concatenate                            | Kleisli SM SM

Decider c e s                               Decider topology input output
  exec  :: s -> c -> Maybe e                  decide :: input -> state v -> output
  apply :: s -> e -> Maybe s                  evolve :: state v -> output
  initial :: s                                       -> EvolutionResult topology state v output
  isFinal :: s -> Bool
```

The core difference: **fst-aggregate models a transducer and derives the
decider via projection. crem models a Mealy machine with type-level
topology constraints and provides the decider as a separate pattern.**

---

## Detailed Comparison

### 1. State Transition Enforcement

**crem: Compile-time via type-level topology**

```haskell
-- Topology defined at the type level
type RegTopology = 'Topology
  '[ '( 'PotentialCustomer, '[ 'RequiresConfirmation ])
   , '( 'RequiresConfirmation, '[ 'RequiresConfirmation, 'Confirmed, 'Deleted ])
   , '( 'Confirmed, '[ 'Deleted ])
   ]

-- State is a GADT indexed by vertex
data RegState (v :: RegVertex) where
  SPotentialCustomer    :: RegState 'PotentialCustomer
  SRequiresConfirmation :: Email -> RegState 'RequiresConfirmation
  SConfirmed            :: Email -> RegState 'Confirmed
  SDeleted              :: RegState 'Deleted

-- AllowedTransition proof required in ActionResult
action :: RegState v -> RegCommand -> ActionResult m RegTopology RegState v RegEvent
action SPotentialCustomer (StartRegistration email) =
  ActionResult $ pure (ConfirmationSent, SRequiresConfirmation email)
  -- ↑ compiles only if AllowedTransition RegTopology 'PotentialCustomer 'RequiresConfirmation

action SConfirmed StartRegistration =
  -- ↑ TYPE ERROR: no AllowedTransition proof for Confirmed → RequiresConfirmation
```

Invalid transitions are **compile-time errors**. The `AllowTransition` GADT
provides an inductive proof that the transition exists in the topology.

**fst-aggregate: Runtime via `Maybe`**

```haskell
delta :: RegState -> RegCommand -> Maybe RegState
delta PotentialCustomer StartRegistration = Just RequiresConfirmation
delta Confirmed         StartRegistration = Nothing  -- runtime rejection
```

Invalid transitions return `Nothing`. Caught at runtime, tested with
Hedgehog.

**Trade-off:**

| Aspect | crem (type-level) | fst-aggregate (runtime) |
|--------|-------------------|------------------------|
| Invalid transition | Compile error | Runtime `Nothing` |
| Error messages | GHC type errors (can be cryptic) | Clear `Maybe` handling |
| Compile time | Heavy (singletons, GADT proof search) | Fast |
| State can carry data | Yes (`SRequiresConfirmation :: Email -> ...`) | Plain enum |
| Topology changes | Recompile everything downstream | Just update pattern match |
| Dependencies | singletons-base, singletons-th | None (base only) |

### 2. Composition

**crem: GADT tree with 6 constructors**

```haskell
data StateMachineT m a b where
  Basic       :: BaseMachineT m topology a b -> StateMachineT m a b
  Sequential  :: StateMachineT m a b -> StateMachineT m b c -> StateMachineT m a c
  Parallel    :: StateMachineT m a b -> StateMachineT m c d -> StateMachineT m (a,c) (b,d)
  Alternative :: StateMachineT m a b -> StateMachineT m c d -> StateMachineT m (Either a c) (Either b d)
  Feedback    :: StateMachineT m a (n b) -> StateMachineT m b (n a) -> StateMachineT m a (n b)
  Kleisli     :: StateMachineT m a (n b) -> StateMachineT m b (n c) -> StateMachineT m a (n c)
```

Plus full typeclass hierarchy: `Category`, `Profunctor`, `Strong`, `Choice`,
`Arrow`, `ArrowChoice`.

**fst-aggregate: Two operations (union, concatenation)**

```haskell
union       :: Acceptor s1 a -> Acceptor s2 a -> Acceptor (s1,s2) a
concatenate :: Acceptor s1 a -> Acceptor s2 a -> Acceptor (Either s1 s2) a
compose     :: Transducer s1 c e1 -> Transducer s2 e1 e2 -> Transducer (s1,s2) c e2  -- proposed
```

No profunctor/category instances yet (proposed in FUTURE-DIRECTIONS).

**What crem has that we don't:**

| Combinator | crem | fst-aggregate | DDD Meaning |
|-----------|------|---------------|-------------|
| Sequential | `Category (.)` | `compose` (proposed) | Saga / pipeline |
| Parallel | `Parallel` / `Strong` | `union` (similar) | Independent invariants |
| Alternative | `Alternative` / `Choice` | Missing | Command routing |
| Feedback | `Feedback` | Missing | Aggregate ↔ Policy loop |
| Kleisli | `Kleisli` | Missing | Multi-event pipeline |
| Arrow | `arr` | Missing | Pure function lifting |

**The Feedback combinator** is particularly valuable for DDD — it models
the aggregate→policy→aggregate loop that's central to event-driven
architectures:

```haskell
-- crem: aggregate events loop back through policy as commands
writeModel :: StateMachine CartCommand [CartEvent]
writeModel = Feedback cartAggregate paymentPolicy
```

Our `compose` (from FUTURE-DIRECTIONS) is the sequential version of this
but lacks the loop-back capability.

### 3. Decider Pattern

**crem: Separate pattern, decide takes output not state**

```haskell
data Decider topology input output = forall state. Decider
  { deciderInitialState :: InitialState state
  , decide :: forall v. input -> state v -> output
  , evolve :: forall v. state v -> output -> EvolutionResult topology state v output
  }

-- Rebuild from event history
rebuildDecider :: [output] -> Decider topology input output -> Decider topology input output
rebuildDecider outputs decider = foldl' rebuildDeciderStep decider outputs
```

Key: `evolve` takes `state -> output -> EvolutionResult` — the output
(event) determines the next state. This matches the event sourcing
pattern exactly. `rebuildDecider` folds events over `evolve` to
reconstruct the machine with its state restored.

`deciderMachine` converts a `Decider` to a `BaseMachine` by composing
`decide` and `evolve`:

```haskell
deciderMachine :: Decider topology input output -> BaseMachine topology input output
deciderMachine (Decider initial' decide' evolve') = BaseMachineT
  { initialState = initial'
  , action = \state input ->
      let output = decide' input state
      in case evolve' state output of
           EvolutionResult finalState -> ActionResult $ pure (output, finalState)
  }
```

**fst-aggregate: Decider derived from Transducer via projection**

```haskell
-- exec IS omega (the output function)
-- apply IS the transition function of π₂(T) (the output projection)
toDecider :: (Enum c, Bounded c, Eq e) => Transducer s c e -> Decider c e s
```

The Decider isn't defined independently — it's a mathematical consequence
of projecting the Transducer.

**Comparison:**

| Aspect | crem | fst-aggregate |
|--------|------|---------------|
| Decider is | Independently defined | Derived from Transducer |
| decide/exec | `input -> state v -> output` | `s -> c -> Maybe e` |
| evolve/apply | `state v -> output -> EvolutionResult` | `s -> e -> Maybe s` |
| Consistency | User must ensure decide/evolve agree | Guaranteed by derivation |
| Type-level constraints | Topology enforced in EvolutionResult | None (runtime Maybe) |
| Rebuild/reconstitute | `rebuildDecider :: [output] -> Decider -> Decider` | `reconstitute :: Decider -> [e] -> Maybe s` |
| State returned | Updated Decider (machine with new state) | `Maybe s` (just the state) |

crem's `rebuildDecider` returns a full `Decider` (machine with restored
state) — ready to process the next command. Our `reconstitute` returns
just the state value. crem's approach is more ergonomic for command
handling; ours is more transparent about what's happening.

### 4. Automata-Theoretic Operations

**fst-aggregate has, crem doesn't:**

| Operation | Purpose | Value |
|-----------|---------|-------|
| `inputProjection` | Extract command-language Acceptor | Command sequence validation |
| `outputProjection` | Extract event-language Acceptor | Event stream validation |
| `Acceptor` type | Binary accept/reject machine | Invariant checking |
| `Sequencer` type | Predetermined path | Happy path analysis |
| Formal projection proof | Event sourcing = π₂(T) | Mathematical guarantee |

crem has no concept of projecting a machine onto its input or output
language. There's no Acceptor type. You can't ask "is this sequence of
commands valid?" without running the machine and checking for errors.

### 5. State Representation

**crem: Vertex-indexed GADT, existentially quantified**

```haskell
data RegState (v :: RegVertex) where
  SPotentialCustomer    :: RegState 'PotentialCustomer
  SRequiresConfirmation :: Email -> RegState 'RequiresConfirmation
```

State carries data AND encodes the current lifecycle position at the type
level. The vertex index determines which transitions are valid. State is
existentially quantified inside `BaseMachineT` — consumers can't inspect
it.

**fst-aggregate: Plain enum, visible type parameter**

```haskell
data RegState = PotentialCustomer | RequiresConfirmation | Confirmed | Deleted
```

State is a simple sum type. Lifecycle position is encoded by value, not
type. The state type parameter `s` is visible in `Transducer s c e`.

**Trade-off:** crem's indexed state is more expressive (state can carry
different data per vertex) but heavier. Our plain enum is simpler but
can't carry vertex-specific data.

### 6. Effects

**crem: Monad-parameterized from the start**

```haskell
data BaseMachineT m topology input output = ...
  -- m is the effect monad

type BaseMachine topology a b = forall m. Monad m => BaseMachineT m topology a b
  -- Pure machines work in any monad

-- Change effect context
hoist :: (forall x. m x -> n x) -> StateMachineT m a b -> StateMachineT n a b
```

Effects are a first-class concern. Pure machines use the rank-2 `forall m`
trick. `hoist` allows changing the effect context (e.g., test → production).

**fst-aggregate: Pure only (effects proposed)**

Our current types are pure. The coalgebraic encoding (FUTURE-DIRECTIONS §6)
proposes `EffTransducer m c e` but it's not implemented.

### 7. Visualization

**crem: Built-in Mermaid rendering**

```haskell
-- Topology → Graph → Mermaid
renderStateDiagram :: Graph a -> Mermaid

-- Composed machines render as product/transitive-closure graphs
machineAsGraph :: StateMachineT m a b -> UntypedGraph

-- Flow diagrams for composition structure
renderFlow :: TreeMetadata MachineLabel -> StateMachineT m a b -> Either String (Mermaid, ...)
```

crem renders both the state topology and the composition structure.
Composed machines use graph products and transitive closure to compute
the effective topology.

**fst-aggregate: Proposed (FUTURE-DIRECTIONS §5)**

DOT and Mermaid generation proposed but not implemented.

### 8. Production Readiness

| Aspect | crem | fst-aggregate |
|--------|------|---------------|
| Effect support | Yes (`m` parameter) | No (proposed) |
| NoThunks | Yes (prevents space leaks) | No |
| machines integration | Yes (`AutomatonM` instance) | No |
| Streaming | Via `machines` ProcessT | No (proposed) |
| Visualization | Built-in Mermaid | No (proposed) |
| Compile-time safety | Type-level topology | Runtime `Maybe` |
| Snapshot support | `rebuildDecider` from any point | `reconstituteFrom` (proposed) |
| Dependencies | Heavy (singletons, profunctors, machines, nothunks) | Minimal (base only) |

---

## What Each Architecture Does Best

### crem excels at

1. **Compile-time transition safety** — invalid transitions are type errors,
   not runtime failures
2. **Rich composition** — Sequential, Parallel, Alternative, Feedback, Kleisli
   cover every DDD composition pattern
3. **Profunctor/Category ecosystem** — idiomatic Haskell composition with
   Arrow notation, Strong, Choice
4. **Production concerns** — effects, NoThunks, machines integration,
   visualization
5. **Vertex-indexed state** — state can carry different data per lifecycle
   position, enforced by types
6. **Feedback loops** — models aggregate↔policy interaction directly

### fst-aggregate excels at

1. **Mathematical foundation** — grounded in automata theory with formal
   operations (projection, union, concatenation)
2. **Derivation over assumption** — the Decider is derived from the
   Transducer via projection, not independently defined
3. **Acceptor/Sequencer concepts** — first-class types for command validation
   and happy-path analysis
4. **The projection insight** — event sourcing = output projection of a
   transducer is a provable mathematical fact, not a design pattern
5. **Simplicity** — plain Haskell, no singletons/GADTs/type families, minimal
   dependencies
6. **Exhaustive testing** — Enum/Bounded types enable complete verification
   of all transitions

---

## What Each Could Learn From the Other

### crem could adopt from fst-aggregate

| Concept | Value |
|---------|-------|
| `inputProjection` / `outputProjection` | Validate command/event sequences independently |
| `Acceptor` type | Binary validator derivable from any machine |
| Formal projection proof | Mathematical guarantee that `rebuildDecider` is correct |
| Exhaustive Hedgehog testing | Test every (state, command) pair from the topology |
| Transducer as source of truth | Derive `Decider` instead of defining it separately |

crem's `Decider` requires the user to define `decide` and `evolve`
consistently. There's no mechanism to verify they agree. Our projection
derivation guarantees it by construction.

### fst-aggregate could adopt from crem

| Concept | Value |
|---------|-------|
| Type-level topology | Compile-time transition enforcement |
| StateMachineT GADT | Rich composition (especially Feedback, Kleisli) |
| Profunctor/Category instances | Ecosystem integration, Arrow notation |
| Effect monad parameterization | Production-ready machines |
| `hoist` | Change effect context (test → prod) |
| NoThunks | Prevent space leaks in long-running systems |
| machines integration | Streaming via ProcessT |
| Mermaid rendering | Built-in visualization |
| Vertex-indexed state GADTs | Per-vertex typed state data |

---

## Synthesis: What a Combined Library Could Look Like

The two approaches are complementary. A synthesis would layer them:

```
Layer 3: Composition (from crem)
  StateMachineT with Sequential, Parallel, Alternative, Feedback, Kleisli
  Category, Profunctor, Strong, Choice, Arrow instances
  Effect monad parameterization

Layer 2: Automata Operations (from fst-aggregate)
  inputProjection, outputProjection
  Acceptor, Sequencer types
  toDecider derivation with formal guarantee
  union, concatenation on Acceptors

Layer 1: Core Machine (combined)
  BaseMachineT m (topology :: Topology vertex) input output
    with type-level topology enforcement (from crem)
  Transducer-style delta/omega separation (from fst-aggregate)
    enabling projection operations
  Vertex-indexed state GADTs (from crem)
```

### Key Design Decisions for a Synthesis

**1. Can we project a topology-constrained machine?**

Yes. Given a `BaseMachineT m topology input output` with
`(Enum vertex, Bounded vertex, Enum input, Bounded input)`, we can
enumerate all transitions and build the Acceptor. The type-level
topology is demoted to a runtime `Topology` value via singletons,
then used to construct the projection.

```haskell
inputProjection
  :: (SingI topology, Demote vertex ~ vertex, ...)
  => BaseMachineT m topology input output
  -> Acceptor vertex input   -- uses demoted topology
```

**2. Can we derive the Decider from a topology-constrained machine?**

Yes, but with a subtlety. crem's `Decider` has topology constraints in
`EvolutionResult`. Our derived apply function would need to produce
`EvolutionResult` values with `AllowedTransition` proofs. Since these
proofs are constructed by typeclass resolution, the derived `apply`
would need the same vertex-indexed GADT structure.

This is tractable but requires careful design. The `AllowedTransition`
proof for the derived apply comes from the same topology that constrains
the original machine — it's just being used in the opposite direction
(event→state instead of command→state).

**3. Can we add Feedback/Kleisli to fst-aggregate's operations?**

Feedback is orthogonal to the automata operations. It's a composition
pattern (loop), not an automata operation (project/union/concat). Both
can coexist in the same library.

The Feedback combinator could be defined on our Transducer type:

```haskell
feedback
  :: (Foldable n, Monoid (n c))
  => Transducer s1 c (n e)
  -> Transducer s2 e (n c)
  -> Transducer (s1, s2) c (n e)
```

**4. Should we use singletons?**

This is the biggest decision. Singletons add:
- Compile-time transition safety (high value)
- Heavy dependencies and compile times (high cost)
- Complex error messages (medium cost)

A pragmatic middle ground: provide both a lightweight runtime-checked
API (our current approach) and an optional type-level-checked API
(crem-style) via a separate module. Users choose based on their needs.

---

## Summary

| Dimension | crem | fst-aggregate |
|-----------|------|---------------|
| Core idea | Composable Mealy machines with type-level topology | Transducer with automata operations and derived Decider |
| Transition safety | Compile-time (GADTs) | Runtime (Maybe) |
| Composition | 6 combinators + full profunctor hierarchy | union + concatenation (more proposed) |
| Event sourcing | Decider pattern (assumed) | Decider derived via projection (proven) |
| Formal operations | None | Projection, union, concatenation |
| Effects | Built-in (monad parameter) | Not yet |
| Visualization | Built-in (Mermaid) | Not yet |
| Dependencies | Heavy (singletons, profunctors, machines) | Minimal (base) |
| Best for | Production systems needing compile-time guarantees | Formal modeling and correct-by-construction derivation |

Neither library is strictly better. crem is more production-ready.
fst-aggregate is more mathematically principled. A synthesis combining
crem's composition and type safety with fst-aggregate's projection and
derivation would be stronger than either alone.
