# FST as Workflow Runtime

> **Status: historical.** This note's central type is the toy
> `ExtTransducer s ctx c e` from the EFSM era. keiki rejected EFSM in
> favour of the symbolic-register transducer (`SymTransducer phi rs s ci co`),
> so the code sketches throughout do not match the shipped library. The
> *runtime architectural ideas* (event store, queue, subscriptions,
> timers, activities, signals, child workflows, cancellation,
> versioning, snapshotting) survived into `effects-boundary.md`, which
> is now the authoritative reference for the pure-core / runtime split.
> Read this doc for the runtime-capability survey and the Temporal /
> Cadence positioning, not for the encoding.

How the transducer formalism, paired with an event-sourced database and
message queue, covers the capabilities of dedicated workflow engines like
Temporal and Cadence — and what it gives you that they don't.

---

## The Architecture

```
              Command                          Event
           (from queue)                     (to event store)
                │                                ▲
                ▼                                │
    ┌───────────────────────────┐                │
    │    Extended Transducer    │                │
    │    (pure state machine)   │                │
    │                           │                │
    │  s   = control state      │   (s, ctx) ──► event
    │  ctx = data context       │                │
    │  δ   = control transition │                │
    │  ω   = output event       │                │
    │  ρ   = context update     │                │
    └───────────────────────────┘                │
                                                 │
                                    ┌────────────┴──────────┐
                                    │     Event Store       │
                                    │  (durability + replay) │
                                    └────────────┬──────────┘
                                                 │
                                    ┌────────────▼──────────┐
                                    │    Subscriptions      │
                                    │  (effect interpreter) │
                                    └──┬─────┬─────┬───┬───┘
                                       │     │     │   │
                                    Timer  Activity Route  Notify
                                    Svc    Executor  Cmd   Svc
                                       │     │     │   │
                                       └──┬──┘     └─┬─┘
                                          ▼          ▼
                                       Queue      Queue
                                    (delayed)   (commands)
```

The FST is pure. The event store provides durability. Subscriptions
interpret output events as infrastructure actions. The queue feeds
results back as input commands. This is the complete runtime — no
additional framework needed.

---

## 1. Extended Transducer (EFSM)

The standard Transducer requires `(Enum, Bounded)` on all type
parameters. This works for aggregates where state is a small enum, but
complex workflows carry dynamic data: approval lists, retry counters,
collected results, variable-length queues.

The solution: separate **control state** (finite, analyzable) from
**data context** (arbitrary, opaque to formal analysis).

```haskell
data ExtTransducer s ctx c e = ExtTransducer
  { delta   :: s -> ctx -> c -> Maybe s      -- control transition (may use guards on ctx)
  , omega   :: s -> ctx -> c -> Maybe e      -- output event
  , rho     :: s -> ctx -> c -> ctx          -- context update ("register transfer")
  , initial :: s
  , initialCtx :: ctx
  , isFinal :: s -> Bool
  }
```

In automata theory this is an **Extended Finite State Machine** — a
finite control unit augmented with registers. The formal model:

```
EFSM = ⟨S, Ctx, C, E, δ, ω, ρ, s₀, ctx₀, F⟩

S    = control states     (Enum, Bounded — finite, enumerable)
Ctx  = data context       (arbitrary — counters, maps, sets, whatever)
C    = input alphabet     (Enum, Bounded)
E    = output alphabet    (Enum, Bounded)
δ    = S → Ctx → C → Maybe S
ω    = S → Ctx → C → Maybe E
ρ    = S → Ctx → C → Ctx
```

### What you keep

- Exhaustive enumeration of control transitions (parameterized by
  representative contexts via property tests)
- Deadlock detection on the control flow graph
- Soundness checking (reachability + liveness)
- Input/output projection over control states
- All composition operations (product, concatenation, feedback)

### What changes

- `outputProjection` can no longer mechanically derive `apply` — context
  updates depend on the original command, which is lost during projection
- You provide `apply` by hand (Approach 3 from MULTI-EVENT.md)
- The event-determinism invariant is verified by property test:

