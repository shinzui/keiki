# Multi-Event Commands: Three Approaches

## The Problem

The letter-by-letter FST formalism maps each (state, command) pair to exactly
one event (or epsilon):

```
ω: S × C → E ∪ {ε}
```

But in practice, a single command often produces multiple events:

```
StartRegistration → [RegistrationStarted, ConfirmationEmailSent]
```

This creates a tension: the `[e]` output of tan-event-source's `decide` is
practical, but it breaks the 1:1 FST correspondence and makes it impossible
to derive `apply` mechanically from the Transducer.

The root cause is that event-by-event reconstitution — `foldl apply s₀ events`
— requires a defined state *between* each pair of events. If a single command
emits two events, what is the state after the first event but before the second?

```
PotentialCustomer
    → apply(_, RegistrationStarted) = ???
    → apply(???, ConfirmationEmailSent) = RequiresConfirmation
```

The `???` is an intermediate state that must exist somewhere. The three
approaches differ in **where that intermediate state lives**.

---

## Approach 1: State Refinement

**Core idea:** Add explicit intermediate states to the domain state type. Each
transition produces exactly one event. The FST letter-by-letter correspondence
is preserved perfectly.

### Model

```
States:   {PotentialCustomer, Registering, RequiresConfirmation, Confirmed, Deleted}
                                    ↑
                            intermediate state

Commands: {Cmd StartRegistration, Cmd ConfirmAccount, ..., Continue}
                                                              ↑
                                                     internal command
```

The multi-event command becomes two transitions:

```
PotentialCustomer  —[Cmd StartRegistration]/RegistrationStarted→  Registering
Registering        —[Continue]/ConfirmationEmailSent→             RequiresConfirmation
```

### Haskell Types

```haskell
data State
  = PotentialCustomer
  | Registering            -- intermediate
  | RequiresConfirmation
  | Confirmed
  | Deleted

data Cmd
  = Cmd Command            -- external commands
  | Continue               -- internal advancement

transducer :: Transducer State Cmd Event
```

### Reconstitution

Standard letter-FST reconstitution works directly:

```
reconstitute [RegistrationStarted, ConfirmationEmailSent, AccountConfirmed]

  apply(PotentialCustomer,    RegistrationStarted)   = Registering
  apply(Registering,          ConfirmationEmailSent) = RequiresConfirmation
  apply(RequiresConfirmation, AccountConfirmed)      = Confirmed ✓
```

### Projection

Both projections work out of the box:

```
π₁(T) accepts: [Cmd StartRegistration, Continue, Cmd ConfirmAccount]
π₂(T) accepts: [RegistrationStarted, ConfirmationEmailSent, AccountConfirmed]
```

The `toDecider` derivation works mechanically — no user-provided `apply`.

### State Diagram

```
                          Cmd StartRegistration           Continue
                          / RegistrationStarted           / ConfirmationEmailSent
  ┌───────────────────┐ ─────────────────────→ ┌──────────────┐ ──────────────────→ ┌────────────────────────┐
  │ PotentialCustomer │                        │  Registering  │                    │ RequiresConfirmation   │
  └───────────────────┘                        └──────────────┘                    └────────────────────────┘
                                                                                     │            │     ↺
                                                                              Cmd ConfirmAccount  │  Cmd ResendConfirmation
                                                                              / AccountConfirmed  │  / ConfirmationResent
                                                                                     ↓            │
                                                                                ┌───────────┐     │
                                                                                │ Confirmed  │     │
                                                                                └───────────┘     │
                                                                                     │            │
                                                                    Cmd FulfillGDPR  │            │ Cmd FulfillGDPR / ε
                                                                    / AccountDeleted │            │
                                                                                     ↓            ↓
                                                                                ┌───────────┐
                                                                                │  Deleted   │
                                                                                └───────────┘
```

### Trade-offs

