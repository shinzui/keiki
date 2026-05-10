# Composition

How to combine two transducers with the `Keiki.Composition`
combinators. Three are exported today:

- **`compose`** — sequential composition (`t1`'s output feeds
  `t2`'s input).
- **`alternative`** — disjoint-input dispatch over `Either ci1 ci2`
  (sibling aggregates evolving independently).
- **`feedback1`** — single-step aggregate ↔ stateless-policy
  cascade (one round of reaction per external command).

This guide assumes you've read the main `user-guide.md` and have at
least one working aggregate. For the formal semantics, the
substitution algorithm, and the proof sketches see
`docs/research/composition-combinators-design.md`.

---

## 0. Choosing a combinator

A quick pick-list for event-sourced systems.

| If your shape is… | Reach for | Concrete example |
|---|---|---|
| Stage A's events drive stage B as a pipeline | `compose` | An alerting source emits `EmailCmd`s that the email-delivery aggregate consumes (the canonical `AlertSource ⨾ EmailDelivery` fixture); a fraud detector emits `FreezeAccount` commands that the accounts aggregate consumes |
| Two sibling aggregates sharing one runtime channel, evolving independently | `alternative` | One service hosts both `Orders` and `Customers` bounded contexts behind a single HTTP API and command queue; a multi-tenant control plane manages both `Workspace` and `ApiKey` aggregates |
| One round of policy reaction, event → follow-up command → second event, observed atomically | `feedback1` | An order placement that auto-confirms via a stateless confirm-policy (`PlaceOrder → OrderConfirmed` atomically); a form submission that runs a stateless validator before emitting `FormValidated` |
| Many feedback rounds | nested `feedback1`s | A multi-step admission workflow where each round is a distinct policy reaction (capped statically by the nesting depth) |
| Long-running orchestrator with its own state (saga / process manager) | hand-roll the saga as a transducer, then `compose`/`alternative` it with the participating aggregates | A booking saga that holds `(flight, hotel, car)` reservations and emits compensating commands on failure — the saga has its own register file and vertices |
| Strict tuple input (`(a, c) → (b, d)`) or unbounded iteration | not shipped today | Re-deferred in MP-8; rationale in `docs/research/composition-combinators-design.md` under "Combinators beyond `compose`" |
| Reshape one transducer's input or output alphabet (rename, wrap in a newtype, route a slice from a sum, upcast events to a new schema version) | `Keiki.Profunctor`'s `lmapCi` / `rmapCo` / `dimapTransducer` / `lmapMaybeCi` | These rewrite a single transducer's edges; they are not combinators between two transducers. See `profunctor.md` for the full guide and the variance caveat (rewritten transducers are forward-only — `solveOutput`/replay is lossy). |

The three shipped combinators all preserve keiki's three core
guarantees (`solveOutput`, `checkHiddenInputs`,
`isSingleValuedSym`). Each of the sections below names the
guarantees it inherits and the limitations it carries.

---

## 1. `compose` — sequential composition

```haskell
compose
  :: ( WeakenR rs1
     , Disjoint (Names rs1) (Names rs2)
     )
  => SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 mid
  -> SymTransducer (HsPred rs2 mid) rs2 s2 mid co
  -> SymTransducer (HsPred (Append rs1 rs2) ci1)
                   (Append rs1 rs2)
                   (Composite s1 s2)
                   ci1
                   co
```

Read the type left to right. `compose t1 t2` builds a transducer
whose:

- **input alphabet** is `t1`'s input (`ci1`),
- **output alphabet** is `t2`'s output (`co`),
- **mid alphabet** (`mid`) is shared: `t1`'s output equals `t2`'s
  input,
- **vertex** is `Composite s1 s2` (a strict pair newtype),
- **register file** is `Append rs1 rs2` (the slot lists
  concatenated).

The composite preserves keiki's three core guarantees:

1. **Mechanical inversion.** `solveOutput` on the composite walks
   `t2`'s wire form back through `t1`'s structural reads, recovering
   `ci1`.
2. **Hidden-input detection.** `checkHiddenInputs` surfaces fields
   that are transitively hidden — a `ci1` field `t1` keeps in `mid`
   but `t2` drops on the wire is flagged at the composite level.
3. **Symbolic single-valuedness.** The composite is single-valued
   when `t1` and `t2` are individually single-valued; substitution
   is a syntactic rewrite that preserves unsatisfiability.

---

## 2. The two preconditions

### 2.1 Disjoint slot names

```haskell
Disjoint (Names rs1) (Names rs2)
```

`rs1` and `rs2` must not share a slot label. Violating this is a
compile-time `TypeError` naming the duplicate.

The keiki `RegFile` is positional, so a name collision wouldn't
*break* the runtime — but distinct names also keep the SBV
translation's free-variable names unambiguous, and they make the
composite read clearly. If two aggregates both want `"at"`, prefix
them: `"alertAt"`, `"emailAt"`.

### 2.2 Mid-side alphabet alignment

`t1`'s output type must equal `t2`'s input type. The
`AlertSource ⨾ EmailDelivery` test fixture aligns the two by
declaring `AlertSource`'s output to *be* `EmailCmd`:

```haskell
type AlertEvent = EmailCmd

alertSource :: SymTransducer (HsPred AlertRegs AlertCmd)
                              AlertRegs AlertVertex AlertCmd EmailCmd
```

When the two natural alphabets don't match, you can either:

- Author one aggregate's events to be the other's commands directly
  (the simplest case, above), or
- Insert a small adapter transducer between them — itself a
  one-edge transducer that translates events to commands.

---

## 3. A worked example

The composition spec at `test/Keiki/CompositionSpec.hs` builds a
two-stage pipeline. Reading it top to bottom:

```haskell
-- Stage 1: AlertSource. Defined inline in the spec.
alertSource
  :: SymTransducer (HsPred AlertRegs AlertCmd)
                   AlertRegs AlertVertex AlertCmd EmailCmd

-- Stage 2: the EmailDelivery example aggregate.
emailDelivery
  :: SymTransducer (HsPred EmailRegs EmailCmd)
                   EmailRegs EmailVertex EmailCmd EmailEvent

-- The pipeline.
pipeline
  :: SymTransducer
       (HsPred (Append AlertRegs EmailRegs) AlertCmd)
       (Append AlertRegs EmailRegs)
       (Composite AlertVertex EmailVertex)
       AlertCmd
       EmailEvent
pipeline = compose alertSource emailDelivery
```

Running one external command through the composite:

```haskell
case step pipeline (initial pipeline, initialRegs pipeline) sampleTrigger of
  Just (Composite av ev, _, Just co) -> …
  -- av  = AlertEmitted        (s1 advanced)
  -- ev  = EmailSentVertex     (s2 advanced)
  -- co  = EmailSent {...}     (the wire event)
```

One external `TriggerAlert` command produces one external `EmailSent`
event. The intermediate `EmailCmd` never escapes — `compose` fuses
the two stages into a single transition.

---

## 4. ε-edges in composition

Composition handles `t1`'s ε-edges specially: each ε-edge of `t1`
from `s1` produces one composite edge that advances `s1` and leaves
`s2` unchanged. `t2`'s ε-edges are not chained transitively — `t1`
must explicitly emit a `mid` event for `t2` to fire.

In practice this means:

- A pipeline where every stage emits is the simple case
  (`compose` round-trips `reconstitute` cleanly).
- A pipeline whose first stage emits ε events on some commands has
  composite edges where `s2` doesn't advance. Replay over the event
  log reaches the right place because `applyEvent` only sees the
  emitted events.

The design note's §"Semantics" enumerates the cases.

---

## 5. What composition does **not** preserve

Three things `compose` is documented as *not* carrying through.
Each is a known limitation, not a defect.

- **`TApp1` / `TApp2` opaque escape hatches in `t2`'s mid-side
  reads.** The substitution algorithm rewrites mid-side terms
  against `t1`'s output term. Opaque Haskell functions can't be
  substituted through — the composite uses the original `t2` term
  and the input-recovery proof falters. Avoid `TApp1`/`TApp2` over
  the input alphabet on the second stage.
- **Non-`OPack` outputs on `t1`.** `OPack` is the only output
  constructor today, so this is automatic. Listed in the design
  note for completeness if a future output shape is added.
- **Non-structural `t2` mid-side guards.** Same reason as the
  first item: substitution over `PEq` requires both sides be
  structurally walkable.

`checkHiddenInputs` on the composite catches the practical
consequence (a hidden field somewhere in the chain) — run it after
each `compose`.

---

## 6. Verifying a composite

After building the composite, the standard verification gates:

```haskell
-- 1. No hidden inputs.
checkHiddenInputs pipeline `shouldBe` []

-- 2. Single-valued (symbolic, requires Keiki.Symbolic + z3).
isSingleValuedSym (withSymPred pipeline) `shouldBe` True

-- 3. Round-trip on a sample event log.
reconstitute pipeline [sampleEmailEvent] `shouldSatisfy` isJust
```

The first two are zero-cost in CI (single-valuedness costs the
solver dispatch — see `symbolic-ci.md`). The third costs as much
as one `applyEvent` per event in the fixture.

---

## 7. Composing more than two

`compose` is sequential and binary. For three stages, fold left:

```haskell
threeStage = compose (compose t1 t2) t3
```

The associativity proof isn't formally written down in the design
note; treat the parenthesisation as a free choice and test the
result. The vertex type stacks: `Composite (Composite s1 s2) s3`,
which `Bounded`/`Enum` derive cleanly.

keiki ships sequential `compose`, disjoint-input `alternative`
(§8), and single-step `feedback1` (§9). `parallel` and `Kleisli`
are deferred; the rationale is in
`docs/research/composition-combinators-design.md` under
"Combinators beyond `compose`".

---

## 8. `alternative` — disjoint-input dispatch

### 8.1 The shape

```haskell
alternative
  :: ( WeakenR rs1
     , Disjoint (Names rs1) (Names rs2)
     )
  => SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 co1
  -> SymTransducer (HsPred rs2 ci2) rs2 s2 ci2 co2
  -> SymTransducer (HsPred (Append rs1 rs2) (Either ci1 ci2))
                   (Append rs1 rs2)
                   (Composite s1 s2)
                   (Either ci1 ci2)
                   (Either co1 co2)
```

`alternative t1 t2` consumes `Either ci1 ci2` and emits
`Either co1 co2`. A `Left ci1` advances `t1` from its current
sub-vertex; the `t2` sub-vertex stays put. A `Right ci2` does the
mirror. The two arms have **independent state** — each sibling
evolves as commands arrive for it.

The vertex is the **product** `Composite s1 s2` (the same newtype
`compose` uses). `isFinal` requires both sub-aggregates to be
final.

### 8.2 When to use it in event sourcing

`alternative` is the right combinator when you have **sibling
aggregates** that share a runtime channel but don't drive each
other. The two arms are independent state machines glued together
only by the dispatcher — `Left` goes to one, `Right` goes to the
other, and neither can observe the other's state.

Real-world shapes where this fits cleanly:

- **A single service hosting two bounded contexts.** A small
  e-commerce backend exposes both `OrdersCmd` (place / cancel /
  fulfil orders) and `CustomersCmd` (register / update profile /
  close account) over one HTTP API. Each has its own event log
  and its own aggregate logic. Wiring them as
  `alternative ordersAggregate customersAggregate` gives one
  transducer whose input is `Either OrdersCmd CustomersCmd`,
  whose output is `Either OrdersEvent CustomersEvent`, and whose
  state-space is the cross-product `Composite OrderVertex
  CustomerVertex`. The HTTP layer wraps each request in `Left`
  or `Right` based on the URL path; the composite handles
  dispatch.
- **A multi-tenant control plane with disjoint resource kinds.**
  A SaaS admin service manages both `WorkspaceCmd` (create /
  rename / archive workspaces) and `ApiKeyCmd` (rotate / revoke
  API keys). They have unrelated event streams but share an
  audit log and an admin UI. `alternative workspaces apiKeys`
  gives a single transducer the audit subsystem can subscribe
  to, with each event tagged `Left` (workspace event) or `Right`
  (key event).
- **A read-side projector consuming two upstream event streams.**
  A reporting service folds events from both an `Inventory`
  aggregate and a `Pricing` aggregate into a denormalised view.
  Modelling the projector as `alternative inventoryView
  pricingView` lets it consume `Either InventoryEvent
  PricingEvent` from a merged Kafka topic; each event lands in
  the correct arm and updates only that arm's state. The
  composite's `applyEvent` is the projector's update function.
- **A door / payment terminal / IoT device with two input
  channels.** A point-of-sale terminal accepts both
  `KeypadCmd` (PIN entry, cash-amount input) and `ScannerCmd`
  (barcode scans, NFC tap). The two share a session but evolve
  independent state. `alternative keypad scanner` keeps each
  channel's state machine isolated while letting the runtime
  treat both as one input queue.
- **Sibling sagas competing for one process slot.** A worker
  process needs to drive both a `RefundSaga` and a `ChurnSaga`,
  but only one is active at a time per session. `alternative`
  models them as a single transducer; the runtime decides which
  arm receives the next command.

`alternative` is **not** for:

- *Non-deterministic dispatch* ("either aggregate could handle
  this command"). The `Either` arms make the dispatch
  unambiguous — the wrapping decides which arm fires.
- *Aggregates that should observe each other's state.* Use
  `compose` (sequential) or `feedback1` (one round of policy
  reaction) for that. `alternative` arms are oblivious to each
  other.
- *Sharding one aggregate across instances.* Doubling the vertex
  space to model two shards of `Orders` is rarely worthwhile;
  usually a single transducer with an `instanceId` field handles
  partitioning more cleanly at the runtime layer.

### 8.3 Preconditions

The same disjoint-slot-names constraint as `compose`. There is
**no mid-side alphabet alignment** — the two arms have unrelated
input/output alphabets. Authoring fix-up is therefore minimal:
just rename slots if both halves want, e.g., `"id"`.

`alternative` does **not** introduce a new mutual-exclusion API.
The `Either ci1 ci2` input alphabet makes the cross-arm
single-valuedness check vacuous (t1's `Left`-gated guards are
unsatisfiable on `Right` inputs and vice versa); per-arm
single-valuedness reduces to the underlying sub-aggregates'.

### 8.4 A worked example

`test/Keiki/CompositionAlternativeSpec.hs` builds the canonical
pair:

```haskell
siblings :: SymTransducer
              (HsPred (Append EmailRegs PingRegs) (Either EmailCmd PingCmd))
              (Append EmailRegs PingRegs)
              (Composite EmailVertex PingVertex)
              (Either EmailCmd PingCmd)
              (Either EmailEvent PingEvent)
siblings = alternative emailDelivery pinger
```

A Left-arm step:

```haskell
case step siblings (initial siblings, initialRegs siblings)
                   (Left (SendEmail d)) of
  Just (Composite EmailSentVertex PingIdle, _, Just (Left (EmailSent _))) -> ...
  -- t1 advanced; t2 (PingIdle) is unchanged.
```

A subsequent Right-arm step from there leaves the
`EmailSentVertex` sub-vertex intact while advancing the Pinger
arm to `PingDone`.

### 8.5 What `alternative` preserves and drops

**Preserved (same as `compose`):** mechanical inversion via
`solveOutput`, hidden-input detection, symbolic
single-valuedness.

**Limitations:** none beyond the underlying combinators' (the
lifters are structural, so `TApp1`/`TApp2` over the input on
either side is still discouraged for the same reason `compose`
discourages them).

### 8.6 Verifying an `alternative` composite

```haskell
checkHiddenInputs siblings `shouldBe` []
isSingleValuedSym (withSymPred siblings) `shouldBe` True
reconstitute siblings [Left (EmailSent _), Right (Pong _)] `shouldSatisfy` isJust
```

---

## 9. `feedback1` — single-step aggregate ↔ policy

### 9.1 The shape

```haskell
feedback1
  :: ( WeakenR rs1
     , WeakenR rs2
     , Disjoint (Names rs2) (Names rs1)
     , Disjoint (Names rs1) (Names (Append rs2 rs1))
     )
  => SymTransducer (HsPred rs1 ci) rs1 s1 ci co
  -> SymTransducer (HsPred rs2 co) rs2 s2 co ci
  -> SymTransducer (HsPred (Append rs1 (Append rs2 rs1)) ci)
                   (Append rs1 (Append rs2 rs1))
                   (Composite s1 (Composite s2 s1))
                   ci
                   co
```

Read it as: an aggregate `t :: ci → co` and a policy
`f :: co → ci`, run as one round of cascade. The composite
consumes one external `ci`, runs `t`, feeds the resulting `co`
into `f`, feeds `f`'s output back into a second invocation of
`t`, and emits *that* second `co` as the composite output.

The implementation is literally:

```haskell
feedback1 t f = compose t (compose f t)
```

The composite vertex `Composite s1 (Composite s2 s1)` reflects
this — outer `t` state, then `(policy state, inner t state)`.

### 9.2 When to use it in event sourcing

`feedback1` models the **aggregate ↔ stateless-policy** loop
that's common in process-manager and saga shapes. Use it when:

- exactly one round of reaction belongs in the same logical step
  as the triggering command, and
- the policy's decision is a pure function of the aggregate's
  emitted event (no policy-side history needed).

Real-world shapes where this fits cleanly:

- **Auto-fulfilment with idempotent confirmation.** A user
  submits `PlaceOrder`; the order aggregate emits
  `OrderAccepted`; a stateless policy turns it into
  `ConfirmAcceptance` (e.g. stamping a confirmation number from
  the event); the order aggregate consumes the confirmation and
  emits `OrderConfirmed`. Wiring this as
  `feedback1 orderAggregate confirmPolicy` makes
  `PlaceOrder → OrderConfirmed` one atomic step in the event
  log; the intermediate `OrderAccepted`/`ConfirmAcceptance`
  pair never escapes the composite.
- **Form validation and acknowledgement.** A `SubmitForm`
  command produces a `FormSubmitted` event; a stateless
  validator inspects the event's payload and emits
  `MarkValidated` (or `MarkInvalid`); the form aggregate
  consumes the verdict and emits the public event
  `FormValidated` (or `FormRejected`). The consumer of the
  composite sees one external command in, one external event
  out, with the validation pass hidden inside.
- **Notification dispatch with deduplication.** A `LogIn` event
  triggers a stateless policy that emits a
  `SendLoginNotification` command if the device is unrecognised
  (decision based purely on payload fields, not history); the
  notifications aggregate consumes the command and emits
  `LoginNotificationSent`. The composite emits a single
  observable event per `LogIn`.
- **Reservation auto-release on expiry.** A
  `CheckReservation` command produces an `ExpiryDetected` event
  carrying the timestamp; a stateless policy compares
  payload-vs-now and emits `ReleaseReservation`; the aggregate
  consumes the release and emits the public
  `ReservationReleased` event. (This works because the timestamp
  comparison is encoded in the policy's *guards*, not in
  policy-side state.)
- **Single-step compensation.** A failed payment emits
  `PaymentDeclined`; a stateless compensation policy emits the
  matching `MarkOrderUnpaid` command; the order aggregate
  consumes it and emits `OrderMarkedUnpaid`. One round, no
  policy state, exactly the shape `feedback1` is designed for.
- **CQRS read-model invalidation.** An admin `EditCatalogItem`
  produces `CatalogItemEdited`; a stateless policy emits
  `InvalidateCache` for the affected ids (computed from the
  event payload); the cache aggregate consumes the
  invalidation and emits `CacheInvalidated`. The composite
  exposes the invalidation as part of the same step as the
  edit.

`feedback1` is **not** for:

- *Loops with non-trivial state in the policy.* The "stateless
  policy" requirement is documented but not enforced. A policy
  with its own register file or vertex history breaks the
  single-step semantics — its edges may iterate across composite
  steps in ways the cascade-as-one-edge intuition doesn't
  capture. If the policy needs to remember anything (rate limits,
  sliding windows, prior decisions), model it as a fully-fledged
  aggregate and use `compose` plus `alternative` to wire it into
  the system.
- *Unbounded iteration to quiescence.* `feedback1` is exactly
  one round. Two rounds is `feedback1 (feedback1 t f) f`. Three
  is another nesting. There is no `feedbackN`-with-fuel today.
  Workflows that "react until no more reactions are pending"
  belong in a hand-rolled saga aggregate or wait for a future
  bounded-iteration combinator.
- *Aggregates with a non-empty register file.* See §9.3.
- *Cross-aggregate orchestrations.* If the policy's follow-up
  command targets a *different* aggregate than the one that
  emitted the triggering event, the natural fit is two stages
  glued by `compose` (or a saga aggregate), not `feedback1`.
  `feedback1`'s shape is "the same aggregate reacts to its own
  event via a policy".

### 9.3 The stateless-aggregate restriction

The constraint
`Disjoint (Names rs1) (Names (Append rs2 rs1))` reduces, since
`rs1` appears on both sides of `Append`, to "rs1 disjoint from
itself" — only satisfiable when `rs1 = '[]`. **`feedback1`
typechecks only for stateless aggregates `t`** (empty register
file). The policy `f`'s register file may be non-empty, but
keiki's "stateless policy" recommendation makes that uncommon.

This is a real limitation of the two-stacked-`compose` reduction:
`t` appears twice and each appearance gets its own copy of
`rs1`. A "shared-state" `feedback1` variant (the second `t`
reading/writing the first `t`'s registers via custom edge
construction outside `compose`) is documented as a future
extension. If you need stateful aggregate ↔ policy round trips
today, you have two options:

1. Model the round-trip as a single, longer-lived aggregate that
   internalises the policy as additional vertices (the
   "expanded" form).
2. Hand-author the cascade as one transducer (drop down to
   `Keiki.Core` `Edge` records and bypass the combinator).

### 9.4 A worked example

`test/Keiki/CompositionFeedback1Spec.hs` ships a toggle ↔
echo-policy fixture: a stateless toggle aggregate and a
one-vertex policy that echoes the toggle's event back as a
follow-up command. The composite turns one external command into
the *second* round's event.

```haskell
loop :: SymTransducer ... ToggleCmd ToggleEvent
loop = feedback1 toggle echoPolicy

case step loop (initial loop, initialRegs loop) externalCmd of
  Just (Composite _ (Composite _ _), _, Just secondRoundEvent) -> ...
```

### 9.5 What `feedback1` preserves and drops

**Preserved:** all three guarantees, inherited from the two
underlying `compose` calls.

**Limitations:**

- Stateless aggregate only (§9.3).
- Vertex space is `|s1| × |s2| × |s1|`; nesting multiplies it.
  Watch the symbolic check's runtime if you nest deeply.
- Policy is conventionally stateless. A stateful policy
  typechecks but the single-step intuition breaks down.
- No `feedbackN n t f` with fuel — multi-round patterns are
  expressed by nesting `feedback1`s.

### 9.6 Verifying a `feedback1` composite

Same gates as the other combinators:

```haskell
checkHiddenInputs loop `shouldBe` []
isSingleValuedSym (withSymPred loop) `shouldBe` True
reconstitute loop [secondRoundEvent] `shouldSatisfy` isJust
```

---

## 10. Common errors

**Slot-name collision.**

```
• Slot name "at" appears in both rs1 and rs2
```

Rename slots in one of the two aggregates.

**Mid alphabet mismatch.**

```
• Couldn't match type ‘EmailCmd’ with ‘OtherCmd’
```

`t1`'s output type doesn't equal `t2`'s input type. Either align
them at the source or insert an adapter aggregate.

**Hidden input on the composite, but not on either stage.**

```
checkHiddenInputs pipeline `shouldBe` []   -- fails
```

A field that `t1` writes into a `mid` event but `t2` doesn't
re-emit on the wire. Either widen `t2`'s output to carry the
field, or accept that the composite's `applyEvent` for that edge
won't recover from the event log alone.

**`feedback1` rejects a stateful aggregate.**

```
• Slot name "x" appears in both rs1 and (Append rs2 rs1)
```

`feedback1`'s `Disjoint (Names rs1) (Names (Append rs2 rs1))`
constraint reduces to "rs1 disjoint from itself" whenever `rs1`
is non-empty. The fix is structural: either drop down to a
shared-state hand-rolled cascade, or restructure the aggregate
so the policy round-trip is internalised as additional vertices.
See §9.3.

**`alternative`'s arms have unrelated alphabets — no mid-alphabet
mismatch is possible**, by construction. If you find yourself
reaching for an adapter inside an `alternative`, you probably
want `compose` instead.

---

## 11. Pointers

- `src/Keiki/Composition.hs` — implementation; haddocks at
  `compose`, `alternative`, and `feedback1` summarise the
  mechanics.
- `docs/research/composition-combinators-design.md` — formal
  semantics, substitution algorithm, single-valuedness proof
  sketch, per-combinator design records, the full `crem`
  catalogue compared.
- `test/Keiki/CompositionSpec.hs` — the canonical
  `AlertSource ⨾ EmailDelivery` fixture for `compose`.
- `test/Keiki/CompositionAlternativeSpec.hs` —
  `EmailDelivery ⊕ Pinger` fixture for `alternative`.
- `test/Keiki/CompositionFeedback1Spec.hs` — toggle ↔ echo-policy
  fixture for `feedback1`.
