# Mealy Machines vs. Finite-State Transducers

> Historical API note (2026-07-12): references below to the Decider facade
> describe a pre-0.1 design that has been removed. Use `Keiki.Core.stepEither`
> for forward decisions and the structured Core replay functions for hydration.
> The formalism comparison still stands; prototype `Maybe`-output signatures do
> not. The release edge output is list-shaped.

These terms are often used interchangeably but they describe different
levels of generality. The distinction matters for library design: crem
models Mealy machines, keiki models finite-state transducers (extended
with symbolic guards and a typed register file).

---

## Definitions

### Mealy Machine

A Mealy machine is a **specific, constrained** type of finite-state
transducer:

```
M = ⟨S, Σ, Γ, δ, ω, s₀⟩

δ: S × Σ → S       -- transition function (total)
ω: S × Σ → Γ       -- output function (total)
s₀ ∈ S              -- initial state
```

Properties:
- **Deterministic** — exactly one transition per (state, input) pair
- **Total** — defined for every (state, input) pair; never rejects
- **Real-time** — consumes exactly one input and produces exactly one
  output per step
- **No ε-transitions** — cannot advance without consuming input
- **No final states** — runs until input is exhausted; no accept/reject

This is what crem's `BaseMachineT` implements (extended with an effect
monad `m`).

### Moore Machine

For completeness: a Moore machine has output that depends only on the
current state, not the input:

```
M = ⟨S, Σ, Γ, δ, ω, s₀⟩

δ: S × Σ → S       -- transition function
ω: S → Γ           -- output depends on state only
```

Moore and Mealy machines are equivalent in expressive power (any Moore
machine can be converted to a Mealy machine and vice versa), but Mealy
machines may require fewer states. Moore machines are not used in our
design because DDD aggregates naturally have output that depends on both
state and command (e.g., the same `FulfillGDPRRequest` command produces
`AccountDeleted` from `Confirmed` but ε from `RequiresConfirmation`).

### Finite-State Transducer (FST)

The general concept — a finite-state machine with an input tape and an
output tape:

```
T = ⟨S, Σ, Γ, δ, S₀, F⟩

δ ⊆ S × (Σ ∪ {ε}) × (Γ ∪ {ε}) × S    -- transition relation
S₀ ⊆ S                                 -- initial states (possibly multiple)
F ⊆ S                                  -- final (accepting) states
```

Properties:
- **Possibly non-deterministic** — a (state, input) pair can have zero,
  one, or many transitions
- **Partial** — some (state, input) pairs have no valid transition
- **ε-transitions** — can consume no input and/or produce no output
- **Final states** — some states are accepting; the machine can
  accept or reject an input sequence
- **Multi-symbol output** — generalized FSTs (GSMs) can output strings
  per transition

### Generalized Sequential Machine (GSM)

A further generalization where transitions can consume and produce
*strings* of symbols rather than single symbols:

```
δ ⊆ S × Σ* × Γ* × S
```

keiki does not model GSMs directly: a single edge produces at most one
event. Multi-event commands are handled by *state refinement* — the
author introduces internal vertices and chains letter edges through
them, optionally driven end-to-end by `Keiki.Decider.toMultiDecider`
with a `DriverConfig`. See `multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`
for the rejection of the GSM-expansion approach in favor of state
refinement.

---

## The Hierarchy

```
Finite-State Transducer
│   partial, non-deterministic, ε-transitions, final states
│   δ ⊆ S × (Σ ∪ {ε}) × (Γ ∪ {ε}) × S
│
├── Generalized Sequential Machine (GSM)
│   │   multi-symbol output per transition
│   │   ω: S × Σ → Γ*
│   │
│   └── Letter Transducer (real-time FST)
│           exactly 1 input and ≤ 1 output per transition
│
├── Deterministic FST
│   │   at most one transition per (state, input)
│   │
│   └── Total Deterministic FST
│       │   exactly one transition per (state, input)
│       │
│       └── Mealy Machine
│               total, deterministic, real-time, no final states
│
└── Acceptor / Recognizer
        no output tape; binary accept/reject
```