| Aspect | Assessment |
|--------|------------|
| Mathematical soundness | Perfect — letter-by-letter FST |
| Derivation of `apply` | Automatic via `toDecider` |
| Projection | Both π₁ and π₂ work |
| Domain model clarity | Mixed — `Registering` and `Continue` are implementation artifacts |
| State space size | Grows with multi-event commands (N events → N-1 extra states) |
| Command validation | Must account for `Continue` in external API boundary |
| Testability | Excellent — exhaustive via `(Enum, Bounded)` |

### When to use

- The intermediate states have genuine domain meaning ("Registering" could
  be meaningful — the system has recorded intent but hasn't yet dispatched
  the confirmation email)
- You want fully automatic `apply` derivation with no user-provided functions
- The number of multi-event commands is small

---

## Approach 2: GSM with Automatic Expansion

**Core idea:** Define the aggregate naturally with `ω: S × C → [E]`
(a Generalized Sequential Machine). The library mechanically expands it into
a letter FST by wrapping the state type with `Expanded s e`, which carries
intermediate state automatically.

### Model

The user defines a GSM with the "logical" states only:

```
States:   {PotentialCustomer, RequiresConfirmation, Confirmed, Deleted}
Commands: {StartRegistration, ConfirmAccount, ResendConfirmation, FulfillGDPRRequest}

ω(PotentialCustomer, StartRegistration) = [RegistrationStarted, ConfirmationEmailSent]
ω(RequiresConfirmation, ConfirmAccount) = [AccountConfirmed]
...
```

The library's `expand` function transforms this into:

```
States:   Expanded {PotentialCustomer, ...} Event
        = Settled PotentialCustomer
        | Settled RequiresConfirmation
        | Mid RequiresConfirmation [ConfirmationEmailSent]    ← auto-generated
        | Settled Confirmed
        | Settled Deleted

Commands: ExpandedInput Command
        = Real StartRegistration | Real ConfirmAccount | ... | Tick
```

### Haskell Types

```haskell
data GSM s c e = GSM
  { delta   :: s -> c -> Maybe s
  , omega   :: s -> c -> [e]      -- multi-event output
  , initial :: s
  , isFinal :: s -> Bool
  }

data Expanded s e
  = Settled s        -- stable domain state
  | Mid s [e]        -- target state + remaining events to emit

data ExpandedInput c
  = Real c           -- external command
  | Tick             -- internal advancement

expand :: GSM s c e -> Transducer (Expanded s e) (ExpandedInput c) e
```

### Expansion Mechanics

A GSM transition `s —[c]/[e₁, e₂, e₃]→ s'` becomes:

```
Settled s              —[Real c]/e₁→  Mid s' [e₂, e₃]
Mid s' [e₂, e₃]       —[Tick]/e₂→    Mid s' [e₃]
Mid s' [e₃]           —[Tick]/e₃→    Settled s'
```

Single-event transitions pass through unchanged:

```
Settled s              —[Real c]/e→   Settled s'
```

Epsilon transitions (no events):

```
Settled s              —[Real c]/ε→   Settled s'
```

### Reconstitution

After expansion, standard `toDecider` works:

```
reconstitute [RegistrationStarted, ConfirmationEmailSent, AccountConfirmed]

  apply(Settled PotentialCustomer,   RegistrationStarted)   = Mid RequiresConfirmation [ConfirmationEmailSent]
  apply(Mid RequiresConfirmation .., ConfirmationEmailSent) = Settled RequiresConfirmation
  apply(Settled RequiresConfirmation, AccountConfirmed)     = Settled Confirmed ✓
```

### State Diagram

```
                         Real StartRegistration                        Tick
                         / RegistrationStarted                         / ConfirmationEmailSent
  ┌─────────────────────────┐ ──────────→ ┌──────────────────────────────┐ ──────────→ ┌──────────────────────────────────┐
  │ Settled                 │             │ Mid                          │             │ Settled                          │
  │   PotentialCustomer     │             │   RequiresConfirmation       │             │   RequiresConfirmation           │
  └─────────────────────────┘             │   [ConfirmationEmailSent]   │             └──────────────────────────────────┘
                                          └──────────────────────────────┘                 │              │      ↺
                                              auto-generated by expand                     │              │  Real ResendConfirmation
                                                                                           │              │  / ConfirmationResent
                                                                                           ↓              ↓
                                                                                   Settled Confirmed   Settled Deleted
```

