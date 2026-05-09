# Transducers for Orchestration

> **Status: historical (encoding only).** The conceptual content —
> sagas, process managers, choreography, compensating transactions,
> aggregate ↔ policy feedback as composed transducers — is still
> sound and is referenced from `effects-boundary.md` and
> `composition-combinators-design.md`. The *encoding* throughout uses
> the toy `Transducer s c e` shape (`delta s c -> Maybe s`,
> `omega s c -> Maybe e`, `compose : Transducer s1 c e1 -> Transducer s2 e1 e2 -> Transducer (s1, s2) c e2`,
> `inputProjection` / `outputProjection`, `toDecider`). None of those
> signatures match the shipped `SymTransducer` / `Keiki.Composition` /
> `Keiki.Acceptor` / `Keiki.Decider` surface. Read for patterns; map
> the encoding to current names via
> `architecture-comparison-keiki-vs-crem.md`.

Transducers model orchestration naturally because a process manager,
saga, or policy is itself a transducer — it consumes events and produces
commands, maintaining state to track progress. This document shows how
each orchestration pattern maps to the FST formalism and what formal
guarantees the automata operations provide.

---

## The Core Insight

An aggregate transducer maps commands to events:

```
T_aggregate: Commands → Events
```

An orchestrator transducer maps events to commands:

```
T_orchestrator: Events → Commands
```

These are both transducers — they differ only in what their input and
output alphabets represent. The FST formalism doesn't distinguish
between "command" and "event" — it just has input and output alphabets.
This symmetry is what makes orchestration a natural fit.

```
T_aggregate     = ⟨S, C, E, δ, ω, s₀, F⟩     commands in, events out
T_orchestrator  = ⟨S', E, C', δ', ω', s₀', F'⟩   events in, commands out
```

---

## Orchestration Patterns

### 1. Saga / Process Manager

A saga coordinates a multi-step business process across multiple
aggregates. It receives events from aggregates and issues commands to
aggregates, tracking its own progress through the process.

**Example: Order Fulfillment Saga**

```
States:  {AwaitingPayment, PaymentReceived, Shipping, Shipped, Completed, Failed}
Input:   Events from Order + Payment + Shipping aggregates
Output:  Commands to Payment + Shipping + Notification aggregates

ω(AwaitingPayment,  OrderPlaced)        = InitiatePayment
ω(AwaitingPayment,  PaymentFailed)      = CancelOrder
ω(PaymentReceived,  PaymentConfirmed)   = RequestShipment
ω(Shipping,         ShipmentDispatched) = SendTrackingEmail
ω(Shipped,          DeliveryConfirmed)  = CompleteOrder
```

As a transducer:

```haskell
data SagaState
  = AwaitingPayment
  | PaymentReceived
  | Shipping
  | Shipped
  | Completed
  | Failed
  deriving (Eq, Show, Enum, Bounded)

data SagaInput   -- events from various aggregates
  = OrderPlaced
  | PaymentConfirmed
  | PaymentFailed
  | ShipmentDispatched
  | DeliveryConfirmed
  deriving (Eq, Show, Enum, Bounded)

data SagaOutput  -- commands to various aggregates
  = InitiatePayment
  | CancelOrder
  | RequestShipment
  | SendTrackingEmail
  | CompleteOrder
  deriving (Eq, Show, Enum, Bounded)

orderFulfillment :: Transducer SagaState SagaInput SagaOutput
orderFulfillment = Transducer
  { delta = \s e -> case (s, e) of
      (AwaitingPayment, OrderPlaced)        -> Just PaymentReceived
      (AwaitingPayment, PaymentFailed)      -> Just Failed
      (PaymentReceived, PaymentConfirmed)   -> Just Shipping
      (Shipping,        ShipmentDispatched) -> Just Shipped
      (Shipped,         DeliveryConfirmed)  -> Just Completed
      _                                     -> Nothing
  , omega = \s e -> case (s, e) of
      (AwaitingPayment, OrderPlaced)        -> Just InitiatePayment
      (AwaitingPayment, PaymentFailed)      -> Just CancelOrder
      (PaymentReceived, PaymentConfirmed)   -> Just RequestShipment
      (Shipping,        ShipmentDispatched) -> Just SendTrackingEmail
      (Shipped,         DeliveryConfirmed)  -> Just CompleteOrder
      _                                     -> Nothing
  , initial = AwaitingPayment
  , isFinal = \case { Completed -> True; Failed -> True; _ -> False }
  }
```

**What the FST operations give us:**

```haskell
-- Which event sequences can this saga handle?
sagaInputAcceptor :: Acceptor SagaState SagaInput
sagaInputAcceptor = inputProjection orderFulfillment
-- accepts [OrderPlaced, PaymentConfirmed, ShipmentDispatched, DeliveryConfirmed]
-- rejects [PaymentConfirmed, OrderPlaced]  (wrong order)
-- rejects [OrderPlaced, DeliveryConfirmed] (skipped steps)

-- Which command sequences can the saga produce?
sagaOutputAcceptor :: Acceptor SagaState SagaOutput
sagaOutputAcceptor = outputProjection orderFulfillment
-- accepts [InitiatePayment, RequestShipment, SendTrackingEmail, CompleteOrder]
-- accepts [CancelOrder]  (failure path)

-- Reconstitute saga state from event history
sagaDecider :: Decider SagaInput SagaOutput SagaState
sagaDecider = toDecider orderFulfillment
-- reconstitute sagaDecider [OrderPlaced, PaymentConfirmed] = Just Shipping
```