```haskell
prop_eventDeterminism s ctx c =
  case delta ext s ctx c of
    Nothing -> discard
    Just s' ->
      let e = omega ext s ctx c
          ctx' = rho ext s ctx c
      in  apply extDecider (s, ctx) e === Just (s', ctx')
```

### Example: Multi-Approval Workflow

A workflow requiring N approvals before proceeding — impossible with
plain `(Enum, Bounded)` state, natural with EFSM:

```haskell
data ApprovalControl = Pending | Collecting | Approved | Rejected
  deriving (Eq, Show, Enum, Bounded)

data ApprovalCtx = ApprovalCtx
  { approvedBy     :: Set UserId
  , rejectedBy     :: Set UserId
  , requiredCount  :: Int
  , submittedDoc   :: DocumentId
  }

data ApprovalCmd
  = StartReview DocumentId Int    -- doc id + required count
  | SubmitApproval UserId
  | SubmitRejection UserId
  | Escalate UserId
  deriving (Eq, Show, Enum, Bounded)

data ApprovalEvent
  = ReviewStarted DocumentId Int
  | ApprovalRecorded UserId
  | RejectionRecorded UserId
  | ThresholdReached
  | ReviewRejected UserId
  | EscalationGranted UserId
  deriving (Eq, Show, Enum, Bounded)

multiApproval :: ExtTransducer ApprovalControl ApprovalCtx ApprovalCmd ApprovalEvent
multiApproval = ExtTransducer
  { delta = \s ctx c -> case (s, c) of
      (Pending,    StartReview _ _)      -> Just Collecting
      (Collecting, SubmitApproval uid)
        | uid `Set.member` approvedBy ctx -> Nothing  -- already voted
        | Set.size (approvedBy ctx) + 1 >= requiredCount ctx
                                          -> Just Approved
        | otherwise                       -> Just Collecting
      (Collecting, SubmitRejection _)     -> Just Rejected
      (Collecting, Escalate _)            -> Just Approved
      _                                   -> Nothing

  , omega = \s ctx c -> case (s, c) of
      (Pending,    StartReview doc n)     -> Just (ReviewStarted doc n)
      (Collecting, SubmitApproval uid)
        | Set.size (approvedBy ctx) + 1 >= requiredCount ctx
                                          -> Just ThresholdReached
        | otherwise                       -> Just (ApprovalRecorded uid)
      (Collecting, SubmitRejection uid)   -> Just (ReviewRejected uid)
      (Collecting, Escalate uid)          -> Just (EscalationGranted uid)
      _                                   -> Nothing

  , rho = \s ctx c -> case (s, c) of
      (Pending,    StartReview doc n)     -> ctx { submittedDoc = doc
                                                 , requiredCount = n }
      (Collecting, SubmitApproval uid)    -> ctx { approvedBy = Set.insert uid (approvedBy ctx) }
      (Collecting, SubmitRejection uid)   -> ctx { rejectedBy = Set.insert uid (rejectedBy ctx) }
      _                                   -> ctx

  , initial    = Pending
  , initialCtx = ApprovalCtx Set.empty Set.empty 0 (DocumentId "")
  , isFinal    = \case { Approved -> True; Rejected -> True; _ -> False }
  }
```

The control flow has 4 states — fully enumerable, checkable for
deadlocks and soundness. The context carries the dynamic data that
makes each instance unique.

### Relationship to base Transducer

The plain Transducer is the degenerate case `ExtTransducer s () c e`
where context is unit. All existing theory applies. The ExtTransducer
is a conservative extension.

```haskell
liftTransducer :: Transducer s c e -> ExtTransducer s () c e
liftTransducer t = ExtTransducer
  { delta   = \s () c -> delta t s c
  , omega   = \s () c -> omega t s c
  , rho     = \_ () _ -> ()
  , initial = initial t
  , initialCtx = ()
  , isFinal = isFinal t
  }
```

---

## 2. Infrastructure Interpretation

The FST remains pure. Infrastructure behavior is encoded in the
**interpretation** of output events by subscriptions reading from
the event store. This is where the existing ES + queue does the
heavy lifting.