### Trade-offs

| Aspect | Assessment |
|--------|------------|
| Mathematical soundness | Perfect after expansion — letter-by-letter FST |
| Derivation of `apply` | Automatic via `toDecider` on the expanded FST |
| Projection | Both π₁ and π₂ work on the expanded FST |
| Domain model clarity | Excellent — user defines only logical states |
| State space size | Expanded wrapper adds structural complexity, not conceptual |
| User ergonomics | `Expanded s e` wrapper complicates pattern matching downstream |
| Command type | `ExpandedInput c` wrapper; external boundary must map `Real` |
| Testability | Good, but tests work with wrapped types |

### When to use

- You want the library to handle intermediate states automatically
- Domain states are clean and you don't want to pollute them
- You don't mind working with `Expanded`/`ExpandedInput` wrappers
- You need projections and `toDecider` to work mechanically

---

## Approach 3: Direct MultiDecider

**Core idea:** Define the aggregate as a GSM (natural multi-event output).
Provide the `apply` function by hand, with intermediate states encoded in
the state type. No expansion step. `exec` is derived from the GSM; `apply`
is user-provided.

### Model

The user defines both the GSM and the apply function:

```haskell
-- GSM: the natural, multi-event model
-- delta and omega use only "logical" states
gsm :: GSM State Command Event

-- apply: user-provided, with intermediate states
apply :: State -> Event -> Maybe State
```

The state type includes intermediates that only `apply` uses:

```
States: {PotentialCustomer, Registering, RequiresConfirmation, Confirmed, Deleted}
                                  ↑
                          only visible to apply
```

### Haskell Types

```haskell
data MultiDecider c e s = MultiDecider
  { exec    :: s -> c -> Maybe [e]   -- from GSM's omega (list output)
  , apply   :: s -> e -> Maybe s     -- user-provided (handles intermediates)
  , initial :: s
  , isFinal :: s -> Bool
  }

toMultiDecider
  :: GSM s c e
  -> (s -> e -> Maybe s)             -- user provides apply
  -> MultiDecider c e s
```

### The Event-Determinism Contract

The `apply` function must satisfy this invariant for every valid (s, c):

```
foldlM apply s (omega gsm s c) == Just (delta gsm s c)
```

In words: folding `apply` over the events produced by a command must arrive
at the same state that `delta` specifies. This is what makes reconstitution
correct.

For the User Registration example:

```
foldlM apply PotentialCustomer [RegistrationStarted, ConfirmationEmailSent]
  = apply PotentialCustomer RegistrationStarted        -- Just Registering
  >>= \s -> apply s ConfirmationEmailSent              -- Just RequiresConfirmation
  = Just RequiresConfirmation
  = delta PotentialCustomer StartRegistration           ✓
```

**This contract is not checked by the compiler.** It must be verified via
property-based tests:

```haskell
prop_eventDeterminism :: State -> Command -> Property
prop_eventDeterminism s c =
  case delta gsm s c of
    Nothing -> discard  -- invalid command, skip
    Just s' ->
      let events = omega gsm s c
      in  foldlM (apply decider) s events === Just s'
```

With `(Enum State, Bounded State, Enum Command, Bounded Command)`, this
can be checked exhaustively over all (state, command) pairs.

### Reconstitution

Works identically to the letter-FST case — events are folded one at a time:

```
reconstitute [RegistrationStarted, ConfirmationEmailSent, AccountConfirmed]

  apply(PotentialCustomer,    RegistrationStarted)   = Registering
  apply(Registering,          ConfirmationEmailSent) = RequiresConfirmation
  apply(RequiresConfirmation, AccountConfirmed)      = Confirmed ✓
```

### State Diagram

Same as Approach 1 but without the `Continue` command. The intermediate state
`Registering` only appears during event application, never during command handling:

