# 02 — Event Sourcing and the Decider Pattern

## The core idea

Most systems store the **current state** of a thing:

```
users
─────────────────────────────────────
id   | email      | confirmed | …
42   | alice@x.io | true      | …
```

Event-sourced systems store the **immutable log of events** that
produced the current state:

```
events for user-42
─────────────────────────────────────
1.  RegistrationStarted   email="alice@x.io", code="Z9F4", at=t0
2.  ConfirmationEmailSent email="alice@x.io"
3.  AccountConfirmed      email="alice@x.io", at=t1
```

To get the current state, you replay the events:

```
state₀ = empty
state₁ = evolve state₀ event₁
state₂ = evolve state₁ event₂
state₃ = evolve state₂ event₃   ← current state
```

The current state is a *derived view*; the log is the source of truth.

## Why bother

- **Full audit trail by construction.** Nothing changes the state
  except an appended event; nothing modifies past events.
- **Time travel.** State at any past moment is `replay events_up_to_t`.
- **Multiple read models.** Different consumers can build different
  projections from the same event log.
- **Recovery.** Lose your read database; rebuild it from the event
  store.
- **Decoupling.** Other services subscribe to the event stream and
  react. You don't have to know who's listening.

The cost is real (more moving parts, schema evolution is harder, you
have to think about idempotence), but for systems that need
auditability or have many downstream consumers it's often worth it.

## Aggregates

An **aggregate** is a consistency boundary — a thing whose state is
mutated only by its own commands and only as a single transaction at
a time. In event-sourced terms: an aggregate owns one event stream.
A user is an aggregate. An order is an aggregate. A shipment is an
aggregate.

Aggregates do not directly call other aggregates. They emit events;
other aggregates (or process managers, or external services) react.

## The decider pattern

The decider pattern (formalized by Jérémie Chassaing in his article
series and the F#/Haskell `tan-event-source` library) decomposes the
aggregate into two pure functions:

```haskell
data Decider c e s = Decider
  { decide :: c -> s -> [e]   -- handle a command, produce events
  , evolve :: s -> e -> s     -- apply an event to advance state
  , initial :: s
  }
```

To process a command:

```
1.  Load current state by replaying past events.
        s = foldl evolve initial events
2.  Decide what events the command produces.
        new_events = decide cmd s
3.  Append new events to the store.
4.  (Optionally) compute the new state for the response.
        s' = foldl evolve s new_events
```

That's the entire pattern. Both functions are pure. State is never
mutated; it's always derived from events.

### Worked example: User Registration

```haskell
data State = PotentialCustomer
           | RequiresConfirmation { email :: Email, code :: ConfirmationCode }
           | Confirmed            { email :: Email }
           | Deleted

data Cmd = StartRegistration Email ConfirmationCode UTCTime
         | ConfirmAccount    ConfirmationCode UTCTime
         | FulfillGDPRRequest UTCTime

data Event = RegistrationStarted   Email ConfirmationCode UTCTime
           | ConfirmationEmailSent Email
           | AccountConfirmed      Email UTCTime
           | AccountDeleted        Email UTCTime

decide :: Cmd -> State -> [Event]
decide (StartRegistration email code at) PotentialCustomer =
  [ RegistrationStarted email code at, ConfirmationEmailSent email ]
decide (ConfirmAccount code at) (RequiresConfirmation email expected)
  | code == expected = [ AccountConfirmed email at ]
decide (FulfillGDPRRequest at) (Confirmed email) =
  [ AccountDeleted email at ]
decide _ _ = []   -- invalid command in this state: produce no events

evolve :: State -> Event -> State
evolve PotentialCustomer (RegistrationStarted email code _) =
  RequiresConfirmation email code
evolve s@(RequiresConfirmation _ _) (ConfirmationEmailSent _) = s
evolve (RequiresConfirmation email _) (AccountConfirmed _ _) =
  Confirmed email
evolve (Confirmed _) (AccountDeleted _ _) = Deleted
evolve s _ = s   -- shouldn't happen if decide is correct
```

Process a command:

```
1.  state = foldl evolve PotentialCustomer pastEvents
        — say state = RequiresConfirmation "alice@x.io" "Z9F4"
2.  newEvents = decide (ConfirmAccount "Z9F4" t1) state
        — = [AccountConfirmed "alice@x.io" t1]
3.  append newEvents to the event store
4.  state' = foldl evolve state newEvents
        — = Confirmed "alice@x.io"
```

## The hidden contract

`decide` and `evolve` are written separately. Nothing in the type
system enforces that they agree.

Suppose someone refactors `decide` to emit a new field on
`AccountConfirmed` but forgets to update `evolve`. The aggregate still
typechecks. New commands still produce new events. The events still
get stored. But `evolve`, ignorant of the new field, computes the
wrong next state during replay. Days later, a downstream subscriber
gets corrupted data.

This is the **event-determinism contract**:

> For every (state, command) pair such that
> `decide cmd s = [e₁, e₂, …, eₙ]`,
> the result of `foldl evolve s [e₁, e₂, …, eₙ]` must equal the
> intended next state.

It's enforceable only by tests and code review. The standard decider
pattern has no mechanical guarantee that the two halves of the model
agree.

## The keiki angle

The rest of the foundations — and the library — is built around making
this contract mechanical instead of conventional.

The move is: define the aggregate **once**, as a richer object (a
finite-state transducer, covered in `03`), and **derive** both `decide`
and `evolve` from that single definition. They cannot disagree because
there's only one source of truth.

That's what the next two docs build up to.

## Vocabulary recap

- **Event store** — append-only log, partitioned by stream
  (typically one stream per aggregate instance).
- **Aggregate** — a consistency boundary; owns a stream.
- **Command** — an intent to change state, validated against current
  state.
- **Event** — an immutable fact about something that happened.
- **State** — derived from events; never stored as the source of truth
  (except for snapshots, which are an optimization).
- **Decider** — the pair `(decide, evolve, initial)` that defines an
  aggregate.
- **Replay / reconstitute** — `foldl evolve initial events` to recover
  state.
- **Projection / read model** — a view derived from the event stream
  for query purposes (separate from the aggregate state).