### 2. Choreography (Transducer Composition)

In choreography, there's no central coordinator. Each aggregate's events
directly trigger the next aggregate's behavior. This is **transducer
composition**:

```
T₁ ∘ T₂: T₁'s events feed T₂'s commands
```

**Example: Registration → Email Verification → Onboarding**

```haskell
registration :: Transducer RegState RegCommand RegEvent
-- StartRegistration → ConfirmationSent
-- ConfirmAccount    → AccountConfirmed

emailVerification :: Transducer VerifState RegEvent VerifEvent
-- ConfirmationSent → VerificationEmailDispatched
-- AccountConfirmed → WelcomeEmailDispatched

-- Composed: registration commands → verification events
pipeline :: Transducer (RegState, VerifState) RegCommand VerifEvent
pipeline = compose registration emailVerification
```

The composed transducer processes registration commands end-to-end,
producing email verification events. No saga needed — the composition
IS the choreography.

**Formal guarantees from composition:**

- `inputProjection pipeline` = valid command sequences for the full flow
- `outputProjection pipeline` = valid verification event sequences
- If `registration` and `emailVerification` are individually correct,
  the composition is correct (compositionality)

### 3. Compensating Transactions

A compensating saga must undo previous steps when a later step fails.
The transducer models this by having failure transitions that produce
compensating commands:

```haskell
data CompState = S0 | Step1Done | Step2Done | Compensating1 | Compensated | Completed
  deriving (Eq, Show, Enum, Bounded)

data CompInput = Step1Ok | Step2Ok | Step2Failed | Comp1Done
  deriving (Eq, Show, Enum, Bounded)

data CompOutput = DoStep2 | DoCompensate1 | AckComplete | AckCompensated
  deriving (Eq, Show, Enum, Bounded)

compensatingSaga :: Transducer CompState CompInput CompOutput
compensatingSaga = Transducer
  { delta = \s e -> case (s, e) of
      (S0,            Step1Ok)     -> Just Step1Done
      (Step1Done,     Step2Ok)     -> Just Completed
      (Step1Done,     Step2Failed) -> Just Compensating1    -- failure: compensate
      (Compensating1, Comp1Done)   -> Just Compensated
      _                            -> Nothing
  , omega = \s e -> case (s, e) of
      (S0,            Step1Ok)     -> Just DoStep2
      (Step1Done,     Step2Ok)     -> Just AckComplete
      (Step1Done,     Step2Failed) -> Just DoCompensate1    -- emit compensation
      (Compensating1, Comp1Done)   -> Just AckCompensated
      _                            -> Nothing
  , initial = S0
  , isFinal = \case { Completed -> True; Compensated -> True; _ -> False }
  }
```

**The output projection reveals both paths:**

```
Happy path:        [DoStep2, AckComplete]
Compensation path: [DoStep2, DoCompensate1, AckCompensated]
```

Both are valid words in the output language. The Acceptor from
`outputProjection` recognizes exactly these two sequences (plus any
with additional intermediate steps if the saga is more complex).

### 4. Policy / Reactor

A policy is the simplest orchestrator — a stateless (or nearly stateless)
transducer that maps individual events to commands:

```haskell
-- Stateless: every event maps independently to a command
fraudPolicy :: Transducer () FraudEvent FraudCommand
fraudPolicy = Transducer
  { delta = \() _ -> Just ()            -- always valid, no state change
  , omega = \() e -> case e of
      HighValueTransaction -> Just FlagForReview
      SuspiciousLogin      -> Just LockAccount
      _                    -> Nothing   -- ignore other events
  , initial = ()
  , isFinal = const False               -- policies run forever
  }
```

A policy with no final states and trivial state is essentially a pure
function `Event -> Maybe Command` lifted into the transducer formalism.
This gives it composability — it can participate in `compose`, `union`,
and `concatenate` like any other transducer.

### 5. Feedback Loops (Aggregate ↔ Policy)

The most complex pattern: an aggregate produces events, a policy
consumes them and produces commands, which feed back to the aggregate.
This is the feedback loop that crem models with its `Feedback`
combinator.

In the transducer formalism, this is a **fixed-point** of composition:

```
T_loop = T_aggregate ∘ T_policy ∘ T_aggregate ∘ T_policy ∘ ...
```

Or more precisely, the aggregate and policy form a **closed system**
where the output of each feeds the input of the other until both
quiesce:

```
          ┌──────────────────────────────────────┐
          │                                      │
Commands  │   ┌─────────────┐    Events    ┌─────────┐
─────────►│   │  Aggregate  │─────────────►│  Policy │
          │   │  T_agg      │              │  T_pol  │
          │   └─────────────┘              └────┬────┘
          │         ▲                           │
          │         │      Commands             │
          │         └───────────────────────────┘
          │                (feedback)
          └──────────────────────────────────────┘
```

