# 04 — Projections and Deriving Event Sourcing

This is the chapter where the library's central insight clicks. Read
slowly.

## Two views of one machine

The FST from `03` has two alphabets: an input alphabet (commands) and
an output alphabet (events). At any moment we can ask two questions:

1. **What command sequences are valid?** Throw away the events; look
   only at the control flow over commands.
2. **What event sequences are valid?** Throw away the commands; look
   only at the control flow over events.

Each answer is itself an acceptor — a state machine over a single
alphabet. They're called the **input projection** and the **output
projection** of the FST.

```
         Transducer T : commands → events
         ┌──────────────────────────────────┐
         │                                  │
         ▼                                  ▼
   π₁(T) Input Acceptor              π₂(T) Output Acceptor
   over commands only                over events only
   (drops events)                    (drops commands)

   "what command sequences          "what event sequences
    can the FST process?"            can the FST produce?"
```

Both projections share the same state set and the same start/final
states as the FST. They differ in what their transition function reads.

## Building both projections by hand

Take the User Registration FST from `03`:

```
States  = { PotentialCustomer (PC), RequiresConfirmation (RC),
            Confirmed (C), Deleted (D) }
Initial = PC
Final   = { D }

Transitions:
  (PC, StartRegistration)   → RegistrationStarted   → RC
  (RC, ConfirmAccount)      → AccountConfirmed      → C
  (RC, ResendConfirmation)  → ConfirmationResent    → RC
  (RC, FulfillGDPRRequest)  → ε                     → D
  (C,  FulfillGDPRRequest)  → AccountDeleted        → D
```

### Input projection (drop events)

```
π₁(T) acceptor over commands:

  (PC, StartRegistration)  → RC
  (RC, ConfirmAccount)     → C
  (RC, ResendConfirmation) → RC
  (RC, FulfillGDPRRequest) → D
  (C,  FulfillGDPRRequest) → D
```

This acceptor's "language" is the set of command sequences the
aggregate accepts. For example:

- `[StartRegistration, ConfirmAccount, FulfillGDPRRequest]` ✓
- `[StartRegistration, FulfillGDPRRequest]` ✓
- `[ConfirmAccount]` ✗ (no transition out of `PC`)
- `[StartRegistration, StartRegistration]` ✗ (no transition out of `RC`)

The input projection answers "which command sequences are
permitted by the model?"

### Output projection (drop commands)

```
π₂(T) acceptor over events:

  (PC, RegistrationStarted) → RC
  (RC, AccountConfirmed)    → C
  (RC, ConfirmationResent)  → RC
  (C,  AccountDeleted)      → D

  (Note: the ε-transition from RC to D had no event, so it
   produces no edge in the event projection.)
```

This acceptor's "language" is the set of event sequences the
aggregate produces. For example:

- `[RegistrationStarted, AccountConfirmed, AccountDeleted]` ✓
- `[RegistrationStarted, ConfirmationResent, AccountConfirmed]` ✓
- `[AccountConfirmed]` ✗ (no transition out of `PC`)
- `[RegistrationStarted, AccountDeleted]` ✗ (no transition out of `RC`)

The output projection answers "which event sequences could possibly
have come from the model?"

## The insight

**The output projection's transition function IS `evolve`.**

Read the output projection again:

```
(PC, RegistrationStarted) → RC
(RC, AccountConfirmed)    → C
(RC, ConfirmationResent)  → RC
(C,  AccountDeleted)      → D
```

Now read `evolve` from the decider in `02`:

```
evolve PotentialCustomer    RegistrationStarted = RequiresConfirmation
evolve RequiresConfirmation AccountConfirmed    = Confirmed
evolve RequiresConfirmation ConfirmationResent  = RequiresConfirmation
evolve Confirmed            AccountDeleted      = Deleted
evolve _ _                                       = (no transition)
```