### Durable Execution = Event Sourcing (already have it)

On crash or restart:

```haskell
recover :: EventStore -> WorkflowId -> IO (ApprovalControl, ApprovalCtx)
recover store wfId = do
  events <- readStream store wfId
  case reconstitute extDecider events of
    Just state -> pure state
    Nothing    -> error "corrupt event history"
```

Replay the event stream, recover full state. This is Temporal's
"deterministic replay" — but explicit and under your control.

### Timers = Infrastructure-Injected Commands

Timers stay out of the FST. The pattern:

1. FST emits an output event indicating a timer is needed
2. A subscription reads the event, schedules a delayed message on the
   queue
3. When the delay expires, the queue delivers a command to the FST
4. The FST handles the timer command like any other input

```haskell
-- In the FST's alphabets:
data WfCmd = ... | TimerFired TimerId
data WfEvt = ... | TimerScheduled TimerId Duration

-- In the FST's transitions:
omega (AwaitingPayment, ctx) (OrderSubmitted ...) =
  Just (TimerScheduled "payment-deadline" (hours 24))

delta (AwaitingPayment, ctx) (TimerFired "payment-deadline") =
  Just TimedOut

-- Infrastructure subscription (outside the FST):
-- on TimerScheduled: enqueue delayed message → TimerFired after duration
```

For recurring timers, the FST emits a new `TimerScheduled` event on
each cycle. The subscription is stateless — it just converts
`TimerScheduled` events into delayed queue messages.

**Cancellation of pending timers**: The subscription can check whether
the workflow has advanced past the timer's relevant state before
delivering `TimerFired`. Or the FST can reject `TimerFired` via
partiality — `delta (AlreadyPaid, ctx) (TimerFired _) = Nothing`.

### Activities = Request/Response via Queue

An activity is an external side effect (HTTP call, file processing,
third-party API). The pattern:

1. FST emits `ActivityRequested activityId payload`
2. Subscription picks up the event, dispatches work via queue
3. Worker executes the activity, publishes result
4. Result arrives as `ActivitySucceeded activityId result` or
   `ActivityFailed activityId error` command to the FST
5. FST handles success/failure transitions

```haskell
data WfCmd
  = ...
  | ActivitySucceeded ActivityId Result
  | ActivityFailed ActivityId Error

data WfEvt
  = ...
  | ActivityRequested ActivityId Payload
  | ActivityResultRecorded ActivityId Result
  | ActivityFailureRecorded ActivityId Error

-- Retry logic: in the FST (explicit, verifiable)
delta (ExecutingStep, ctx) (ActivityFailed aid err)
  | retryCount ctx < 3 = Just ExecutingStep    -- stay, context tracks count
  | otherwise           = Just Failed

rho (ExecutingStep, ctx) (ActivityFailed _ _) =
  ctx { retryCount = retryCount ctx + 1 }

-- Or: retry logic in infrastructure (transparent to FST)
-- The subscription retries N times before delivering ActivityFailed
```

**Trade-off**: Retry logic in the FST is formally verifiable (you can
enumerate all retry paths). Retry logic in infrastructure is simpler
but invisible to analysis. Choose based on whether the retry behavior
is a business concern or an infrastructure concern.

### Signals = Commands (already handled)

A Temporal "signal" is just an external command arriving
asynchronously. The FST's input alphabet already includes these.
Partiality rejects signals that aren't valid in the current state.

```haskell
data WfCmd = ... | UserCancelled | AdminOverride AdminId

delta (AwaitingApproval, ctx) UserCancelled = Just Cancelled
delta (Completed, ctx)        UserCancelled = Nothing  -- too late
```

### Queries = Reconstitute + Read

```haskell
queryWorkflow :: EventStore -> WorkflowId -> IO (WfControl, WfCtx)
queryWorkflow store wfId = do
  events <- readStream store wfId
  pure $ fromMaybe (error "corrupt") $ reconstitute extDecider events
```

No separate query handler needed. The event store is the source of
truth; reconstitute gives you the current state on demand.

