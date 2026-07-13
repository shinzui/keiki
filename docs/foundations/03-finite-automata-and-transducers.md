# 03 — Finite Automata and Transducers

This is the central conceptual chapter. We build up from the simplest
state machine (an acceptor) to the formalism keiki uses (a finite-state
transducer with partiality, ε-output, and final states).

If you've taken a CS theory course this is review — skim for
vocabulary. If not, read carefully; the rest of the library hangs on
the ideas here.

## Acceptor: the simplest state machine

A **deterministic finite automaton** (DFA), also called an **acceptor**,
is the simplest useful state machine. It reads a sequence of input
symbols one at a time and ends up either in an *accepting* state or a
*non-accepting* state.

```
DFA = ⟨S, Σ, δ, s₀, F⟩

S      = finite set of states
Σ      = finite set of input symbols (the alphabet)
δ      = S × Σ → S          transition function
s₀     = starting state
F ⊆ S  = accepting states
```

The DFA "accepts" an input sequence if, after reading every symbol,
it's in an accepting state.

### Worked example

A DFA that accepts sequences with an even number of `a`s:

```
       a
   ┌──────►
[Even]      [Odd]
   ◄──────┘
       a
```

`Even` is the start state and the only accepting state.
- Input `aa`: `Even → Odd → Even`. Accept.
- Input `aaa`: `Even → Odd → Even → Odd`. Reject.

The "language" of this DFA is the set of all input strings it accepts.
Acceptors classify input sequences as valid or invalid.

## Mealy machine: adding output

A **Mealy machine** is a DFA that also produces output. On every
transition, it emits an output symbol.

```
Mealy = ⟨S, Σ, Γ, δ, ω, s₀⟩

S   = states
Σ   = input alphabet
Γ   = output alphabet
δ   = S × Σ → S         transition function (next state)
ω   = S × Σ → Γ         output function     (emitted symbol)
s₀  = start state
```

Properties:

- **Total**: defined for every (state, input) pair. Always produces a
  next state and an output.
- **Deterministic**: exactly one transition per (state, input).
- **Real-time**: one input in → one output out.
- **No final states**: runs until input is exhausted.

Mealy machines are great for things like "transform every character of
an input string into something else." They're not enough for our needs
because they have to produce *something* on every input.

## Finite-state transducer (FST)

An **FST** generalizes the Mealy machine in three ways that turn out
to matter for aggregates and workflows:

1. **Partial**: some (state, input) pairs may have *no* transition.
   The machine "rejects" the input rather than producing a next state.
2. **ε-output**: a transition can change state without producing any
   output (the "ε" stands for "empty").
3. **Final states**: some states are accepting/terminal. The machine
   has a notion of "done."

```
FST = ⟨S, Σ, Γ, δ, ω, s₀, F⟩

S      = states
Σ      = input alphabet
Γ      = output alphabet
δ      = S × Σ → Maybe S        transition (partial)
ω      = S × Σ → Maybe Γ        output (ε if Nothing on a valid transition)
s₀     = start state
F ⊆ S  = final states
```

Same shape as a Mealy machine, but `δ` and `ω` are partial.

(There are even more general definitions — non-deterministic FSTs, FSTs
that consume or produce strings instead of single symbols, etc. keiki
uses the deterministic letter FST above plus a register extension
introduced in `05`. The hierarchy is in
`docs/research/formalism-choice-mealy-machines-vs-finite-state-transducers.md` §3.)

## Why each generalization matters for aggregates

This is the crucial argument: aggregates from `02` are not Mealy
machines. They need every one of the three FST features.

### Partial transitions = invariants

> "You cannot confirm an account that hasn't registered."

A Mealy machine must produce *something* for every (state, input) pair.
What should it produce for `(PotentialCustomer, ConfirmAccount)`?
There's no good answer. You could pick a "no-op" output, but then the
aggregate accepts an invalid command and silently does nothing —
exactly the bug class we're trying to avoid.

