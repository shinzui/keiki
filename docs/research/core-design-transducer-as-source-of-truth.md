# FST Aggregate: Design Notes

> **Status: historical.** This is the early kernel sketch from when
> the project was called *fst-aggregate* and the central type was
> `Transducer s c e`. It has been superseded by the symbolic-register
> direction; the load-bearing reference is now
> `synthesis-c-foundation-b-presentation-with-worked-examples.md`,
> and the architectural overview lives in
> `architecture-comparison-keiki-vs-crem.md`. The shipped types
> (`SymTransducer phi rs s ci co`, `Acceptor a s`, `Decider c e s`,
> `inputAcceptor`, `outputAcceptor`, `applyEvent`) do not match the
> sketches below. Read for the original framing, not as an API
> reference.

## Architectural Difference from tan-event-source

```
tan-event-source                    fst-aggregate
─────────────────                   ──────────────
                                    Transducer s c e        ← single source of truth
                                        │
                                   ┌────┼────────────┐
                                   │    │            │
                                   ▼    ▼            ▼
Decider c e s (assumed)      π₁: Acceptor s c   π₂: Acceptor s e   Decider c e s
  decide :: c → s → [e]           (command         (event            exec  :: s → c → Maybe e
  evolve :: s → e → s              validator)       validator)       apply :: s → e → Maybe s
                                                        │
                                                        │
                                                   reconstitute
                                                   = foldlM apply s₀
```

## Key Design Decisions

### 1. Partiality over Totality

tan-event-source uses total functions:
- `decide :: c -> s -> [e]` — always succeeds, `[]` means "rejected"
- `evolve :: s -> e -> s` — always succeeds, even for invalid events

This conflates "no events produced" with "command rejected" and can't
express "this event is invalid in this state."

fst-aggregate uses `Maybe`:
- `delta :: s -> c -> Maybe s` — `Nothing` = invariant violation
- `omega :: s -> c -> Maybe e` — `Nothing` = ε-transition (valid but silent)
- `apply :: s -> e -> Maybe s` — `Nothing` = invalid event for this state

### 2. Single Event per Transition

The FST formalism maps each (state, command) pair to exactly one event
(or ε). tan-event-source's `decide` returns `[e]`, allowing multiple
events per command. This is practical but breaks:
- The 1:1 correspondence with FST transitions
- The ability to derive `apply` from the Transducer automatically
- Formal reasoning about event languages

If multi-event commands are needed, model them as a sequence of
sub-transitions within the Transducer, or use a separate combinator.

### 3. Transducer as Source of Truth

The Transducer defines δ and ω together, ensuring consistency.
The Decider's exec and apply are *derived*, not independently defined.
This prevents bugs where exec and apply disagree about valid transitions.

### 4. Output Projection Requires Enumerable Commands

`outputProjection` needs `(Enum c, Bounded c)` to search for the
command that produces a given event. This is the mathematical price
of going from ω(s,c)→e to apply(s,e)→s — you need to "invert" ω.

For the Haskell implementation, this means command types should derive
`Enum` and `Bounded` (which sum types do naturally).

## Type Hierarchy

```haskell
-- The FSA family, from most to least general:

Transducer s c e    -- Full model: commands → states → events
    │
    ├── inputProjection  → Acceptor s c    -- Validates command sequences
    ├── outputProjection → Acceptor s e    -- Validates event sequences  
    └── toDecider        → Decider c e s   -- Event-sourced decomposition

Acceptor s a        -- Binary accept/reject
    │
    └── type Sequencer s = Acceptor s ()   -- Single predetermined path
```

## Operations

| Operation | Type | DDD Meaning |
|-----------|------|-------------|
| `inputProjection` | `Transducer s c e → Acceptor s c` | Command validation |
| `outputProjection` | `Transducer s c e → Acceptor s e` | Event stream validation |
| `toDecider` | `Transducer s c e → Decider c e s` | Event sourcing decomposition |
| `union` | `Acceptor s1 a → Acceptor s2 a → Acceptor (s1,s2) a` | Parallel composition |
| `concatenate` | `Acceptor s1 a → Acceptor s2 a → Acceptor (Either s1 s2) a` | Sequential phases |
| `reconstitute` | `Decider c e s → [e] → Maybe s` | Replay event history |

## Future Directions

- **Profunctor instances**: Transducer is contravariant in `c`, covariant in `e`
- **Composition**: Transducer composition (output of one feeds input of another)
- **Weighted transducers**: For probabilistic or cost-based transitions
- **QuickCheck generators**: Generate valid command/event sequences from Acceptors
- **Visualization**: Generate state diagrams from Transducers
- **Coalgebraic encoding**: Use the `automaton` package's StreamT approach for
  potentially infinite state machines with effects
