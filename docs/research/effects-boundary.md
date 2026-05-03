# Effects boundary between pure transducer and runtime

This note pins down the contract between keiki's pure core (the
symbolic-register transducer specified in
`synthesis-c-foundation-b-presentation-with-worked-examples.md`) and the
runtime layer that gives it durability, time, and an outside world. It
specifies exactly what is pure, what is not, what types cross the
boundary in each direction, and what the v1 prototype does and does not
implement.

The reader who finishes this note should be able to:

- Predict, for any proposed function, whether it belongs in `Keiki.Core`
  or `Keiki.Runtime` without consulting the synthesis.
- Write a `Keiki.Runtime` adapter on top of `IO`, `ReaderT IO`,
  `Effectful`, or any other monad without disturbing `Keiki.Core`.
- Implement plan 4 (the prototype) by copying the v1 prototype scope
  paragraph in §11 verbatim.


## Inputs and prerequisites

Read first, in this order:

1. `synthesis-c-foundation-b-presentation-with-worked-examples.md` —
   §4's data discipline notes (UTCTime is a command field;
   `ConfirmationCode` is generated outside the transducer); §5's "How
   the runtime threads the alphabets," "Timer," and "Reconstitution"
   subsections; §6 "Composition."
2. `fst-as-workflow-runtime.md` — the runtime architecture sketch:
   event store, queue, subscriptions, timers, activities, signals,
   queries, child workflows, cancellation, versioning, snapshotting.
3. `orchestration-sagas-choreography-and-feedback-loops-as-transducers.md`
   — the subscription/routing model from a different angle.
4. `future-directions-profunctors-effects-and-composition.md` — names
   `lmapMaybeC` (the routing combinator).

This note refines the runtime sketch in (2) into a concrete boundary;
it does not replace it.

The terms **pure layer**, **runtime layer**, **effects boundary**,
**subscription**, **dispatch**, **timer service**, and **replay** carry
the meanings established in plan 3's "Terms used in this plan" section.


## What the runtime is responsible for

The pure layer (the transducer, its register file, edges, terms,
predicates, `step`, `reconstitute`, `solveOutput`, the analyses) does
exactly one thing: given a state and an input, it computes the next
state and the optional output. It has no `IO`. It does not know what
day it is, where its state came from, where its output goes, what time
zone the user is in, what other transducers exist, or whether it is
running for the first time or being replayed.

Everything else is the runtime's job. Concretely:

- **Event store reads.** Read the prefix of events for a particular
  workflow / aggregate / process-manager instance. Use cases: replay
  on crash, snapshot rebuild, queries.
- **Event store writes.** Append new output events atomically with
  optimistic concurrency control. Use case: persisting the result of
  a successful `step`.
- **Queue dequeue.** Pull the next pending input for an instance.
  Use cases: external commands, foreign-aggregate events routed in
  by subscriptions, timer firings, activity completions.
- **Queue enqueue.** Dispatch a derived command to another aggregate,
  schedule a delayed message, deliver an activity request to a
  worker.
- **Subscription registration.** Wire one stream's events into
  another transducer's input alphabet via a runtime-registered
  filter/route function. The pure layer does not know which
  subscriptions exist.
- **Dispatch.** Read the pure layer's output, decide which side
  effect to perform (HTTP, queue, gRPC, activity worker, log). The
  pure layer cannot perform side effects, so dispatch is not
  optional — it is the whole point of having an outside world.
- **Timer scheduling.** Consume an output event tagged as a timer,
  call `getCurrentTime`, schedule a delayed message on the queue,
  inject the firing back as input at the right time.
- **Snapshot reads/writes.** Optionally accelerate reconstitution by
  storing `(s, RegFile rs)` periodically.
- **Serialization.** JSON / CBOR / Protobuf to and from on-the-wire
  bytes. The pure layer talks only typed Haskell values.
- **Errors.** Schema mismatch, optimistic-concurrency conflict,
  network failure, queue unavailable, deserialization error,
  hidden-input warning escalations, timer service unreachable.
  Handling, retry policy, dead-lettering, and reporting are the
  runtime's call.
- **Retries.** Whether to retry a step (for transient external
  errors) or surface the failure. The pure layer's `step` is total —
  it never throws — so retries only apply to runtime concerns.