```
  Command handler sees:                     Event applier sees:

  ┌───────────────────┐                     ┌───────────────────┐
  │ PotentialCustomer │                     │ PotentialCustomer │
  └───────────────────┘                     └───────────────────┘
          │                                         │
    StartRegistration                         RegistrationStarted
    / [RegistrationStarted,                         │
       ConfirmationEmailSent]                       ↓
          │                                 ┌───────────────┐
          │                                 │  Registering   │ ← only apply sees this
          │                                 └───────────────┘
          │                                         │
          │                                  ConfirmationEmailSent
          ↓                                         ↓
  ┌────────────────────────┐                ┌────────────────────────┐
  │ RequiresConfirmation   │                │ RequiresConfirmation   │
  └────────────────────────┘                └────────────────────────┘
```

### Trade-offs

| Aspect | Assessment |
|--------|------------|
| Mathematical soundness | Sound, but relies on user-verified contract |
| Derivation of `apply` | Manual — user must write and verify it |
| Projection | π₁ works on the GSM; π₂ requires the user-provided apply |
| Domain model clarity | Good — intermediate states are explicit and nameable |
| User ergonomics | Most natural — no wrappers, no internal commands |
| Command type | Clean — no `ExpandedInput` wrapper |
| Testability | Excellent — contract verifiable via exhaustive property tests |
| Closest to | tan-event-source's Decider, but with exec derived from GSM |

### When to use

- The intermediate states are meaningful enough to name (even if ephemeral)
- You want clean, unwrapped types for commands and states
- You're comfortable verifying the event-determinism contract via tests
- You want the most ergonomic API for consumers of the aggregate

---

## Comparison Summary

```
                    Approach 1              Approach 2              Approach 3
                    State Refinement        GSM + Expansion         Direct MultiDecider
                    ──────────────          ───────────────         ───────────────────

Source of truth     Letter FST              GSM                     GSM

Intermediate        In domain state type    In Expanded wrapper     In domain state type
states live...      + explicit Continue     (auto-generated)        (apply only)

apply derived       Automatically           Automatically           User-provided
                    (toDecider)             (toDecider on           (must satisfy
                                            expanded FST)           contract)

Command type        Extended with           Wrapped in              Clean / unchanged
                    Continue                ExpandedInput

State type          Extended with           Wrapped in              Extended with
                    intermediates           Expanded                intermediates

Projections         Both work               Both work               π₁ works; π₂
                                            (on expanded)           needs user apply

Formal              ★★★                     ★★★                     ★★☆
guarantee           (compile-time)          (compile-time)          (test-time)

Ergonomics          ★★☆                     ★☆☆                     ★★★
                    (Continue cmd           (Expanded/               (clean types,
                     is awkward)             ExpandedInput            natural API)
                                             wrappers)
```

### Decision Matrix

| If you prioritize... | Choose |
|---|---|
| No user-provided functions, fully automatic derivation | Approach 1 or 2 |
| Clean domain types, no wrappers | Approach 3 |
| Library-managed intermediate states | Approach 2 |
| Meaningful intermediate state names | Approach 1 or 3 |
| Easiest integration with existing code / tan-event-source | Approach 3 |
| Strongest compile-time guarantees | Approach 1 |

### Recommendation

**Default to Approach 3** for most aggregates. It's the most ergonomic, the
intermediate states are easy to name and understand, and the event-determinism
contract is trivially testable with `(Enum, Bounded)` types. It's also the
closest to how the Haskell ecosystem already models event sourcing (Chassaing's
Decider), but with the mathematical grounding of deriving `exec` from a
formal GSM.

**Use Approach 1** when the intermediate states have genuine domain significance
and you want the compiler to enforce consistency with no manual verification.

**Use Approach 2** when you need library-managed expansion and are willing to
work with wrapped types — useful for generic tooling (visualization, testing
infrastructure) that operates on the expanded FST uniformly.

All three approaches produce identical event streams and support correct
reconstitution. The difference is where the complexity lives: in the state
type (1 and 3), in wrapper types (2), or in a user-provided function (3).