Same transitions. Same partiality (no transition for invalid
combinations). The output projection's transition function and
`evolve` are the same thing under different names.

This is the key result. Define one FST. Project out the events. Get
`evolve` for free.

Replay falls out:

```
reconstitute :: [Event] -> Maybe State
reconstitute = foldlM evolve initialState
            -- ^ which is just running the output projection on
            --   the event sequence
```

## What `decide` becomes

The other half is similar. `decide` corresponds to the FST's output
function ω, restricted to commands valid in the current state:

```
decide :: Cmd -> State -> [Event]
decide cmd state = case (δ state cmd, ω state cmd) of
  (Nothing, _)        -> []         -- command rejected
  (Just _,  Nothing)  -> []         -- valid but ε-output (silent)
  (Just _,  Just e)   -> [e]        -- normal: one event
```

(For multi-event commands, we extend ω to return a list of events;
that's the GSM extension covered in the multi-event research note.
The principle is unchanged.)

## Why this matters

In the standard decider pattern (covered in `02`), you write `decide`
and `evolve` separately. The event-determinism contract — that they
agree — is your responsibility, enforced by tests if at all.

In the FST formulation, you write the FST once, and the library
**derives both functions from it**. They cannot disagree because they
came from the same source. The contract is mechanical, not
conventional.

```
┌──────────────────────┐         ┌────────────────────┐
│  Decider pattern      │         │  FST + projection   │
├──────────────────────┤         ├────────────────────┤
│  Write decide.        │         │  Write the FST.     │
│  Write evolve.        │   vs.   │  Project π₂.        │
│  Pray they agree.     │         │  Get evolve free.   │
│  Test exhaustively.   │         │  Always agrees.     │
└──────────────────────┘         └────────────────────┘
```

This is the property that motivates the entire library. Everything in
`docs/research/` is in service of preserving this property as we add
data, multi-event commands, composition, and effects.

## What this requires

To mechanically project from the FST to `evolve`, the library needs to
*invert* ω. Given an event `e`, it must find the command `c` such that
`ω(s, c) = e` so it can recover the next state from `δ(s, c)`.

In the simplest case (every transition has a unique event), this works
by enumeration over commands:

```
evolve s e = the unique s' such that
             ∃ c. δ(s, c) = Just s' AND ω(s, c) = Just e
```

Enumerating all commands requires that the command alphabet is
finite — `(Enum, Bounded)` in Haskell terms. That's fine for the toy
example: `Cmd` has four constructors. It's *not* fine when commands
carry payloads like `StartRegistration "alice@x.io" "Z9F4" t0` —
emails and timestamps are not enumerable.

This is the data problem. It's the whole reason `05` exists.

## In code: `Keiki.Acceptor`

The library exports `Keiki.Acceptor.inputAcceptor` and
`Keiki.Acceptor.outputAcceptor`, each producing an `Acceptor a s`
record (step function, initial state, final-state predicate) from a
`SymTransducer`. The state carrier is `(s, RegFile rs)` because edge
guards depend on the register file as well as the control vertex.
Use `accepts (inputAcceptor t) cmds :: Bool` to ask whether a
command sequence is in the input language; `accepts (outputAcceptor
t) events :: Bool` for the event language. The output acceptor's
`aStep` is exactly the `evolve` this chapter derives — it wraps
`applyEvent`, which inverts ω mechanically.

## Vocabulary recap

- **Input projection (π₁)** — the acceptor over the input alphabet
  obtained by dropping the FST's outputs. Its language is the
  permitted command sequences.
- **Output projection (π₂)** — the acceptor over the output alphabet
  obtained by dropping the FST's inputs. Its language is the
  producible event sequences.
- **Derivation of `evolve`** — the output projection's transition
  function, computed by inverting ω. Mechanical when the input
  alphabet is finite.
- **Replay / reconstitute** — `foldlM evolve initialState events`.
  Recovers state from a stored event sequence.