Every Mealy machine is an FST, but not every FST is a Mealy machine.
The FST is the general framework; the Mealy machine is the most
constrained useful specialization.

---

## Where Our Types Sit

### keiki's `SymTransducer`

```haskell
data SymTransducer phi rs s ci co = SymTransducer
  { edgesOut    :: s -> [Edge phi rs ci co s]  -- outgoing edges per vertex
  , initial     :: s                           -- single initial state
  , initialRegs :: RegFile rs                  -- typed initial register file
  , isFinal     :: s -> Bool                   -- final states exist
  }

data Edge phi rs ci co s = Edge
  { guard  :: phi                              -- symbolic predicate
  , update :: Update rs w ci                   -- register-file update
  , output :: Maybe (OutTerm rs ci co)         -- ε-output (Nothing) or event
  , target :: s
  }

delta :: SymTransducer phi rs s ci co -> s -> RegFile rs -> ci -> Maybe (s, RegFile rs)
omega :: SymTransducer phi rs s ci co -> s -> RegFile rs -> ci -> Maybe co
```

This is a **partial, deterministic, letter FST with ε-output and final
states**, extended with symbolic edge guards (over a `BoolAlg phi`) and
a typed register file. Not a Mealy machine because:

- Partial (`delta` returns `Nothing` when no edge guard is satisfied)
- Has ε-output (an edge with `output = Nothing`)
- Has final states (`isFinal`)

The symbolic-guard / register-file extensions are not part of the basic
FST formalism but compose cleanly on top of it — the underlying control
graph is still a letter FST, and `Keiki.Acceptor.inputAcceptor` /
`outputAcceptor` recover the unadorned input/output acceptors.

### crem's `BaseMachineT`

```haskell
data BaseMachineT m (topology :: Topology vertex) input output = forall state.
  BaseMachineT
  { initialState :: InitialState state
  , action :: forall v. state v -> input -> ActionResult m topology state v output
  }
```

This is a **Mealy machine** extended with:
- Effect monad `m`
- Type-level topology constraining valid transitions
- Existentially quantified state

It is total over the transitions permitted by the topology — the type
system prevents calling `action` with an input that the topology doesn't
allow, so there's no `Maybe` in the return type.

The partiality is pushed from the transition function into the type
system: a Mealy machine that's total over a restricted domain (defined
by the topology) is equivalent to a partial FST that returns `Nothing`
for transitions outside that domain.

### crem's `StateMachineT`

```haskell
data StateMachineT m input output where
  Basic       :: BaseMachineT m topology input output -> StateMachineT m input output
  Sequential  :: StateMachineT m a b -> StateMachineT m b c -> StateMachineT m a c
  ...
```

A **composition tree of Mealy machines** — still Mealy at the leaves, but
the composition combinators (Sequential, Parallel, Feedback, etc.) create
machines with richer behavior.

---

## How Partiality is Handled

The core difference in how the two libraries express "this command is
invalid in this state":

### keiki: runtime `Maybe`, with optional symbolic checks at build time

```haskell
edgesOut PotentialCustomer =
  [ Edge { guard = matchInCtor inpStartRegistration, …, target = RequiresConfirmation } ]
edgesOut Confirmed = []  -- no outgoing edge accepts StartRegistration

-- delta t Confirmed regs StartRegistration  ⇒  Nothing
```

The transition is partial: `delta` returns `Just` only when exactly one
outgoing edge has a satisfied guard. The caller handles the `Maybe`.
`Keiki.Symbolic.isBot` can additionally prove at build time that an
edge can never fire (its guard is unsatisfiable), giving a measure of
the compile-time safety crem buys with type-level topology.

### crem: Type-level topology

```haskell
-- Topology says: Confirmed can only go to Deleted
type RegTopology = 'Topology '[ ..., '( 'Confirmed, '[ 'Deleted ]) ]

-- Action is total over the topology's allowed transitions
action (SConfirmed email) (FulfillGDPRRequest) =
  ActionResult $ pure (AccountDeleted, SDeleted)
  -- compiles: AllowedTransition RegTopology 'Confirmed 'Deleted ✓

action (SConfirmed email) (StartRegistration) =
  -- doesn't need to exist: the topology says this can't happen
  -- if written anyway: TYPE ERROR (no AllowedTransition proof)
```