- **Observability.** Logs, metrics, traces, audit trails. The pure
  layer emits a value; the runtime decides whether anything is
  observed about that emission.
- **Idempotence and ordering.** Deduplicating queue redeliveries,
  enforcing per-instance ordering, fencing concurrent writers. All
  runtime; all invisible to the transducer.

The pure layer never logs. It never traces. It never retries. It
never sleeps, awaits, or blocks. It is a mathematical function on
typed Haskell values and so are all its analyses.


## Walked Order Fulfillment trace

To make the boundary tangible, walk one happy-path event through the
synthesis's Order Fulfillment process manager (`synthesis §5`), from
the customer's HTTP request through the first dispatched command and
back. Lines that perform `IO` are flagged. The pure layer (the
transducer and `step`) does not appear in any flagged line.

    1. HTTP request arrives at the order intake service.
       [IO] HTTP server reads the request body.

    2. The runtime adapter parses the body into a typed payload.
       [IO] Possibly fails on malformed JSON; the adapter returns 400.
       Pure: SubmitOrderData is constructed once parsing succeeds.

    3. The adapter calls getCurrentTime to compute `deadline = now + 24h`.
       [IO] getCurrentTime is the only place the wall clock is read.
       Pure: SubmitOrderData {..., deadline = stampedDeadline} is now a
       fully populated input.

    4. The runtime constructs the typed input `SubmitOrder data` :: OrderInput.
       Pure: this is a Haskell sum constructor.

    5. The runtime fetches the current state for orderId from the event
       store and reconstitutes (s, regs).
       [IO] readStream :: EventStore -> OrderId -> IO [OrderOutput]
       Pure: reconstitute orderPM events :: Maybe (Vertex, RegFile OrderRegs)

    6. The runtime calls step orderPM (s, regs) (SubmitOrder data).
       Pure: step is a total function on values. Returns
       Just (s', regs', Just OrderAccepted-event) on success, Nothing
       if the command is rejected by the current vertex.

    7. The runtime appends the output event to the order stream.
       [IO] appendEvent :: EventStore -> OrderId -> OrderOutput -> IO ()
       Optimistic concurrency: the runtime carries the expected version.

    8. A subscription on the order stream picks up the new event.
       [IO] The subscription is a separate process / thread / fiber.
       Pure: the subscription's filter routePaymentToOrder is a pure
       function; only the read of the stream is IO.

    9. The dispatcher matches OrderAccepted and routes downstream
       commands. For OrderAccepted, no command is dispatched; for
       PaymentAuthorizationAsked (which the next iteration of step
       emits), the dispatcher forwards a Payment.Authorize command to
       the payment aggregate.
       [IO] sendCommand :: Aggregate -> Command -> IO ()

    10. When the payment aggregate emits PaymentAuthorized later, a
        subscription on the payment stream routes it back to the order
        PM as PaymentAuthorized :: OrderInput.
        [IO] readStream + queue enqueue.
        Pure: the routing function is total.

    11. The runtime fetches the order PM's state, calls step, appends,
        dispatches — return to step 5.

The pure transducer is invoked exactly once per loop iteration, in
step 6. Everything else is runtime. Time enters once, in step 3, in
the adapter — never inside `step`. Randomness, when needed, enters in
the same shape: in the adapter, before `step` is called.


## Survey of comparable approaches

Three local references inform the boundary shape. None is adopted
wholesale; each contributes a specific lesson.

### `effectful` (registered as `effectful/effectful`)

`effectful` represents effects as datatypes (`data MyEffect :: Effect
where ...`) and runs them in an `Eff es` monad parameterized by an
effect row. The library's bottom-most non-trivial effect is `IOE`,
which is the only one that grants raw `IO`. Pure code uses `Eff '[]`
or `runPureEff`. Effects are dispatched statically (`Static`) or
dynamically (`Dynamic`) and can be reinterpreted — a crucial property
for testing.