For performance-sensitive queries, maintain a read model / projection
updated by a subscription — standard event sourcing pattern.

### Child Workflows = Composition via Queue

```
Parent FST ──ActivityRequested──► Event Store
                                      │
                              Subscription reads
                                      │
                                      ▼
                              Creates child workflow
                              (new stream in event store)
                                      │
                              Child FST runs independently
                                      │
                              Child reaches final state
                                      │
                              Subscription reads child completion
                                      │
                                      ▼
                              Enqueues ChildCompleted command
                              to parent workflow
                                      │
Parent FST ◄──ChildCompleted──────────┘
```

This is transducer composition mediated by the event store and queue.
The parent's output triggers the child; the child's completion feeds
back as the parent's input. No coupling between the FST definitions.

### Cancellation = Command + Compensation

```haskell
data WfCmd = ... | Cancel CancellationReason
data WfEvt = ... | CancellationInitiated | CompensationCompleted

delta (anyActiveState, ctx) (Cancel reason)
  | hasCompensatableWork ctx = Just Compensating
  | otherwise                = Just Cancelled

-- Compensating transitions clean up
delta (Compensating, ctx) (CompensationStepDone stepId) =
  if allCompensated ctx
    then Just Cancelled
    else Just Compensating
```

Compensation logic lives in the FST — it's just more transitions.
The formal operations tell you whether all active states have a path
to a final state through cancellation (soundness under cancellation).

### Versioning = Event Upcasting

Standard event sourcing approach:

1. Events carry a schema version
2. Upcasting transforms old events to new schema during replay
3. New FST definition handles reconstituted state going forward

```haskell
upcast :: Version -> RawEvent -> CurrentEvent
upcast V1 (V1_OrderPlaced oid) = OrderPlaced oid defaultPriority
upcast V2 e = e  -- already current
```

The FST doesn't need special versioning support — event upcasting is
an infrastructure concern handled during reconstitution.

### Continue-As-New = Snapshotting

For workflows with unbounded event histories (e.g., long-running
monitoring), event replay gets expensive. The solution:

1. Periodically snapshot `(s, ctx)` to the event store as a special
   snapshot event
2. Reconstitution starts from the latest snapshot
3. The FST is unaware — this is purely an event store optimization

```haskell
snapshot :: EventStore -> WorkflowId -> (WfControl, WfCtx) -> IO ()
snapshot store wfId state =
  appendEvent store wfId (Snapshot state)

reconstitute' :: EventStore -> WorkflowId -> IO (WfControl, WfCtx)
reconstitute' store wfId = do
  -- Read from latest snapshot forward
  (snap, remaining) <- readFromSnapshot store wfId
  foldlM apply snap remaining
```

---

## 3. What This Gives You That Temporal Doesn't

### Formal Verification

```haskell
-- "Can this workflow deadlock?"
deadlocks multiApproval  -- []

-- "Is every state reachable?"
unreachable multiApproval  -- []

-- "Does the saga's output match what downstream aggregates accept?"
prop_contractValid =
  forAll (genPaths sagaOutput) $ \cmds ->
    accepts aggregateInput cmds
```

Temporal workflows are opaque — you discover deadlocks in production.
FST workflows are analyzable before deployment.

### Composition with Guarantees

Compose two transducers and the composed system inherits properties
from both. Prove that a saga + aggregate pair can't produce invalid
states without running a single test.

### Workflow Equivalence

Refactor a workflow and prove it accepts exactly the same interactions:

```haskell
equivalent oldWorkflow newWorkflow  -- True
```

### Single Formalism

Aggregates, sagas, policies, workflows, process managers — all
transducers, all composable, all analyzable with the same operations.
No impedance mismatch between your domain model and your orchestration
layer.

### Full Audit Trail by Construction

Every state transition produces an event. The event store IS the
complete, immutable audit log. No separate audit infrastructure.

---

## 4. Remaining Gaps

### Dynamic Fan-Out

Temporal can spawn N parallel activities where N is determined at
runtime. The EFSM can model this:

