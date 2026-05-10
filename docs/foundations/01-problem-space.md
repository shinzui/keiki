# 01 — The Problem Space

Three things that show up over and over in long-running business
systems:

1. **Event sourcing** — instead of storing the current state of a thing
   (an order, a user account, a shipment), store the immutable log of
   events that produced it. Replay the log to recover the state.
2. **Workflow engines** — coordinate long-running, multi-step processes
   that span hours, days, or months: order fulfillment, employee
   onboarding, multi-step approvals.
3. **Durable execution** — when a process is in the middle of a long
   workflow and the server crashes, the process should resume on
   recovery exactly where it left off, with no data loss and no double
   work.

These are usually treated as three separate engineering problems with
three separate solutions. keiki takes the position that they are facets
of one underlying thing — and that thing is well-modeled by an old idea
from automata theory.

## Tools you might use today

| Need | Common solutions |
|------|------------------|
| Event sourcing | EventStoreDB, Marten (Postgres), home-rolled on Postgres/Kafka, decider-pattern libraries (`tan-event-source` for Haskell, `crem` for Haskell, similar for Java/Kotlin/F#) |
| Workflow engine | Temporal, Cadence (predecessor), AWS Step Functions, Camunda |
| Durable execution | Temporal again, Restate, Azure Durable Functions |

Each of these works. If you only need one of the three, you can use the
specialized tool and stop reading.

## What's missing across all of them

Once you build a system that needs more than one of the three, the
seams start to hurt:

**No single formal model.** An event-sourced aggregate is "a thing with
`decide` and `evolve`." A workflow is "a function that calls activities
and yields." A saga is "a sequence of steps with compensating actions."
Three vocabularies, three runtimes, three sets of testing strategies.
The mental cost of mapping between them is constant.

**No mechanical derivation between command-handling and event-replay.**
In the standard event-sourcing decider pattern (covered in
`02-event-sourcing-and-the-decider.md`), you write `decide :: Cmd ->
State -> [Event]` and `evolve :: State -> Event -> State` separately.
Nothing checks that they agree. If `decide` says command C produces
event E, but `evolve` interprets E differently than `decide` intended,
your replay produces wrong state. Silently. There's no compile error,
no test failure unless you happened to write one.

**Workflows are opaque.** Temporal workflows are imperative code. You
can't ask "can this workflow deadlock?" or "are these two workflow
versions equivalent?" without running them. The only way to check is to
exercise paths in production.

**Composition is ad hoc.** Aggregates compose into sagas via subscription
glue. Sagas compose into larger workflows via more glue. Each
integration is hand-wired and hand-tested.

## The keiki bet

Lift all three onto **finite-state transducers** (FSTs), an automata
formalism from the 1960s.

The FST is a state machine that takes inputs and produces outputs. It
has a transition function (which next state am I in?) and an output
function (what do I emit?). With a few additions — partiality, ε-output,
final states, register tracking — it covers:

- An aggregate (commands → events, state evolved by events)
- A process manager / saga (events from one context → commands to
  others)
- A workflow (long-running process with timers and external activities)

All as the same kind of object. Same definition, same testing, same
analysis tools, same composition rules.

The pure core stays pure. The infrastructure (event store, queue,
subscriptions for side effects) is a separate, swappable layer
described in `docs/research/effects-boundary.md`.

## What this buys

- **One formalism.** An aggregate, a saga, and a workflow are all
  `Transducer s c e`. Composition rules apply uniformly.
- **Mechanical derivation.** Define the transducer once; the library
  derives the `decide`/`evolve` decomposition from it. They cannot
  disagree because they came from the same source.
- **Analyzability.** Ask "can this deadlock?" or "is this refactoring
  equivalent to the old version?" as questions you can answer at build
  time, not in production.
- **Pure pure.** No framework, no SDK, no runtime magic. The transducer
  is a value. The infrastructure is your existing event store + queue.

## What this costs

- **Vocabulary.** You need to learn a small amount of automata theory.
  These docs cover it.
- **Encoding effort up front.** Writing a transducer is more deliberate
  than writing imperative workflow code. You're stating the model
  precisely, not just programming the happy path.
- **Some operations are not yet decidable.** When data carries
  arbitrary payloads (real workflows always do), some analytical
  questions become semi-decidable or undecidable. We handle that
  honestly — see `05-data-carrying-alphabets.md`.

## What's next

`02-event-sourcing-and-the-decider.md` introduces the decider pattern
that the rest of the library is built on top of. If you already
understand event sourcing well, skim it for vocabulary and move on
to `03`.