The lesson keiki takes from `effectful`: **the boundary is a type, not
a convention.** A function in `Keiki.Core` has a Haskell-level pure
signature (no `IOE`, no `m`, no `Eff es`, no `MonadIO`). It is *as
pure as `runPureEff` requires*. A future `Keiki.Runtime` package can
expose its operations as effects (`data EventStore :: Effect`,
`data Queue :: Effect`, `data Clock :: Effect`) so that the runtime
itself is testable with reinterpretation. But that is a runtime
concern; the core does not depend on `effectful`.

keiki does *not* adopt `effectful`'s `Eff` monad in its core. The core
is plain Haskell. The runtime is free to be `Eff es`, `ReaderT env IO`,
`ResourceT IO`, or `IO` — that choice is the runtime author's, and
none of it leaks back into `Keiki.Core`.

### `tan/message-db-hs` (registered)

`message-db-hs` is a Haskell event-sourcing library over PostgreSQL's
message-db extension. Its `MessageDb` effect surface looks like this:

    data MessageDb :: Effect where
      GetStreamMessages :: GetStreamMessagesQuery -> MessageDb m (Vector Message)
      GetLastStreamMessage :: Stream -> MessageDb m (Maybe Message)
      GetCategoryMessages :: GetCategoryMessagesQuery -> MessageDb m (Vector Message)
      WriteStreamMessage :: (Error WrongExpectedVersion :> es) => NewMessage -> MessageDb (Eff es) MessagePosition
      WriteStreamMessages :: ... -> MessageDb (Eff es) (t MessagePosition)

The boundary is drawn at the database. Above the line: business logic
with deciders, views, evolve functions. Below the line: SQL,
optimistic concurrency, JSON serialization. The `EventStore.Effectful`
module pages through 1000-message batches transparently and folds
events with a decider's `evolve` to recover state — exactly what the
keiki runtime would do, calling `reconstitute` instead of an
ad-hoc `evolve`.

The lessons: (a) the runtime owns paging, batching, and incremental
fold; (b) the `Decider'` / `View'` types — pure functions over
events — are the same shape as keiki's `reconstitute`; (c) the runtime
needs a typed error channel for write conflicts (`WrongExpectedVersion`).

keiki's pure `reconstitute` is the analogue of message-db's
`evolve`-fold; the runtime's eventual `EventStore` port is the
analogue of `MessageDb`. The two libraries could plausibly share an
adapter someday: a keiki transducer's `[output]` is a stream of
JSON-serializable events, and message-db is one place to put them.
keiki itself does not depend on message-db, and the boundary in this
note keeps it that way.

### `crem` (no local registry entry; reasoning from published documentation)

`crem` ("composable representable executable machines", Marco Perone)
is a Haskell library for composable state machines, with a strong
design line: machines are pure values; their interpretation in `IO`
is a separate `runMachine`. A `StateMachineT` parameterizes over an
arbitrary monad, so the same state machine definition runs `Identity`
(for testing) or `IO` (for production).

Two design notes from `crem` are directly relevant:

- **Effectful interpretation by lifting, not embedding.** `crem`
  defines machines without an effect type, then lifts them to a
  monadic interpretation. keiki does the same: the core defines a
  transducer without a monad, then a future `runTransducer` (in the
  runtime layer) lifts it to whatever monad the application chose.
  No effect parameter on `SymTransducer`.

- **Composition is at the value level, not the runtime level.**
  `crem`'s `Sequential`, `Feedback`, etc. are operations on state
  machine values. keiki's composition (per synthesis §6) is the
  same: `compose`, `lmapMaybeC`, etc. are operations on transducer
  values — analyzed, not run. The runtime composes by routing
  events through the queue, not by structurally combining
  transducers.

keiki diverges from `crem` on one point: `crem`'s `Feedback`
combinator runs aggregate-policy loops in-process. keiki delegates
loops to the runtime via subscriptions. This is the right call for
durable execution: any in-process loop is hostile to crash recovery,
because the crash drops the in-flight loop. Routing through the
queue makes every iteration a separately persisted event.


## Pure-layer entry points

The pure layer exports four kinds of function: stepping, replay,
analyses, and constructors. Constructors are AST-shaped — they are
the DSL surface plan 1 specifies — and they are out of scope for this
note. The other three are pinned here.

### `step`