The transition function is total over the restricted domain. Invalid
transitions aren't expressible — they're excluded by the type system.
The caller handles invalid *commands* at the routing layer (via
`Choice` / `Alternative`), not in the transition function itself.

### Equivalence

These are equivalent encodings:

```
Partial function  f: A → Maybe B
       ≅
Total function    f: A' → B       where A' ⊂ A

The subset A' is defined by:
  - keiki: the set of (s, regs, c) where delta t s regs c ≠ Nothing
  - crem: the set of (s, c) where AllowedTransition topology s c holds
```

The information content is identical. The difference is where the
invariant lives (runtime vs. compile time) and what the consequences
of violation are (`Nothing` vs. type error). keiki's symbolic layer
narrows the gap further: `isBot` flags unsatisfiable guards at build
time, and constructor-mutex on `PInCtor` is recognised by SBV.

---

## Why DDD Aggregates Need More Than Mealy

A pure Mealy machine (total, no final states, no ε) is insufficient
for DDD aggregates because:

### 1. Invariants require partiality

Aggregates reject invalid commands. A Mealy machine must produce output
for every input. An FST can return "no transition" — which IS the
invariant.

```
-- "You cannot confirm an account that hasn't registered"
-- Mealy: must return something. What?
-- FST: delta(PotentialCustomer, ConfirmAccount) = Nothing. Done.
```

crem solves this at the type level — the Mealy machine is total, but the
topology prevents the invalid input from reaching the action function.

### 2. Lifecycle termination requires final states

Aggregates have terminal states (Deleted, Closed, Archived). A Mealy
machine has no concept of "done." An FST's final states model this.

crem doesn't have final states in `BaseMachineT` — but if the topology
has a vertex with no outgoing edges, the machine effectively terminates
(no further transitions are possible). This is an implicit encoding of
finality.

### 3. Silent transitions require ε-output

Some state changes produce no event (e.g., GDPR deletion of an
unconfirmed account). A Mealy machine always produces output. An FST
allows ε-output.

crem handles this by having the output type include an "empty" case
(e.g., `Maybe Event` or `[Event]` with `[]`). This is a value-level
encoding of ε — the Mealy machine produces `Nothing` or `[]`, not
silence at the automaton level.

### 4. Multi-event commands require generalized output

A single command may produce multiple events. A Mealy machine produces
exactly one output per input. A GSM produces a sequence.

crem handles this with collection types (`[Event]`) as the output, plus
`Kleisli` composition for chaining multi-output machines. keiki uses
*state refinement*: the author introduces internal vertices and chains
single-event letter edges through them; `Keiki.Decider.toMultiDecider`
drives the chain end-to-end so the user sees a `decide :: c -> s -> [e]`
that can return more than one event per command.

---

## Summary

| Property | Mealy Machine | FST | DDD Need |
|----------|--------------|-----|----------|
| Transitions | Total | Partial | Invariants (reject invalid commands) |
| Output | Always exactly 1 | 0, 1, or many | ε-transitions + multi-event |
| Final states | None | Yes | Lifecycle termination |
| Determinism | Deterministic | Possibly non-deterministic | Deterministic in practice |
| Partiality via | Type-level restriction (crem) | `Maybe` from `delta` + symbolic `isBot` (keiki) | Either works |
| ε-output via | `Maybe`/`[]` in output type (crem) | `Nothing` from edge `output` (keiki) | Either works |
| Multi-event via | `[]` output + Kleisli (crem) | State refinement + `toMultiDecider` (keiki) | Either works |

Both libraries end up at the same expressiveness — they just encode the
constraints differently. crem pushes restrictions into the type system.
keiki keeps them in the transition function's partiality, then uses an
SBV-backed symbolic layer to recover build-time guarantees where the
type system would otherwise have nothing to say. The trade-off is
compile-time safety (crem) vs. structural alphabets, register-file
discipline, and decidable guard analysis (keiki).

---