```haskell
data FanOutCtx = FanOutCtx
  { pending   :: Set ActivityId
  , completed :: Map ActivityId Result
  }

delta (FanningOut, ctx) (ActivitySucceeded aid result)
  | Set.size (pending ctx) == 1 = Just AllComplete   -- last one
  | otherwise                    = Just FanningOut    -- still waiting

rho (FanningOut, ctx) (ActivitySucceeded aid result) =
  ctx { pending   = Set.delete aid (pending ctx)
      , completed = Map.insert aid result (completed ctx) }
```

The control state remains simple (`FanningOut` → `AllComplete`). The
context tracks which activities are pending. This works, but the FST
can't verify properties about the fan-out statically since the number
of activities is dynamic.

### Observability Dashboard

Temporal's UI shows running workflows, their states, and history.
With ES + queue you build this as a read model / projection:

```haskell
-- Subscription maintains a queryable view of all active workflows
workflowDashboard :: Subscription WorkflowEvent DashboardView
```

This is additional work but follows standard event sourcing patterns.

### Multi-Language Workers

Temporal supports activity workers in different languages. With this
approach, activities are dispatched via queue — any language that can
consume from the queue can implement workers. The FST itself is
Haskell, but the activities it orchestrates are language-agnostic.

---

## 5. The Execution Loop

Tying it all together — the runtime loop that connects the pure FST
to the infrastructure:

```haskell
-- The core execution step (pure)
step :: ExtTransducer s ctx c e
     -> (s, ctx)
     -> c
     -> Maybe (s, ctx, e)
step t (s, ctx) c = do
  s' <- delta t s ctx c
  e  <- omega t s ctx c
  let ctx' = rho t s ctx c
  pure (s', ctx', e)

-- The runtime loop (effectful, uses ES + queue)
runWorkflow
  :: ExtTransducer s ctx c e
  -> EventStore -> Queue
  -> WorkflowId
  -> IO ()
runWorkflow t store queue wfId = do
  -- 1. Reconstitute current state from event history
  (s, ctx) <- reconstitute store wfId

  -- 2. Receive next command from queue
  cmd <- dequeue queue wfId

  -- 3. Step the pure FST
  case step t (s, ctx) cmd of
    Nothing -> do
      -- Command rejected in current state — dead letter / log
      nack queue cmd

    Just (s', ctx', event) -> do
      -- 4. Persist event to event store (this is the commit point)
      appendEvent store wfId event

      -- 5. Ack the command (processed successfully)
      ack queue cmd

      -- 6. If final state, mark workflow complete
      when (isFinal t s') $
        markComplete store wfId

  -- Subscriptions (separate processes) handle:
  -- - TimerScheduled events → delayed queue messages
  -- - ActivityRequested events → worker dispatch
  -- - Command routing events → enqueue to other workflows
  -- - Notification events → send emails/webhooks
```

The FST is the brain. The event store is the memory. The queue is the
nervous system. Subscriptions are the effectors. No framework, no SDK,
no vendor lock-in — just the primitives you already have.

---

## Summary: Temporal Feature Mapping

| Temporal Feature | FST + ES + Queue Equivalent |
|---|---|
| Workflow definition | `ExtTransducer s ctx c e` |
| Durable execution | Event sourcing (reconstitute on restart) |
| Activity execution | Output event → subscription → queue → worker → result command |
| Activity retry | In FST (explicit states) or in infrastructure (transparent) |
| Timers / sleep | Output event → subscription → delayed queue message → TimerFired command |
| Signals | Commands (input alphabet) |
| Queries | Reconstitute from event store |
| Child workflows | Output event → subscription → new workflow stream |
| Cancellation | Cancel command + compensation transitions |
| Saga / compensation | Failure transitions producing compensating commands |
| Continue-as-new | Event store snapshotting |
| Versioning | Event upcasting during reconstitution |
| Search / visibility | Read model projection from event store |
| **Formal verification** | **Deadlock detection, soundness, path enumeration** |
| **Workflow equivalence** | **Language equality of projections** |
| **Contract verification** | **Output projection ⊆ downstream input projection** |

The last three rows have no Temporal equivalent — they are unique to
the FST approach.