`step` is the canonical primary export of `Keiki.Core`. Given a
transducer, a current state, and an input, it returns the next state,
the updated register file, and the optional output:

    step
      :: SymTransducer phi rs s ci co
      -> (s, RegFile rs)
      -> ci
      -> Maybe (s, RegFile rs, Maybe co)

Semantics: `step` finds the unique outgoing edge whose guard models
`(regs, ci)`, runs the edge's `Update` to produce `regs'`, evaluates
the edge's `output` term (if any) to produce `co`, and returns
`(target edge, regs', maybeCo)`. If zero or more than one edge
matches, `step` returns `Nothing`. If exactly one edge matches but
its `output` is `Nothing` (the ε case), the returned `Maybe co` is
`Nothing` — the input was processed silently.

`step` is the runtime's only call site for "advance the transducer by
one input." Plan 4's smoke test calls `step` directly with hardcoded
inputs.

`delta` and `omega` (synthesis §2) remain available as analysis-only
projections but are not the primary export. Carving them as separate
calls would risk the runtime calling them inconsistently — e.g.,
`delta` accepting an input that `omega` rejects — which `step` makes
impossible by construction. Following synthesis §2's promise that
"familiar functions are projections, not fields," `delta` and `omega`
project from `step` by ignoring or extracting the appropriate
components.

### `reconstitute`

`reconstitute` is what plan 4 implements. Given a transducer and a
list of output events (the durable record of what the transducer has
emitted), it recovers `(state, regs)`:

    reconstitute
      :: SymTransducer phi rs s ci co
      -> [co]
      -> Maybe (s, RegFile rs)

Semantics: starting from `(initial t, initialRegs t)`, fold each event
through the inverse step. For each event, walk the outgoing edges of
the current vertex, find the unique edge whose `output` term is
invertible against the event, recover the implied input (via
`solveOutput`), and run the edge's update to advance `(s, regs)`.

If `solveOutput` cannot determine a unique input — because the event
is missing fields the update or guard reads, or because two edges
produce the same event constructor — `reconstitute` returns `Nothing`.
This is the synthesis's hidden-input bug surfacing at runtime; the
build-time check (next entry) catches the same condition statically.

`reconstitute` does not consume commands; it consumes outputs. This
is intentional: the event store is a record of what the transducer
*emitted*, not what it *received*. Replay reconstructs received
inputs by inverting outputs.

### `checkHiddenInputs`

A static analysis that scans every edge in the transducer and reports
edges whose `update` or `guard` reads input fields not present in the
edge's `output`. Returns a list of warnings (not a `Bool`) so that
multiple problems are reported in one pass:

    checkHiddenInputs
      :: SymTransducer phi rs s ci co
      -> [HiddenInputWarning]

The shape of `HiddenInputWarning` (whether it carries vertex name,
field name, both, or richer evidence) is a DSL-shape question owned
by plan 1. This note commits only to the type signature and the
contract: an empty list means `reconstitute` is total over
well-formed event logs (modulo runtime corruption); a non-empty list
identifies edges that may make `reconstitute` return `Nothing` even
on log fragments produced by the transducer itself.

The check's precision depends on how structurally `OutTerm` is
encoded — see IP-2 in the master plan.

### `isSingleValued`

Best-effort single-valuedness check for v1; SBV-backed precise check
for v2:

    -- v2: lives in Keiki.Symbolic; BoolAlg-polymorphic.
    isSingleValuedSym
      :: (BoolAlg phi (RegFile rs, ci), Bounded s, Enum s)
      => SymTransducer phi rs s ci co
      -> Bool

Synthesis §7 deferred a general single-valuedness decision procedure to
v2 (SBV-backed); v2 has now landed. With the v2 `SymPred` `BoolAlg`
instance, `isBot (g₁ \`conj\` g₂)` is decided by z3, so the per-vertex
pairwise check is precise. With the v1 `HsPred` instance, the answer
is the v1 syntactic conservative approximation (false positives
acceptable; false negatives the user's contract). Both call sites use
the same `isSingleValuedSym` function — the `BoolAlg` parameter
selects v1 or v2 behavior.

For the User Registration aggregate, `isSingleValuedSym (withSymPred
userReg) == True` is asserted in
`test/Keiki/Examples/UserRegistrationSymbolicSpec.hs`; the proof goes
through the constructor-mutex translation of `PInCtor`. See
`docs/research/sbv-boolalg-design.md` for the full v2 design record
and `docs/plans/6-sbv-backed-boolalg-instance-for-symbolic-emptiness.md`
for the implementation plan.

Plan 4 implemented `step`, `reconstitute`, and `checkHiddenInputs`
without exercising `isSingleValued`; EP-2 of MasterPlan 2 added
`isSingleValuedSym` and the symbolic User Registration spec.


## Runtime-side ports

These are *names* of types and functions the runtime exposes. The
pure layer does not import them. Plan 4 does not implement them. They
exist in this note so future runtime plans have something to point
at.

    -- Runtime-defined; produces ci values from somewhere.
    -- Concrete shape might be `Stream IO ci`, `IO ci`, `Eff es ci`,
    -- or a callback-based interface. Owner: future Keiki.Runtime.
    data InputSource ci

    -- Runtime-defined; consumes co values somewhere.
    -- Likely involves an event-store append plus a notification.
    data OutputSink co

    -- The runtime loop. Sits in some monad m chosen by the runtime
    -- author (IO, Eff es, ResourceT IO, ...). Returns Void because
    -- the loop runs forever for a long-lived transducer; for one-shot
    -- replay or query, a different entry point is appropriate.
    runTransducer
      :: SymTransducer phi rs s ci co
      -> InputSource ci
      -> OutputSink co
      -> IO Void

A skeleton implementation, for orientation only:

    runTransducer t source sink = forever $ do
      ci         <- pull source
      (s, regs)  <- restoreState sink t        -- via reconstitute on
                                                -- the persisted [co]
      case step t (s, regs) ci of
        Nothing                       -> nack source ci
        Just (_, _, Nothing)          -> ack  source ci
        Just (_, _, Just co)          -> do
          push sink co                          -- atomic with ack
          ack  source ci

This is `fst-as-workflow-runtime.md` §5's loop, refined to use the
pure layer's `step` and `reconstitute`. Every line involving
`source`, `sink`, or "restore" is `IO`. The line involving `step` is
not.


## Time discipline

**Rule.** All values that depend on the wall clock are carried in the
input alphabet; the adapter (an unspecified runtime component) stamps
them by calling `getCurrentTime` before constructing the input.

The transducer never calls `getCurrentTime`. The pure layer has no
notion of "now." Time entering the system is an alphabet question,
not a transition question.

This discipline is already settled in synthesis §4's data discipline
notes; this note re-states it as a normative rule for the prototype
and elaborates on the implementation shape.

### Worked example: `RegistrationStarted.at`

The synthesis User Registration aggregate has this command:

    data StartRegistrationData = StartRegistrationData
      { email       :: Email
      , confirmCode :: ConfirmationCode
      , at          :: UTCTime
      } deriving (Eq, Show, Generic)

The `at` field is `UTCTime`. The transducer's edge in
`PotentialCustomer` reads `d.at` from the command and writes it into
register `#registeredAt` and into the output event
`RegistrationStartedData.at`.

End-to-end:

    1. HTTP request arrives at /register with body
       { email, confirmCode (or none) }.

    2. The adapter parses the body. If `confirmCode` is missing, the
       adapter generates one (see Randomness discipline below).

    3. The adapter calls getCurrentTime :: IO UTCTime.   ← only IO line

    4. The adapter constructs the typed command:
         StartRegistration (StartRegistrationData
           { email, confirmCode = stampedCode, at = stampedNow })

    5. The runtime calls step userReg (s, regs) (StartRegistration ...)
       in pure code. The transducer reads d.at and stamps it into
       #registeredAt and into the output event.

    6. The runtime persists the output event. The persisted event
       carries the timestamp stamped in step 3.

On replay, `reconstitute` reads the persisted `at` from the event,
recovers the original command (including its `at`), and re-runs the
update with the same value. The replayed register file matches the
original. There is no clock involvement during replay.

Three implications:

- **Timestamps are part of the command's identity.** Two adapters
  stamping at slightly different times produce two distinct
  commands and two distinct events, even if the user submitted "the
  same" request twice.
- **Clock skew is an adapter concern, not a transducer concern.**
  If a distributed adapter cluster needs monotonic timestamps, that
  is solved at the adapter (e.g., Lamport clocks, hybrid logical
  clocks) without any change to the transducer.
- **Tests are deterministic.** Plan 4's smoke test passes a
  hardcoded `UTCTime` in every fixture; no `IO` clock is needed,
  no time-mocking library is needed, no `--allow-different-user` /
  `--freeze-time` machinery is needed. The fixtures *are* the
  clock.


## Randomness discipline

**Rule.** All values that depend on randomness or fresh-ID generation
are carried in the input alphabet; the adapter stamps them by calling
the appropriate `IO` generator before constructing the input.

Same shape as time. The transducer never calls `getStdGen`,
`randomIO`, `nextUUID`, `genConfirmationCode`, or any other source of
nondeterminism.

### Worked example: `freshCode` becomes a payload field

Synthesis §4's User Registration uses pseudosyntax `freshCode` inside
the `ResendConfirmation` edge to denote "rotate to a new code":

    Edge { guard  = matchCmd \(ResendConfirmation _) -> True
         , update = Combine (Set #confirmCode freshCode)
                            (Set #registeredAt (\(ResendConfirmation d) -> d.at))
         , ...
         }

In a fully pure formalism, `freshCode` cannot be a runtime-generated
value: the transducer would have to call `IO`. The fix is to add the
fresh code as a field of `ResendConfirmationData`, pre-populated by
the adapter:

    data ResendConfirmationData = ResendConfirmationData
      { code :: ConfirmationCode
      , at   :: UTCTime
      } deriving (Eq, Show, Generic)

End-to-end:

    1. HTTP request arrives at /resend-confirmation for user X.

    2. The adapter calls a fresh-code generator:
         freshCode :: IO ConfirmationCode    ← only IO for randomness
       and getCurrentTime :: IO UTCTime      ← only IO for time.

    3. The adapter constructs the typed command:
         ResendConfirmation (ResendConfirmationData
           { code = stampedCode, at = stampedNow })

    4. The runtime calls step userReg (s, regs) (ResendConfirmation ...).
       The edge's update reads d.code and writes it into #confirmCode.
       The edge's output (ConfirmationResent) carries the new code so
       that solveOutput can recover it on replay.

The synthesis's pseudosyntax `Set #confirmCode freshCode` becomes
`Set #confirmCode (\(ResendConfirmation d) -> d.code)`. The
transducer is now pure; the adapter is now responsible for
generating fresh codes.

Same three implications as time: the code is part of the command's
identity; randomness skew (e.g., the adapter using a weak RNG) is an
adapter concern; tests are deterministic by hardcoding codes.

### What about register-derived fresh values?

The synthesis hints at one alternative: derive the next code
deterministically from registers (e.g.,
`nextCode = hash (oldCode, registeredAt)`). This keeps the entire
update pure, including the fresh-code computation. This is a DSL
choice (plan 1's territory) — does the DSL provide enough term-level
machinery to express a hash? — and is not pinned here. Either
discipline (adapter-generated or register-derived) keeps the
transducer pure; the boundary note allows both.


## Subscriptions and dispatch

Subscriptions and dispatch are runtime concepts. The pure layer
emits typed Haskell values (one per `step`); the runtime decides
where they go and what arrives next. The library does not prescribe
how subscriptions are stored, how dispatchers are wired, how
delivery is acknowledged, or how at-most-once / at-least-once /
exactly-once semantics are guaranteed.

### Subscription

A subscription is a routing function from one stream's events into
another transducer's input alphabet:

    type Subscription a b = a -> Maybe b

This is the synthesis's `lmapMaybeC` shape. Given a function from
"some upstream event type" to "this transducer's input alphabet (or
`Nothing` if the event is irrelevant)," the runtime registers it
and routes accordingly.

Concrete signatures, drawing from
`future-directions-profunctors-effects-and-composition.md` §1:

    -- Build a routed input source from a wider one.
    -- The runtime composes these to feed multiple upstream streams
    -- into a single transducer's input alphabet.
    lmapMaybeC :: (a -> Maybe b) -> InputSource a -> InputSource b

    -- A specific instance: routing payment events into the order PM.
    routePaymentToOrder :: PaymentEvent -> Maybe OrderInput

The pure layer does not see `InputSource` or `lmapMaybeC` as runtime
operations — those live in `Keiki.Runtime`. What the pure layer
does see is the typed sum constructor `OrderInput`. Whether a
particular `OrderInput` came from the customer's HTTP request, from
the payment subscription, from the timer service, or from a
manually replayed dead-letter is invisible to the transducer.

### Dispatch

A dispatch is the dual of a subscription: from one transducer's
output event, perform a side effect (typically: send a command to
another aggregate, schedule a timer, request an activity):

    type Dispatch a m = a -> m ()

Concrete:

    dispatchPaymentRequests :: OrderOutput -> SomeRuntimeMonad ()

Where `SomeRuntimeMonad` is whatever the runtime author picks
(`IO`, `Eff es`, `ReaderT env IO`). The library does not prescribe
this monad. It does prescribe that dispatch is impure (side effects)
and that the pure layer never sees it: the pure layer's `step`
returns the typed output, and the runtime — *separately* — passes
that output through the registered dispatchers.

The synthesis §5 example:

    dispatchPaymentRequests :: OrderOutput -> IO ()
    dispatchPaymentRequests = \case
      PaymentAuthorizationAsked d -> sendCommand paymentAggregate ...
      PaymentRefundAsked d        -> sendCommand paymentAggregate ...
      _                           -> pure ()

is a runtime artifact. Plan 4 does not implement it.


## Timer model

A timer is two alphabet members and a runtime service. The transducer
emits a `*Scheduled` output (e.g., `PaymentTimerScheduled`); the
timer service consumes it, calls `getCurrentTime` to compute "fire
at," schedules a delayed message, and at the appointed time pushes a
`*Expired` input (e.g., `PaymentDeadlineExpired`) back onto the
transducer's queue.

Inside the transducer, the timer is just two more alphabet entries.
There is no notion of "wait" or "sleep." There is no notion of
"cancel a timer" — if the transducer has moved past the relevant
vertex by the time the firing input arrives, the firing has no
matching edge in the current vertex and `step` returns `Nothing`,
which the runtime ack-and-discards. Synthesis §5 makes this point
explicitly: partiality handles cancellation; no special machinery
needed.

### Worked example: `PaymentTimerScheduled` → `PaymentDeadlineExpired`

From synthesis §5:

    1. SubmitOrder edge in <initial> emits both OrderAccepted and,
       on a follow-up edge, PaymentTimerScheduled with deadline = at + 24h.
       (The 24h offset is computed at the adapter, before constructing
       the command; the transducer never adds durations to clocks.)

    2. The timer service is a subscription on the order stream that
       matches PaymentTimerScheduled. On match:
         [IO] timerService :: PaymentTimerScheduled -> IO ()
         [IO] now        <- getCurrentTime
         [IO] enqueueAt    queue (deadline) (PaymentDeadlineExpired)

    3. At time `deadline`, the queue delivers PaymentDeadlineExpired
       as an input to the order PM.
         [IO] dequeue      queue
         Pure: step orderPM (s, regs) PaymentDeadlineExpired
         If the PM is in AwaitingPayment, the timer-expired edge
         transitions to Cancelled.
         If the PM has moved to ReservingInventory or beyond, the
         input has no matching edge; step returns Nothing; the
         runtime acks-and-discards.

The timer service is one named subscription/dispatch combo. Its
type, recapping:

    timerSchedule :: TimerScheduledEvent -> IO ScheduledTimerHandle
    -- where ScheduledTimerHandle is the runtime's bookkeeping; the
    -- pure layer never sees it.

The pure layer's contribution: define `*Scheduled` as one output
event constructor, `*Expired` as one input event constructor, and
edges that emit/consume them. That is all.


## Module layout

Two modules at minimum, named here as a forward-looking aid for plan
4 and any future runtime plan:

    Keiki.Core      -- pure types and projections; what plan 4 implements
    Keiki.Runtime   -- IO-wired event store, queue, subscriptions, timer
                       (deferred to a future plan)

`Keiki.Core` exports:

- The types: `SymTransducer`, `Edge`, `Term`, `OutTerm`, `Update`,
  `RegFile`, `Index`, `BoolAlg phi`, and the helpers needed to
  construct them. (Exact constructors are plan 1's territory.)
- The functions: `step`, `reconstitute`, `delta`, `omega`,
  `solveOutput`, `evalTerm`, `evalOut`, `runUpdate`, `models`,
  `checkHiddenInputs`, `isSingleValued`.
- No `IO` import. No `MonadIO`. No `Eff`. No effect type variable
  on any function or type. A reader who tries to mentally compile
  `Keiki.Core` should find that it works with the ghc flag
  `-XSafe` (or its modern equivalent), modulo the language
  extensions for the typed register file.

`Keiki.Runtime` (deferred) exports:

- The types: `InputSource`, `OutputSink`, `Subscription`,
  `Dispatch`, `EventStore`, `Queue`, `TimerService`, etc.
- The functions: `runTransducer`, the wiring API for registering
  subscriptions and dispatches, the adapter constructors, the
  serialization plumbing.
- This module imports `IO` (or `Eff` or `IOE`, depending on the
  runtime author's choice). It depends on `Keiki.Core` but not the
  reverse.

Optionally, for the smoke test:

    Jitsurei.UserRegistration

Plan 4's deliverable. Imports only `Keiki.Core`. Defines
`UserCmd`, `UserEvent`, `UserRegRegs`, `userReg`. Used by the test
suite.

This module layout is a proposal, not a freeze; if plan 4 finds
during implementation that splitting `Keiki.Core` into
`Keiki.Core.Types` and `Keiki.Core.Step` reads more clearly, that
is fine. The constraint is the boundary, not the file count: no
`IO` ever enters `Keiki.Core`.


## Prototype scope (v1)

The v1 prototype implements only `Keiki.Core`. It provides `step`
and `reconstitute`. It does NOT implement `runTransducer`,
`InputSource`, `OutputSink`, `Subscription`, `Dispatch`, or any
timer code. The smoke test calls `step` and `reconstitute` directly
with hardcoded inputs and a hardcoded `[Output]` event log.

That paragraph is intended to be copy-pasted verbatim into plan 4's
scope. Beyond what it says, three implications worth highlighting:

- **There is no `Keiki.Runtime` package in the v1 cabal file.**
  Adding one — even an empty one — would risk a contributor
  putting `IO` in it before the runtime design is ready.
- **There is no event store in v1.** The "log" is a Haskell list
  literal `[UserEvent]` in the test suite. Plan 4's
  `reconstitute userReg fixtureLog == Just (Deleted, expectedRegs)`
  is the entire integration test.
- **There is no time mocking, no random mocking.** The test
  fixtures hardcode `UTCTime` values and `ConfirmationCode` values.
  This is a feature: the prototype validates that the time and
  randomness disciplines work, by construction, because the test
  suite literally cannot pull a clock or RNG.


## Cross-check

A reader has finished this note. Can they:

- ☑ Write a Haskell module with `module Keiki.Core (...)` that
  imports nothing from `IO`, exports `step` and `reconstitute` with
  the signatures in §5, and compiles? Yes — none of the §5
  signatures involves `IO`.
- ☑ Predict whether `getCurrentTime` belongs in `Keiki.Core`?
  No, it belongs in the adapter. (See §6.)
- ☑ Predict whether `freshCode :: IO ConfirmationCode` belongs in
  `Keiki.Core`? No, it belongs in the adapter. (See §7.)
- ☑ Predict whether `routePaymentToOrder :: PaymentEvent -> Maybe
  OrderInput` belongs in `Keiki.Core`? It is a pure function, but
  it talks about a transducer that does not exist in `Keiki.Core`
  (the order PM and the payment aggregate are separate). It
  belongs in `Keiki.Runtime` or the application layer that wires
  the two together. (See §9.)
- ☑ Predict whether `appendEvent :: EventStore -> orderId -> e ->
  IO ()` belongs in `Keiki.Core`? No — `IO` and `EventStore` are
  both runtime. (See §3 and §5.)
- ☑ Implement the v1 prototype in plan 4 by copying §11's scope
  paragraph and the §5 signatures? Yes.

If any answer is "I'm not sure," this note has failed and needs
extension.