## Which Is Better for Functional Event Sourcing?

**The FST.** The output projection operation π₂(T) — which derives the
`apply` function from the transducer — requires partiality and final
states, both of which the FST has natively and the Mealy machine must
encode indirectly.

### Event sourcing = output projection

The core insight from Part III of the article series is that the
event-sourced Decider (exec/apply) is the **output projection** of a
Finite-State Transducer. This derivation relies on three FST properties
that Mealy machines lack:

**1. Partiality gives us `apply` rejection.**

The derived `apply :: s -> e -> Maybe s` must return `Nothing` when an
event is invalid in a given state. This is the event-language Acceptor
rejecting an invalid history. A Mealy machine's totality means every
(state, event) pair must produce a next state — there's no way to say
"this event can't happen here" without wrapping the output in `Maybe`,
at which point you've re-introduced partiality outside the formalism.

**2. Final states give us lifecycle termination.**

`reconstitute` must know when the aggregate has reached a terminal
state. The FST has `F ⊆ S` — final states are part of the formal
model. The Mealy machine has no equivalent; you'd need to track
termination as a side-channel concern.

**3. ε-output gives us silent transitions.**

Some transitions change state without producing an event (e.g., GDPR
deletion of an unconfirmed account). The FST models this as
`ω(s, c) = Nothing` — a first-class concept in the formalism. In a
Mealy machine, you'd use `Maybe Event` as the output type, but then
"no event produced" and "invalid transition" are both represented as
`Nothing` at different levels — conflating two semantically distinct
concepts.

### The derivation gap

With an FST, the path from model to event sourcing is mechanical:

```
1. Define Transducer T = ⟨S, C, E, δ, ω, S₀, F⟩     (one definition)
2. Call toDecider T                                     (one function call)
3. Get Decider { exec = ω, apply = π₂(T).transition }  (derived, correct by construction)
```

With a Mealy machine, there is no derivation — you define `decide` and
`evolve` independently and must ensure they agree:

```
1. Define decide :: input -> state v -> output          (one definition)
2. Define evolve :: state v -> output -> state v'       (another definition)
3. Hope they are consistent                             (no mechanical guarantee)
```

crem's `deciderMachine` composes `decide` and `evolve` into a
`BaseMachine`, but it doesn't verify that `evolve` correctly inverts
`decide`. If `decide` says command C in state S produces event E, but
`evolve` maps (S, E) to the wrong next state, `rebuildDecider` will
reconstruct incorrect state. This bug is silent — no type error, no
runtime error, just wrong state.

The FST derivation eliminates this class of bug entirely. The `apply`
function is **computed from** δ and ω, not defined alongside them.
There's nothing to keep in sync because there's only one source of
truth.

### What crem must encode outside the formalism

| FST concept | crem encoding | Cost |
|-------------|---------------|------|
| Partiality (invariants) | Type-level topology | Singletons dependency, complex errors |
| Final states | Dead-end vertices (implicit) | No explicit `isFinal` predicate |
| ε-output | `Maybe Event` / `[Event]` output type | Conflates "no event" with "Maybe" at value level |
| Multi-event | `[Event]` output + Kleisli combinator | Works well, but not part of the machine formalism |
| Output projection | Not available | Cannot derive `apply` from the machine |
| Event-language Acceptor | Not available | Cannot validate event sequences independently |

All of these work in practice — crem is a production-quality library.
But they are workarounds for the Mealy formalism's limitations, not
native capabilities.

### The bottom line

The Mealy machine is a **runtime execution model** — it's excellent for
"given this input, what's the output and next state?" crem's composition
combinators (Sequential, Parallel, Feedback, Kleisli) make it powerful
for building complex systems from simple machines.

The FST is a **formal specification model** — it's excellent for "what
are ALL valid command sequences? What are ALL valid event sequences?
Can I mechanically derive the event-sourced decomposition?" The automata
operations (projection, union, concatenation) enable formal reasoning
about the aggregate's behavior.

For functional event sourcing specifically, the FST is the more natural
fit because event sourcing IS an output projection — and the FST is the
formalism where projection is a native operation.
