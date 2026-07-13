# Multi-event commands

When one command produces two or more events from a single transition
— the canonical example is `StartRegistration → [RegistrationStarted,
ConfirmationEmailSent]` — keiki encodes it as a **multi-event edge**:
one edge with `output :: [OutTerm rs ci co]` of length ≥ 2.

This is keiki's main *generalised sequential machine* (GSM) feature.
The formal background is in
[`docs/foundations/03-finite-automata-and-transducers.md`](../foundations/03-finite-automata-and-transducers.md)
and the implementation rationale is in
[`docs/research/gsm-widening-design.md`](../research/gsm-widening-design.md).
This guide is the authoring how-to.

## The shape

In the builder DSL: multiple `emit` calls inside one `onCmd` body.

```haskell
B.from PotentialCustomer do
  B.onCmd inCtorStart $ \d -> B.do
    B.slot @"email"        .= d.email
    B.slot @"confirmCode"  .= d.confirmCode
    B.slot @"registeredAt" .= d.at
    B.emit wireRegistrationStarted RegistrationStartedTermFields
      { email       = d.email
      , confirmCode = d.confirmCode
      , at          = d.at
      }
    B.emit wireConfirmationEmailSent
      ConfirmationEmailSentTermFields { email = d.email }
    B.goto RequiresConfirmation
```

One transition (`PotentialCustomer → RequiresConfirmation`) emits two
events in declaration order. No intermediate vertex, no synthetic
internal command.

In the AST surface: `output` is a list literal.

```haskell
Edge
  { guard  = isStart
  , update = ...
  , output =
      [ pack inCtorStart wireRegistrationStarted (...)
      , pack inCtorStart wireConfirmationEmailSent (OFCons (inpStart #email) OFNil)
      ]
  , target = RequiresConfirmation
  }
```

`output = []` is the ε-edge (no events emitted; only a vertex
transition + register update). `output = [o]` is a letter edge (one
event). `output = [o1, …, oN]` is a multi-event edge.

## The single-snapshot rule

All `emit` calls in one body evaluate against the **same pre-
transition `(regs, ci)` snapshot**. The register update applies
*once* at the edge level and is only visible to *subsequent*
transitions — not to later emits in the same body.

The practical consequence: in a multi-event body, read fields you
need from the input projection (`d.field`), not from registers
(`#slot`) — even if a register write earlier in the same body would
appear to set the slot you want to read.

```haskell
B.onCmd inCtorStart $ \d -> B.do
  B.slot @"email" .= d.email
  B.emit wireRegistrationStarted (...)
  B.emit wireConfirmationEmailSent
    ConfirmationEmailSentTermFields { email = d.email }   -- OK
  -- not:                          { email = #email }     -- reads the PRE-update value
  B.goto RequiresConfirmation
```

This is GSM-faithful: a classical GSM's output function `λ : Q × Σ →
Δ*` produces a fixed word from `(state, input)`. The output cannot
depend on partial-update intermediate state because there is no such
intermediate state in the formalism — the update is atomic with the
transition.

If you only ever have a single `emit` in a body, this rule is
invisible: reading `#slot` works fine because no register write of
the same edge has executed.

## When **not** to use multi-emit

**Branching commands.** A command that emits a *different* number of
events (or different events) depending on the input value is not a
multi-event command — it's branching. Express it as multiple edges
with disjoint guards, one per branch.

```haskell
-- Branching: not multi-event
B.from UnderReview do
  B.onCmd inCtorContinue $ \_ -> B.do
    B.requireGuard approvalGuard
    B.emit wireApplicationApproved (...)
    B.goto Approved

  B.onCmd inCtorContinue $ \_ -> B.do
    B.requireGuard (pnot approvalGuard)
    B.emit wireApplicationDeclined (...)
    B.goto Declined
```

The widened `Edge.output` is a *static* list; it does not admit a
runtime-conditional shape. This is by design — the static shape is
what makes `checkHiddenInputs` decidable per-edge and what keeps
`solveOutput` mechanical.

`Jitsurei.LoanApplication`'s `CollectingDocuments → UnderReview`
chain plus `UnderReview → Approved | Declined` is the canonical
example of branching expressed as separate letter edges. See the
[LoanApplication tutorial §7](loan-application-tutorial.md).

**Genuinely stateful intermediate vertices.** A vertex that exists
for *modelling* reasons — for example, a `UnderReview` state where a
human reviewer can take days to act — is not multi-event scaffolding.
Keep it as a first-class vertex. Multi-event collapse is only for
intermediate vertices that exist solely as synthesis artefacts for a
multi-event command.

## Forward direction: `stepEither` returns the full list