An FST returns `Nothing` for `δ(PotentialCustomer, ConfirmAccount)`.
That `Nothing` IS the invariant. The aggregate's command-handling
layer sees `Nothing` and rejects the command with an error.

### Final states = lifecycle termination

> "Once an account is deleted, no further events can occur on it."

Aggregates have terminal states: `Deleted`, `Closed`, `Archived`,
`Cancelled`. A Mealy machine has no concept of "done"; it runs
forever. An FST's final states model termination natively.

### ε-output = silent transitions

> "Fulfilling a GDPR delete request on an unconfirmed account changes
> state but emits no event (we promised not to record their data)."

A Mealy machine always produces output. An FST can transition with
`ω(s, c) = Nothing` — state changes, no event emitted. The transition
is internal but "real."

## A concrete FST

Take a letter-only simplification of the User Registration aggregate
from `02` and write it as an FST (the shipped example later widens
`StartRegistration` to two outputs):

```
States  = { PotentialCustomer, RequiresConfirmation, Confirmed, Deleted }
Inputs  = { StartRegistration, ConfirmAccount, ResendConfirmation,
            FulfillGDPRRequest }
Outputs = { RegistrationStarted, ConfirmationEmailSent, AccountConfirmed,
            ConfirmationResent, AccountDeleted }
Initial = PotentialCustomer
Final   = { Deleted }

Transitions:
  (PotentialCustomer,    StartRegistration)   →  RegistrationStarted   →  RequiresConfirmation
  (RequiresConfirmation, ConfirmAccount)      →  AccountConfirmed       →  Confirmed
  (RequiresConfirmation, ResendConfirmation)  →  ConfirmationResent     →  RequiresConfirmation
  (RequiresConfirmation, FulfillGDPRRequest)  →  AccountDeleted         →  Deleted
  (Confirmed,            FulfillGDPRRequest)  →  AccountDeleted          →  Deleted

Anything not listed: δ returns Nothing.  Invariant.
```

Notes:

- Both GDPR transitions emit `AccountDeleted`. A silent deletion would
  lose the state change during event-log replay, so the durable example
  makes it observable.
- `Deleted` is final. No transitions leave it.
- Every "missing" entry (e.g., `(PotentialCustomer, ConfirmAccount)`)
  is an invariant violation: command rejected.

This FST has the same business meaning as the Decider in `02`, but
it's a single object instead of two functions. The next chapter shows
why that matters.

## Note: this is the simplest case

The FST above maps each (state, command) to **at most one event**.
Real aggregates often produce multiple events from one command (the
"register an account" command in `02` produces both
`RegistrationStarted` AND `ConfirmationEmailSent`). keiki widens the
output function from one-event-per-transition to a *word* of events
per transition — formally a Generalized Sequential Machine (GSM)
rather than a Mealy / letter FST. The widening is documented in
`docs/research/gsm-widening-design.md`; the user-facing guide is
`docs/guide/multi-event-commands.md`. The parent research note
`docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`
covers the alternatives that were considered. For the foundations,
the one-event-per-transition FST gives the cleanest intuition; the
GSM extension is mechanically derivable from it.

## Vocabulary recap

- **Acceptor / DFA** — state machine that accepts or rejects input
  sequences. No output.
- **Mealy machine** — total state machine with output. Always one
  output per input.
- **Finite-state transducer (FST)** — partial state machine with
  output, ε-transitions, and final states.
- **Alphabet** — the (finite, in classical FSTs) set of input or
  output symbols.
- **Partiality** — `δ(s, c)` may be `Nothing`. Encodes invariants.
- **ε-output** — a transition with no emitted output. Encodes silent
  state changes.
- **Final states** — terminal states. Encodes lifecycle endings.
- **Language** — the set of input sequences an acceptor accepts, or the
  set of input/output pairs an FST produces.