In our formalism, this can be modeled as a GSM where a single external
command triggers a cascade of internal transitions:

```haskell
-- The feedback loop as a GSM:
-- One external command may produce multiple events
-- (from the aggregate + all policy reactions)
feedbackLoop :: GSM (AggState, PolicyState) ExternalCommand AllEvents
```

Or, following crem's approach, as an explicit fixed-point combinator:

```haskell
feedback
  :: (Foldable n, Monoid (n e))
  => Transducer s1 c (n e)          -- aggregate: command → events
  -> Transducer s2 e (n c)          -- policy: event → commands
  -> Transducer (s1, s2) c (n e)    -- closed loop
```

The formal value: the **output projection of the feedback loop** gives
us the complete set of event sequences the system can produce,
including all policy-triggered cascades. This is valuable for:

- Verifying that the system terminates (no infinite loops)
- Understanding the full impact of a single command
- Testing all possible cascade paths

---

## Formal Guarantees for Orchestration

The FST operations provide guarantees that ad-hoc saga implementations
cannot:

### Input Projection: "What can this orchestrator handle?"

```haskell
inputProjection :: Transducer s e c -> Acceptor s e
```

Given an orchestrator transducer, the input projection tells you exactly
which event sequences it can process. This is the orchestrator's
**contract with the upstream aggregates**: "I handle these event
sequences and no others."

If an aggregate produces an event sequence outside this language, the
orchestrator will reject it — detected at the first invalid event,
not after processing half the sequence.

### Output Projection: "What can this orchestrator emit?"

```haskell
outputProjection :: Transducer s e c -> Acceptor s c
```

The output projection tells you exactly which command sequences the
orchestrator can produce. This is its **contract with the downstream
aggregates**: "I will issue these command sequences and no others."

You can verify that the downstream aggregates accept every command
sequence the orchestrator can produce:

```haskell
-- The orchestrator's output language must be a subset of
-- the aggregate's input language
prop_contractCompatibility =
  forAll (genEvents sagaOutputAcceptor range) $ \cmds ->
    accepts aggregateInputAcceptor cmds
```

### Composition: "What does the end-to-end system do?"

```haskell
compose :: Transducer s1 c e1 -> Transducer s2 e1 e2 -> Transducer (s1, s2) c e2
```

The composed transducer IS the end-to-end system specification. Its
input projection is the set of valid external commands. Its output
projection is the set of observable events. Everything in between —
intermediate events, saga state, compensation logic — is internal.

### Event Sourcing the Orchestrator

Because the saga is a transducer, it gets event sourcing for free:

```haskell
sagaDecider = toDecider orderFulfillment

-- Reconstitute saga state from its event history
currentState = reconstitute sagaDecider
  [InitiatePayment, RequestShipment, SendTrackingEmail]
-- Just Shipped
```

The saga's own state is event-sourced — reconstructed from the commands
it has issued. This means the saga is recoverable: on restart, replay
its output history to recover its progress.

---

## Comparison with crem's Approach

| Pattern | crem encoding | Transducer encoding |
|---------|--------------|---------------------|
| Saga | `Feedback aggregate policy` | `compose aggregate saga` or explicit `feedback` |
| Choreography | `Sequential t1 t2` | `compose t1 t2` |
| Policy | `StateMachine event command` | `Transducer () event command` |
| Compensation | In saga state + action function | In saga δ/ω with compensation transitions |
| Feedback loop | `Feedback` combinator (built-in) | `feedback` combinator (to build) or GSM |

crem's `Feedback` combinator is more ergonomic — it handles the
iteration automatically via `runMultiple` and `Monoid` accumulation.
Our transducer formalism requires building this combinator explicitly,
but gains the formal operations (projection, Acceptor derivation) that
crem doesn't have.

The ideal is both: crem's Feedback for runtime execution, transducer
projection for formal analysis. Define the saga as a transducer, verify
its properties via projection, then lift it to a composed `StateMachineT`
for production execution.

---

## Summary

| Orchestration Pattern | Transducer Model | Key FST Operation |
|-----------------------|-----------------|-------------------|
| Saga / Process Manager | Events→Commands transducer with progress state | Projection (input = handled events, output = issued commands) |
| Choreography | Composition T₁ ∘ T₂ ∘ ... ∘ Tₙ | Compose (end-to-end transduction) |
| Compensating Transaction | Saga with failure/compensation transitions | Output projection (reveals all paths including compensation) |
| Policy / Reactor | Stateless or near-stateless transducer | Compose (plug into any pipeline) |
| Feedback Loop | Fixed-point of aggregate ∘ policy | Feedback combinator + output projection (verify termination) |
| Contract Verification | Compare projections of adjacent transducers | Input/output projection (language inclusion check) |

Transducers aren't just for aggregates. Every component in an
event-driven architecture — aggregates, sagas, policies, projections —
is a transducer. The FST operations let you compose them, project them,
and verify their contracts formally. The aggregate is where the theory
started, but orchestration is where it delivers the most practical
value.