```haskell
> stepEither userReg (PotentialCustomer, emptyRegs)
>   (StartRegistration (StartRegistrationData "alice@x" "Z9F4" t0))
Right
  ( RequiresConfirmation
  , updatedRegs
  , [ RegistrationStarted   (RegistrationStartedData "alice@x" "Z9F4" t0)
    , ConfirmationEmailSent (ConfirmationEmailSentData "alice@x")
    ]
  )
```

Length matches the edge's `output` list. There is no façade or
configuration step in between.

## Replay: two regimes

Replay has two flavours depending on whether the runtime preserves
command boundaries.

### Chunk replay (command boundaries preserved)

If the runtime knows which events belong to which command (an event
store with command-id tags, transactional batches, deterministic test
fixtures), it can replay one command's events atomically.

```haskell
applyEvents
  :: (BoolAlg phi (RegFile rs, ci), Eq co)
  => SymTransducer phi rs s ci co
  -> (s, RegFile rs) -> [co]
  -> Maybe (s, RegFile rs)
```

Pass the full chunk; get back the unwrapped settled state. A chunk
that ends mid-flight (the queue is non-empty at the chunk's end)
returns `Nothing`.

For new runtime code prefer `applyEventsEither`. It has the same success
value but returns `ReplayFailure` with the exact event index and
`ReplayLogTruncated pending` (or the exact event-step failure) on the
`Left`.

### Streaming replay (no command boundaries)

If the runtime sees one event at a time without knowing which command
each came from, the mid-chain state during a length-N edge replay
must be expressible. The `InFlight s co` wrapper does this.

```haskell
data InFlight s co
  = Settled  !s
  | InFlight !s ![co]   -- target vertex + tail of expected events
  deriving (Eq, Show)

applyEventStreaming
  :: (BoolAlg phi (RegFile rs, ci), Eq co)
  => SymTransducer phi rs s ci co
  -> InFlight s co -> RegFile rs -> co
  -> Maybe (InFlight s co, RegFile rs)
```

Start from `Settled initialVertex`. Each observed event advances
through `InFlight` for length-N edges and back to `Settled` when the
queue empties. Prefer `applyEventStreamingEither` when handling one
event and `replayEvents` when folding a page or stream: both retain the
`InFlight` state and return structured failures instead of `Nothing`.

For most application code, strict chunk replay (`applyEventsEither` /
`reconstituteEither`) is the right tool — the runtime adapter knows the
command boundary because it knows which command it just dispatched.
Streaming replay is for runtimes that consume an opaque event log
event-by-event.

## Composition

`Keiki.Composition.compose` is closed under multi-event edges via
library-side chain expansion: when T1's edge has a length-N output,
the composite threads T2's state through each mid-symbol and emits
T2's concatenated outputs. The composite's `Vertex` type is unchanged;
no synthetic intermediate vertices leak.

The cartesian product over T2-edge choices per intermediate mid-
symbol produces multiple composite edges; substituted guards
(`substPred (PInCtor X) Y ≡ PBot` for ctor mismatches) ensure only
the live paths fire. The `isSingleValuedSym` symbolic analysis still
certifies determinism over the composite as a whole.

## Diagrams

`Keiki.Render.Mermaid` formats length-N edges with a length-based
switchover:

| Length | Format |
|---|---|
| 0 (ε-edge) | `cmd / ε` |
| 1 (letter) | `cmd / e1` |
| 2 | `cmd / e1; e2` |
| 3+ | `cmd / e1<br/>e2<br/>e3<br/>…` (Mermaid multi-line) |

The User Registration diagram in
[`diagrams/user-registration.md`](diagrams/user-registration.md)
shows the length-2 case for `StartRegistration`.

## Known caveats

- **State-changing ε-edges are not persistable.** `stepEither` advances
  them correctly, but an event log contains no evidence of the change.
  `validateTransducer defaultValidationOptions` reports
  `StateChangingEpsilon`; emit a domain event before mounting the model
  on a durable event stream.
- **Composition produces dead edges.** A length-N first-edge against a
  K-edge target produces K^N composite edges. Most have unsatisfiable
  substituted guards and never fire at `omega`/`delta`/`step` time,
  but they're structurally present in `edgesOut` and the diagram.
  Future cleanup could prune them via `isBot`; today they're noise.
- **Conditional emission stays as multiple edges.** Per the design
  decision recorded in
  [EP-19's plan](../plans/19-multi-event-commands-via-edge-output-widening-gsm-expansion.md),
  the widened `Edge.output` is a static list. Runtime-conditional
  output shape is expressed as multiple disjoint-guarded edges.
