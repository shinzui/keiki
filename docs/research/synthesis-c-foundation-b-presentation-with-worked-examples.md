# Synthesis: Symbolic-Register Foundation, Indexed-State Presentation

This note unifies Direction B (`data-direction-b-indexed-state-per-vertex.md`)
and Direction C (`data-direction-c-symbolic-and-register-automata.md`) into a
single proposal, then grounds it in two fully worked examples — an event-sourced
aggregate and a process manager.

The headline:

> **C is the formalism. B is an optional presentation layer on top.**

C answers the foundational question (how data lives in the formalism so
that `apply` can still be derived). B answers an ergonomic question (how
to surface per-vertex data shapes to the human reading the model). They
are not competing proposals — they're at different layers, and they
compose.

---

## 1. The proposal

**Adopt the symbolic-register transducer** as the v1 core type. State is
`(s, RegFile rs)` where `s` is a finite control vertex and `rs` is a
typed register file. Edges unify guard, update, output, and target into
a single `Edge` value, so `delta`, `omega`, and `rho` cannot disagree by
construction. Predicates and update terms are a closed combinator
language; the v1 carrier is a Haskell-function `BoolAlg`, with an
SBV-backed instance deferred to v2.

**Layer indexed-state views on top, opt-in.** When a control vertex
carries genuinely distinct data, the user (or a derived helper) can
define a GADT `View (v :: Vertex)` that projects the register file into
a vertex-specific record. This is not a different model — it's a
read-only lens onto the register file, gated by the singleton.

**Wire types stay flat.** Commands and events are ordinary sum types
with payloads. They cross JSON, queues, and the event store; indexing
them buys nothing and costs at every boundary.

The decisive technical win: `apply` derivation, which the EFSM extension
surrendered to data, comes back for well-formed schemas (output term
invertible in input fields), and *fails detectably at build time* when a
schema is malformed (hidden inputs, non-injective output).

---

## 2. The core type

```haskell
{-# LANGUAGE DataKinds, GADTs, KindSignatures, TypeFamilies #-}
{-# LANGUAGE FunctionalDependencies, MultiParamTypeClasses    #-}

-- Effective Boolean algebra over (RegFile rs, ci) pairs.
class BoolAlg phi a | phi -> a where
  top, bot   :: phi
  conj, disj :: phi -> phi -> phi
  neg        :: phi -> phi
  models     :: phi -> a -> Bool
  sat        :: phi -> Maybe a   -- v1: Hedgehog witnesses; v2: SMT
  isBot      :: phi -> Bool

-- Typed heterogeneous register tuple.
data RegFile (rs :: [Type])

data Index (rs :: [Type]) (r :: Type)   -- type-safe pointer into rs

-- Closed term language. Eval'd in v1; SMT-translated in v2.
data Term  (rs :: [Type]) (ci :: Type) (r :: Type)
data OutTerm (rs :: [Type]) (ci :: Type) (co :: Type)

-- Copyless update language: each register written at most once per edge.
data Update (rs :: [Type]) (ci :: Type) where
  Keep    :: Update rs ci
  Set     :: Index rs r -> Term rs ci r -> Update rs ci
  Combine :: Update rs ci -> Update rs ci -> Update rs ci   -- distinct targets

-- The unified edge.
data Edge phi rs ci co s = Edge
  { guard  :: phi
  , update :: Update rs ci
  , output :: Maybe (OutTerm rs ci co)   -- Nothing = ε
  , target :: s
  }

-- The single source of truth.
data SymTransducer phi rs s ci co = SymTransducer
  { edgesOut    :: s -> [Edge phi rs ci co s]
  , initial     :: s
  , initialRegs :: RegFile rs
  , isFinal     :: s -> Bool
  }
```

The familiar functions are projections, not fields:

```haskell
delta :: SymTransducer phi rs s ci co
      -> s -> RegFile rs -> ci -> Maybe (s, RegFile rs)
delta t s regs ci = case
  [ (target e, runUpdate (update e) regs ci)
  | e <- edgesOut t s, models (guard e) (regs, ci) ] of
    [single] -> Just single
    _        -> Nothing

omega :: SymTransducer phi rs s ci co
      -> s -> RegFile rs -> ci -> Maybe co
omega t s regs ci = case
  [ evalOut o regs ci
  | e <- edgesOut t s, models (guard e) (regs, ci), Just o <- [output e] ] of
    [o] -> Just o
    _   -> Nothing
```

`(Enum, Bounded)` survives on `s` only. The data axes (`ci`, `co`,
`rs`) are arbitrary and live behind `phi`, `Term`, `OutTerm`,
`Update`. That's the entire formal-vs-data split, made explicit.

---

## 3. Where indexed state (B) fits

The state of a `SymTransducer` is the pair `(s, RegFile rs)`. The
register file is shared across all vertices — that's how composition
and `apply` derivation get to work uniformly. But human readers
benefit when each vertex's data is named.

The B-view is a per-vertex projection. For each `v :: Vertex`, define
the slice of the register file that's "live" in `v`:

```haskell
data View (v :: Vertex) where
  PendingV   :: { vDocId :: DocumentId, vRequired :: Int }
             -> View 'Pending
  AwaitingV  :: { vDocId :: DocumentId, vRequired :: Int
                , vApproved :: Set UserId, vRejected :: Set UserId }
             -> View 'Awaiting
  ApprovedV  :: { vDocId :: DocumentId, vApprovers :: Set UserId, vAt :: UTCTime }
             -> View 'Approved
  RejectedV  :: { vDocId :: DocumentId, vReason :: Text } -> View 'Rejected

viewFor :: SVertex v -> RegFile MultiApprovalRegs -> View v
viewFor SPending  rs = PendingV  (rs ! #docId) (rs ! #required)
viewFor SAwaiting rs = AwaitingV (rs ! #docId) (rs ! #required)
                                 (rs ! #approved) (rs ! #rejected)
viewFor SApproved rs = ApprovedV (rs ! #docId) (rs ! #approved) (rs ! #completedAt)
viewFor SRejected rs = RejectedV (rs ! #docId) (rs ! #reason)
```

`viewFor` is a pure projection. It doesn't change the formalism; it
gives the human a vertex-shaped record to pattern-match on without the
type system letting them ask `Pending` for `approvedBy`.

The library can ship a default `View v = RegFile rs` (no projection) for
simple aggregates. Users opt into a per-vertex GADT only when the
vertex shapes genuinely diverge enough to be worth naming. A `genView`
TH helper now exists as `Keiki.Generics.TH.deriveView` (see EP-13 / MP-5
and `docs/research/genview-th-splice-design.md`); the default
`View v = RegFile rs` for non-opted-in aggregates is still deferred.

The B note's existential `SomeState` becomes the natural pair
`(SVertex v, View v)`, materialized as `(s, RegFile rs)` underneath. The
pattern-matching ergonomics from B carry over verbatim.

---

## 4. Worked Example 1 — User Registration (event-sourced aggregate)

The canonical aggregate from `multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`,
re-cast in the symbolic-register formalism.

### Domain

```haskell
data Vertex = PotentialCustomer | RequiresConfirmation | Confirmed | Deleted
  deriving (Eq, Show, Enum, Bounded)

type UserRegRegs =
  '[ "email"         ':-> Email
   , "confirmCode"   ':-> ConfirmationCode
   , "registeredAt"  ':-> UTCTime
   , "confirmedAt"   ':-> UTCTime
   , "deletedAt"     ':-> UTCTime
   ]

-- Command payloads.
data StartRegistrationData = StartRegistrationData
  { email       :: Email
  , confirmCode :: ConfirmationCode
  , at          :: UTCTime
  } deriving (Eq, Show, Generic)

data ConfirmAccountData = ConfirmAccountData
  { confirmCode :: ConfirmationCode
  , at          :: UTCTime
  } deriving (Eq, Show, Generic)

newtype ResendConfirmationData = ResendConfirmationData { at :: UTCTime }
  deriving (Eq, Show, Generic)

newtype FulfillGDPRRequestData = FulfillGDPRRequestData { at :: UTCTime }
  deriving (Eq, Show, Generic)

data UserCmd
  = StartRegistration  StartRegistrationData
  | ConfirmAccount     ConfirmAccountData
  | ResendConfirmation ResendConfirmationData
  | FulfillGDPRRequest FulfillGDPRRequestData

-- Event payloads. Same shape pattern: outer constructor + record.
data RegistrationStartedData = RegistrationStartedData
  { email       :: Email
  , confirmCode :: ConfirmationCode
  , at          :: UTCTime
  } deriving (Eq, Show, Generic)

newtype ConfirmationEmailSentData = ConfirmationEmailSentData { email :: Email }
  deriving (Eq, Show, Generic)

data AccountConfirmedData = AccountConfirmedData
  { email :: Email
  , at    :: UTCTime
  } deriving (Eq, Show, Generic)

data ConfirmationResentData = ConfirmationResentData
  { email       :: Email
  , confirmCode :: ConfirmationCode
  , at          :: UTCTime
  } deriving (Eq, Show, Generic)

data AccountDeletedData = AccountDeletedData
  { email :: Email
  , at    :: UTCTime
  } deriving (Eq, Show, Generic)

data UserEvent
  = RegistrationStarted   RegistrationStartedData
  | ConfirmationEmailSent ConfirmationEmailSentData
  | AccountConfirmed      AccountConfirmedData
  | ConfirmationResent    ConfirmationResentData
  | AccountDeleted        AccountDeletedData
```

(Assumes `DuplicateRecordFields` and `OverloadedRecordDot` — `d.email`
disambiguates by the record type of `d`. This is the common shape in
modern Haskell event sourcing: one record per command/event payload,
wrapped by a sum constructor of the same name minus the `Data` suffix.)

Notes on data discipline:

- `UTCTime` is a *command field*, not pulled from a clock inside `delta`.
  This keeps `delta` pure and event-sufficient: the timestamp travels in
  the event payload, so replay produces the same state.
- `ConfirmationCode` is generated outside the transducer (the API layer)
  and arrives in the command. Same reason.
- The `Email` is carried in *every* event, even though it's already in
  the register file after the first event. This is the price of "event
  is sufficient to recover state without context" — you make events
  idempotent and standalone.

### The transducer

A two-step command (`StartRegistration` produces both
`RegistrationStarted` and `ConfirmationEmailSent`) maps onto two edges
via the state-refinement approach (Approach 1 from the multi-event doc).
The intermediate vertex `Registering` makes the data flow explicit:

```haskell
data Vertex
  = PotentialCustomer
  | Registering            -- intermediate
  | RequiresConfirmation
  | Confirmed
  | Deleted

userReg :: SymTransducer (HsPred UserRegRegs UserCmd) UserRegRegs Vertex UserCmd UserEvent
userReg = SymTransducer
  { edgesOut = \case

      PotentialCustomer ->
        [ Edge { guard  = matchCmd \(StartRegistration _) -> True
               , update = Combine (Set #email        (\(StartRegistration d) -> d.email))
                       $ Combine (Set #confirmCode  (\(StartRegistration d) -> d.confirmCode))
                                 (Set #registeredAt (\(StartRegistration d) -> d.at))
               , output = Just (mkOut $ \_regs (StartRegistration d) ->
                                  RegistrationStarted RegistrationStartedData
                                    { email       = d.email
                                    , confirmCode = d.confirmCode
                                    , at          = d.at
                                    })
               , target = Registering
               }
        ]

      Registering ->
        -- internal Continue command emits the second event
        [ Edge { guard  = matchCmd \Continue -> True
               , update = Keep
               , output = Just (mkOut $ \regs _ ->
                                  ConfirmationEmailSent ConfirmationEmailSentData
                                    { email = regs ! #email })
               , target = RequiresConfirmation
               }
        ]

      RequiresConfirmation ->
        [ -- right code: confirm
          Edge { guard  = \(regs, ConfirmAccount d) -> d.confirmCode == regs ! #confirmCode
               , update = Set #confirmedAt (\(ConfirmAccount d) -> d.at)
               , output = Just (mkOut $ \regs (ConfirmAccount d) ->
                                  AccountConfirmed AccountConfirmedData
                                    { email = regs ! #email
                                    , at    = d.at
                                    })
               , target = Confirmed }
          -- resend (rotates the code)
        , Edge { guard  = matchCmd \(ResendConfirmation _) -> True
               , update = Combine (Set #confirmCode freshCode)
                                  (Set #registeredAt (\(ResendConfirmation d) -> d.at))
               , output = Just (mkOut $ \regs (ResendConfirmation _) ->
                                  ConfirmationResent ConfirmationResentData
                                    { email       = regs ! #email
                                    , confirmCode = regs ! #confirmCode
                                    , at          = regs ! #registeredAt
                                    })
               , target = RequiresConfirmation }
          -- GDPR before confirmation: silent (ε)
        , Edge { guard  = matchCmd \(FulfillGDPRRequest _) -> True
               , update = Set #deletedAt (\(FulfillGDPRRequest d) -> d.at)
               , output = Nothing
               , target = Deleted }
        ]

      Confirmed ->
        [ Edge { guard  = matchCmd \(FulfillGDPRRequest _) -> True
               , update = Set #deletedAt (\(FulfillGDPRRequest d) -> d.at)
               , output = Just (mkOut $ \regs (FulfillGDPRRequest d) ->
                                  AccountDeleted AccountDeletedData
                                    { email = regs ! #email
                                    , at    = d.at
                                    })
               , target = Deleted }
        ]

      Deleted -> []

  , initial     = PotentialCustomer
  , initialRegs = emptyRegs
  , isFinal     = \case Deleted -> True; _ -> False
  }
```

(The pseudosyntax `matchCmd \pat -> ...`, `mkOut`, and the inline
lambdas extracting record fields stand in for what `Term` / `OutTerm`
look like at the user surface. Concretely they're either built from a
small DSL with `Generic`-driven helpers — `Set #email (lensFor @"email"
@"StartRegistration")` or similar — or, in v1, from plain Haskell
functions over the typed register file.)

### A real event stream

Here's the wire history for one registration:

```
1. RegistrationStarted   { email="alice@x", confirmCode="Z9F4", at=2026-04-30T10:00:00Z }
2. ConfirmationEmailSent { email="alice@x" }
3. ConfirmationResent    { email="alice@x", confirmCode="K2P7", at=2026-04-30T10:15:03Z }
4. AccountConfirmed      { email="alice@x",                     at=2026-04-30T10:18:42Z }
5. AccountDeleted        { email="alice@x",                     at=2027-01-05T14:00:00Z }
```

### Reconstitution, mechanically

`apply` is **derived** from the transducer. For each event, the
mechanism walks the outgoing edges of the current vertex, finds the
unique edge whose `output` term unifies with the observed event, and
runs the recovered command through that edge's update.

```
init: (PotentialCustomer, regs={ })

step 1 — RegistrationStarted { email="alice@x", confirmCode="Z9F4", at=t₀ }
  edgesOut PotentialCustomer has one edge.
  output term: \_regs (StartRegistration d) ->
    RegistrationStarted RegistrationStartedData
      { email = d.email, confirmCode = d.confirmCode, at = d.at }
  invert against ev:  solveOutput recovers d field-for-field, so
    ci = StartRegistration (StartRegistrationData "alice@x" "Z9F4" t₀)
  update Combine (Set #email …) (Set #confirmCode …) (Set #registeredAt …)
  → (Registering, { email="alice@x", confirmCode="Z9F4", registeredAt=t₀ })

step 2 — ConfirmationEmailSent { email="alice@x" }
  edgesOut Registering has one edge with output term
    \regs _ -> ConfirmationEmailSent (ConfirmationEmailSentData (regs ! #email)).
  output is independent of ci (Continue is a unit). Trivially invertible.
  Verify regs ! #email == "alice@x" ✓
  → (RequiresConfirmation, { email="alice@x", confirmCode="Z9F4", … })

step 3 — ConfirmationResent { email="alice@x", confirmCode="K2P7", at=t₁ }
  edgesOut RequiresConfirmation: three edges. Two emit events:
    Confirm  → AccountConfirmed
    Resend   → ConfirmationResent
  Match on event constructor → Resend edge.
  Recover ci = ResendConfirmation (ResendConfirmationData t₁); update
  rotates confirmCode and registeredAt.
  → (RequiresConfirmation, { email=…, confirmCode="K2P7", registeredAt=t₁ })

step 4 — AccountConfirmed { email="alice@x", at=t₂ }
  Match → Confirm edge. The edge's output term reads d.email and d.at
  from the command, both of which appear in the event. But the edge's
  *guard* reads d.confirmCode — and AccountConfirmedData has no
  confirmCode field. solveOutput cannot recover ci.confirmCode; the
  guard cannot be re-checked at replay.  ⚠

  ▸  Hidden-input check at build time would have caught this:
     "edge in RequiresConfirmation depends on input field
      `confirmCode` not present in output event AccountConfirmed".
     Resolution applied below.
```

The walkthrough surfaces a real issue: `AccountConfirmed` doesn't
carry the confirmation code, but the edge that produces it has a
guard that depends on the code. **The hidden-input check
(`data-direction-c §5`) flags this at model-build time** — it scans
edges where the update or guard reads input fields not present in the
output term, and either warns or refuses to derive `apply`.

Two clean fixes:

1. **Include the code in the event.** Most defensible — the event is
   then self-contained for replay and audit. Add `confirmCode` to
   `AccountConfirmedData`.
2. **Move the guard out of the edge.** Validate the code at the API
   layer; the transducer's `ConfirmAccount` command edge is
   unconditional. The aggregate then trusts the boundary. Simpler
   transducer, looser invariant.

Either is fine. The point is the symbolic-register encoding **made
the choice visible at build time**, instead of letting it lurk until a
replay produced wrong state. With the EFSM extension's opaque
`rho :: s -> ctx -> c -> ctx`, the check has no purchase.

### Step 4 with fix (1) applied

```
step 4 — AccountConfirmed { email="alice@x", confirmCode="K2P7", at=t₂ }
  Recover ci = ConfirmAccount (ConfirmAccountData "K2P7" t₂).
  Guard re-checks: d.confirmCode == regs ! #confirmCode → "K2P7" == "K2P7" ✓
  Update sets #confirmedAt = t₂.
  → (Confirmed, { email=…, confirmCode="K2P7", confirmedAt=t₂, … })

step 5 — AccountDeleted { email="alice@x", at=t₃ }
  Match → GDPR edge in Confirmed.
  Recover ci = FulfillGDPRRequest (FulfillGDPRRequestData t₃).
  Update sets #deletedAt = t₃.
  → (Deleted, { …, deletedAt=t₃ })
```

`reconstitute userReg events == Just (Deleted, regs)`. `apply` was
not user-provided — it fell out of the transducer.

### Optional B-view

If the codebase wants a pretty record per state:

```haskell
data UserView (v :: Vertex) where
  PCV    :: UserView 'PotentialCustomer
  RegV   :: UserView 'Registering
  RCV    :: { rcEmail :: Email, rcCode :: ConfirmationCode
            , rcRegisteredAt :: UTCTime } -> UserView 'RequiresConfirmation
  ConfV  :: { cEmail :: Email, cConfirmedAt :: UTCTime }
         -> UserView 'Confirmed
  DelV   :: { dDeletedAt :: UTCTime } -> UserView 'Deleted

userView :: SVertex v -> RegFile UserRegRegs -> UserView v
userView SPotentialCustomer    _    = PCV
userView SRegistering          _    = RegV
userView SRequiresConfirmation regs = RCV (regs!#email) (regs!#confirmCode)
                                          (regs!#registeredAt)
userView SConfirmed            regs = ConfV (regs!#email) (regs!#confirmedAt)
userView SDeleted              regs = DelV (regs!#deletedAt)
```

The view is a pure projection. The transducer doesn't know about it.
You write it once if you want the type-safe record per vertex; you skip
it if `regs ! #email` is fine.

---

## 5. Worked Example 2 — Order Fulfillment (process manager)

A process manager (PM) is a transducer over a different alphabet: its
inputs are *events from other bounded contexts* (routed in by
subscriptions) and its outputs are *commands or requests dispatched to
those other contexts*. Same formalism, different alphabet semantics.

### Scenario

Customer submits an order. The PM coordinates:

1. Authorize payment (Payment context)
2. Reserve inventory (Inventory context)
3. Create shipment (Shipping context)

If payment fails or inventory is short, compensate any work that
already happened. If the customer doesn't pay within 24 hours,
auto-cancel.

### Domain

```haskell
data Vertex
  = AwaitingPayment
  | ReservingInventory
  | AwaitingShipment
  | Completed
  | Compensating
  | Cancelled

type OrderRegs =
  '[ "orderId"        ':-> OrderId
   , "customerId"     ':-> CustomerId
   , "lineItems"      ':-> [LineItem]
   , "shippingAddr"   ':-> Address
   , "totalCents"     ':-> Int
   , "paymentRef"     ':-> Maybe PaymentRef
   , "reservationRef" ':-> Maybe ReservationRef
   , "shipmentRef"    ':-> Maybe ShipmentRef
   , "compensations"  ':-> Set CompensationStep   -- which compensations are still outstanding
   , "cancelReason"   ':-> Maybe Text
   , "deadline"       ':-> UTCTime
   ]

-- Input payloads. Wrapped per-constructor records.
data SubmitOrderData = SubmitOrderData
  { orderId      :: OrderId
  , customerId   :: CustomerId
  , lineItems    :: [LineItem]
  , shippingAddr :: Address
  , totalCents   :: Int
  , deadline     :: UTCTime
  } deriving (Eq, Show, Generic)

newtype PaymentAuthorizedData = PaymentAuthorizedData { paymentRef :: PaymentRef }
  deriving (Eq, Show, Generic)

data PaymentDeclinedData = PaymentDeclinedData
  { paymentRef :: PaymentRef
  , reason     :: Text
  } deriving (Eq, Show, Generic)

newtype InventoryReservedData = InventoryReservedData
  { reservationRef :: ReservationRef } deriving (Eq, Show, Generic)

data InventoryShortageData = InventoryShortageData
  { reservationRef :: ReservationRef
  , missingSkus    :: [Sku]
  } deriving (Eq, Show, Generic)

newtype ShipmentCreatedData = ShipmentCreatedData
  { shipmentRef :: ShipmentRef } deriving (Eq, Show, Generic)

newtype RefundCompletedData = RefundCompletedData
  { paymentRef :: PaymentRef } deriving (Eq, Show, Generic)

newtype InventoryReleasedData = InventoryReleasedData
  { reservationRef :: ReservationRef } deriving (Eq, Show, Generic)

data CancelOrderData = CancelOrderData
  { customerId :: CustomerId
  , reason     :: Text
  } deriving (Eq, Show, Generic)

-- Inputs to the PM. These come from:
--   • the customer (SubmitOrder, CancelOrder)
--   • subscriptions on other contexts' events (PaymentAuthorized, …)
--   • the timer service (PaymentDeadlineExpired)
data OrderInput
  = SubmitOrder            SubmitOrderData
  | PaymentAuthorized      PaymentAuthorizedData
  | PaymentDeclined        PaymentDeclinedData
  | InventoryReserved      InventoryReservedData
  | InventoryShortage      InventoryShortageData
  | ShipmentCreated        ShipmentCreatedData
  | RefundCompleted        RefundCompletedData
  | InventoryReleased      InventoryReleasedData
  | PaymentDeadlineExpired                         -- nullary, no payload
  | CancelOrder            CancelOrderData

-- Output payloads.
newtype OrderAcceptedData = OrderAcceptedData { orderId :: OrderId }
  deriving (Eq, Show, Generic)

data PaymentAuthorizationAskedData = PaymentAuthorizationAskedData
  { orderId    :: OrderId
  , totalCents :: Int
  } deriving (Eq, Show, Generic)

data PaymentTimerScheduledData = PaymentTimerScheduledData
  { orderId  :: OrderId
  , deadline :: UTCTime
  } deriving (Eq, Show, Generic)

data InventoryReservationAskedData = InventoryReservationAskedData
  { orderId   :: OrderId
  , lineItems :: [LineItem]
  } deriving (Eq, Show, Generic)

data ShipmentCreationAskedData = ShipmentCreationAskedData
  { orderId      :: OrderId
  , shippingAddr :: Address
  , lineItems    :: [LineItem]
  } deriving (Eq, Show, Generic)

newtype OrderCompletedData = OrderCompletedData { orderId :: OrderId }
  deriving (Eq, Show, Generic)

newtype PaymentRefundAskedData = PaymentRefundAskedData
  { paymentRef :: PaymentRef } deriving (Eq, Show, Generic)

newtype InventoryReleaseAskedData = InventoryReleaseAskedData
  { reservationRef :: ReservationRef } deriving (Eq, Show, Generic)

data OrderCancelledData = OrderCancelledData
  { orderId :: OrderId
  , reason  :: Text
  } deriving (Eq, Show, Generic)

-- Outputs. Read by subscriptions and translated into commands on other
-- aggregates or scheduled queue messages.
data OrderOutput
  = OrderAccepted              OrderAcceptedData
  | PaymentAuthorizationAsked  PaymentAuthorizationAskedData
  | PaymentTimerScheduled      PaymentTimerScheduledData
  | InventoryReservationAsked  InventoryReservationAskedData
  | ShipmentCreationAsked      ShipmentCreationAskedData
  | OrderCompletedE            OrderCompletedData
  | PaymentRefundAsked         PaymentRefundAskedData
  | InventoryReleaseAsked      InventoryReleaseAskedData
  | OrderCancelledE            OrderCancelledData
```

### A few representative edges

```haskell
orderPM :: SymTransducer (HsPred OrderRegs OrderInput) OrderRegs Vertex OrderInput OrderOutput
orderPM = SymTransducer { edgesOut = pmEdges, … }

pmEdges :: Vertex -> [Edge ...]
pmEdges = \case

  AwaitingPayment ->
    [ -- happy: payment authorized, move to inventory
      Edge { guard  = matchInput \(PaymentAuthorized _) -> True
           , update = Set #paymentRef (\(PaymentAuthorized d) -> Just d.paymentRef)
           , output = Just (mkOut $ \regs _ ->
                              InventoryReservationAsked InventoryReservationAskedData
                                { orderId   = regs ! #orderId
                                , lineItems = regs ! #lineItems
                                })
           , target = ReservingInventory }
      -- payment declined: cancel
    , Edge { guard  = matchInput \(PaymentDeclined _) -> True
           , update = Set #cancelReason (\(PaymentDeclined d) -> Just d.reason)
           , output = Just (mkOut $ \regs (PaymentDeclined d) ->
                              OrderCancelledE OrderCancelledData
                                { orderId = regs ! #orderId
                                , reason  = d.reason
                                })
           , target = Cancelled }
      -- timer fired before payment authorized
    , Edge { guard  = matchInput \PaymentDeadlineExpired -> True
           , update = Set #cancelReason (Const (Just "payment timeout"))
           , output = Just (mkOut $ \regs _ ->
                              OrderCancelledE OrderCancelledData
                                { orderId = regs ! #orderId
                                , reason  = "payment timeout"
                                })
           , target = Cancelled }
      -- customer initiates cancel
    , Edge { guard  = matchInput \(CancelOrder _) -> True
           , update = Set #cancelReason (\(CancelOrder d) -> Just d.reason)
           , output = Just (mkOut $ \regs (CancelOrder d) ->
                              OrderCancelledE OrderCancelledData
                                { orderId = regs ! #orderId
                                , reason  = d.reason
                                })
           , target = Cancelled }
    ]

  ReservingInventory ->
    [ -- happy: inventory reserved, move to shipment
      Edge { guard  = matchInput \(InventoryReserved _) -> True
           , update = Set #reservationRef (\(InventoryReserved d) -> Just d.reservationRef)
           , output = Just (mkOut $ \regs _ ->
                              ShipmentCreationAsked ShipmentCreationAskedData
                                { orderId      = regs ! #orderId
                                , shippingAddr = regs ! #shippingAddr
                                , lineItems    = regs ! #lineItems
                                })
           , target = AwaitingShipment }
      -- shortage: refund payment, then go to Compensating
    , Edge { guard  = matchInput \(InventoryShortage _) -> True
           , update = Combine
                       (Set #cancelReason  (Const (Just "inventory shortage")))
                       (Set #compensations (Const (Set.singleton CompensateRefundPayment)))
           , output = Just (mkOut $ \regs _ ->
                              PaymentRefundAsked PaymentRefundAskedData
                                { paymentRef = fromJust (regs ! #paymentRef) })
           , target = Compensating }
    ]

  AwaitingShipment ->
    [ Edge { guard  = matchInput \(ShipmentCreated _) -> True
           , update = Set #shipmentRef (\(ShipmentCreated d) -> Just d.shipmentRef)
           , output = Just (mkOut $ \regs _ ->
                              OrderCompletedE OrderCompletedData
                                { orderId = regs ! #orderId })
           , target = Completed }
    ]

  Compensating ->
    [ Edge { guard  = \(regs, RefundCompleted _) ->
                       Set.member CompensateRefundPayment (regs ! #compensations)
           , update = Set #compensations
                        (Const . Set.delete CompensateRefundPayment . (! #compensations))
           , output = Just (mkOut $ \regs _ ->
                              OrderCancelledE OrderCancelledData
                                { orderId = regs ! #orderId
                                , reason  = fromJust (regs ! #cancelReason)
                                })
           , target = Cancelled }
    ]

  Completed -> []
  Cancelled -> []
```

### How the runtime threads the alphabets

Conceptually:

```
                  ┌───────────────────────────────────┐
   SubmitOrder    │           orderPM                  │  OrderAccepted
   ────────────► │   (SymTransducer over OrderInput)  │ ─────────────►
                  │                                    │  PaymentAuthorizationAsked
   PaymentAuthorized                                   │ ─────────────►   ← read by subscription
   ────────────►                                       │  PaymentTimerScheduled
                  │                                    │ ─────────────►   ← read by timer service
   InventoryReserved                                   │  …
   ────────────►                                       │
                  └───────────────────────────────────┘
                                ▲
                                │
              event store + queue + subscriptions
              (the runtime described in fst-as-workflow-runtime.md)
```

Each arrow into the PM is a subscription that reads an event from
*another* aggregate's stream and routes it as an `OrderInput`. The
routing is `lmapMaybeC` from `future-directions.md` §1: a function from
the wider event universe to `Maybe OrderInput`. If it returns
`Nothing`, the event isn't relevant to this PM.

```haskell
routePaymentToOrder :: PaymentEvent -> Maybe OrderInput
routePaymentToOrder = \case
  Payment.Authorized d -> Just (PaymentAuthorized (PaymentAuthorizedData d.paymentRef))
  Payment.Declined   d -> Just (PaymentDeclined   (PaymentDeclinedData  d.paymentRef d.reason))
  Payment.Refunded   d -> Just (RefundCompleted   (RefundCompletedData  d.paymentRef))
  _                    -> Nothing
```

Each arrow out of the PM (an `OrderOutput` written to the order's
event stream) is read by another subscription that translates it into
a command to dispatch:

```haskell
dispatchPaymentRequests :: OrderOutput -> IO ()
dispatchPaymentRequests = \case
  PaymentAuthorizationAsked d ->
    sendCommand paymentAggregate
      (Payment.Authorize (Payment.AuthorizeData d.orderId d.totalCents))
  PaymentRefundAsked d ->
    sendCommand paymentAggregate
      (Payment.Refund (Payment.RefundData d.paymentRef))
  _ -> pure ()
```

The PM never calls another aggregate directly. It emits events.
Subscriptions (one per integration) translate those events into
commands. The wiring is data; the PM stays pure.

### Timer

`PaymentTimerScheduled` is an output event consumed by the timer
service, which schedules a delayed queue message. When the queue
delivers it later, it arrives as the `PaymentDeadlineExpired` input.
Inside the PM, the timer is just two more entries in the alphabet —
the timer service is a subscription, not part of the formalism.

If payment authorizes before the timer fires, the PM has already
moved to `ReservingInventory`. The `PaymentDeadlineExpired` input has
no edge in `ReservingInventory`, so it returns `Nothing` — the
runtime acknowledges and discards it. No special cancellation
machinery needed; partiality handles it.

### What the PM gives us that an aggregate doesn't

Same formalism, but:

- **Inputs are aggregated from many sources.** The boundary layer
  routes events from multiple bounded contexts. The PM sees a unified
  alphabet.
- **Outputs are dispatched to many sources.** The PM doesn't know
  about Payment, Inventory, or Shipping. It emits events; the
  subscriptions translate.
- **Compensation is just more transitions.** No special saga
  machinery; the `Compensating` vertex is an ordinary control state
  with edges for each outstanding compensation step.
- **Timers are alphabet members.** Scheduled by output events,
  delivered as input commands.

### Reconstitution

The PM's event stream is its own (separate from Payment's, Inventory's,
Shipping's). On crash:

```
1. OrderAccepted              { orderId="ord-42" }
2. PaymentAuthorizationAsked  { orderId="ord-42", totalCents=4999 }
3. PaymentTimerScheduled      { orderId="ord-42", deadline=2026-05-01T10:00:00Z }
4. InventoryReservationAsked  { orderId="ord-42", lineItems=[…] }
5. ShipmentCreationAsked      { orderId="ord-42", shippingAddr=…, lineItems=[…] }
6. OrderCompletedE            { orderId="ord-42" }
```

The PM's event stream is the record of what *it decided*, not what
other aggregates told it. Cross-context information (payment
authorization succeeded, the ref is X) enters the PM's register file
when the PM consumes the foreign input event — but it only survives
replay if the PM also writes that information into one of its own
output events.

### Same hidden-input lesson, again

Look at the `AwaitingPayment + PaymentAuthorized` edge:

```
update = Set #paymentRef (\(PaymentAuthorized d) -> Just d.paymentRef)
output = InventoryReservationAsked { orderId, lineItems }   -- no paymentRef
```

The update writes `paymentRef` into the register file. The output
event doesn't carry it. On replay, `solveOutput` for
`InventoryReservationAsked` cannot recover the input `d.paymentRef`,
so the register file's `paymentRef` slot stays `Nothing` for the rest
of replay. The downstream `PaymentRefundAsked` edge in
`Compensating` reads `fromJust (regs ! #paymentRef)` and crashes —
silently wrong replayed state, then a runtime error.

**This is the same hidden-input bug the User Registration walkthrough
surfaced**, in a different shape. The build-time check would flag the
edge: *"update writes register `paymentRef` from input field
`PaymentAuthorized.paymentRef`, but no outgoing event carries that
field — replay cannot recover it."*

Three clean fixes:

1. **Echo the ref in the dispatched event.** Add `paymentRef ::
   PaymentRef` to `InventoryReservationAskedData`. Inventory ignores
   it; the PM's replay recovers it. Most defensible.
2. **Split the edge** (state-refinement, mirroring the User
   Registration `Registering` intermediate). Add an intermediate
   `PaymentRecorded` vertex; the first edge writes a
   `PaymentAuthorizationRecorded { orderId, paymentRef }` event
   (PM-internal, not dispatched anywhere) and moves to
   `PaymentRecorded`; an internal `Continue` then dispatches
   `InventoryReservationAsked`.
3. **Don't track the ref in the PM's register file at all.** Re-fetch
   it from the Payment aggregate when needed for compensation. Loosens
   the PM but keeps its event stream minimal.

The lesson is the same as the aggregate example: the symbolic-register
encoding makes "this register write is unrecoverable on replay" a
build-time question, not a 3am question.

---

## 6. Composition

The two transducers compose mechanically when their alphabets line up,
but in practice **you don't compose them at the formal level for
runtime** — you run them separately, route events between them via the
event store and queue, and use `compose` only for *analysis*:

- "Does the PM's `PaymentAuthorizationAsked` output match what the
  Payment aggregate accepts as input?" — express the routing as
  `lmapMaybeC`, then check that the *output language of the routed PM*
  is included in the *input language of the Payment aggregate*. This is
  language inclusion, which is undecidable in general for symbolic
  transducers — but for the single-valued, finite-control aggregates we
  actually write, it reduces to checking the predicate over a finite
  product graph. Decidable in practice for the fragments we live in.

- "Are these two refactorings of the User Registration aggregate
  observationally equivalent?" — symbolic equivalence within the
  single-valued fragment. Decidable per Veanes (2012).

The runtime architecture (event store + queue + subscriptions from
`fst-as-workflow-runtime.md` §2–§5) is unchanged. The formalism just
upgrades.

---

## 7. Settling the open questions

### From C

- **Predicate carrier in v1: first-class AST (option b).** Even without
  SMT in v1, the AST gives visualization, structural diff, and the
  hidden-input / non-injective-output checks something to chew on.
  Translating an AST to SMT in v2 is mechanical. Translating arbitrary
  Haskell predicates to SMT later is not. This is the better long-term
  shape.

- **Single-valuedness: property test in v1, smart-constructor enforcement
  in v2.** A general overlap check needs SMT. For v1, ship a Hedgehog
  property over the user's generators and document that single-valuedness
  is the user's contract. When SMT lands, the smart constructor takes
  over.

### From B

- **Singletons, vertex kind boilerplate.** Only relevant once a user
  opts into a B-view. The `genView` TH helper now ships as
  `Keiki.Generics.TH.deriveView` (EP-13 / MP-5); a per-aggregate
  invocation generates the singletons GADT, the View GADT, and the
  projection function from a `[(vertexCtor, [slot])]` spec. Worked
  example on `Jitsurei.UserRegistration`.

---

## 8. Sequenced next steps

1. **Type sketch.** Flesh out `RegFile rs`, `Index rs r`, `Term`,
   `OutTerm`, `Update`, `Edge`, `SymTransducer`, and `BoolAlg phi a`
   into a single Haskell module sketch. Decide concretely whether the
   register file is hand-rolled GADT or `vinyl`. Resolve the ergonomic
   surface for `matchCmd`/`mkOut`/`proj`.

2. **Build the User Registration aggregate end-to-end as the smoke
   test.** No wire types, no event store — just the type, the event
   list, and `reconstitute`. Validate the mechanical `apply` derivation
   with the hidden-input check actually firing on the unfixed event
   schema.

3. **Add the runtime loop from `fst-as-workflow-runtime.md` §5** with
   an in-memory event store and an in-memory queue. Run a single
   `orderPM` instance through the happy path and a compensation path.

4. **Write the v2 SBV-backed `BoolAlg` instance** with a curated
   predicate fragment. Wire up symbolic deadlock checking and symbolic
   equivalence as separate analyzers.

5. **Indexed-state views (B) as a separate library module.** Optional,
   used by users who want per-vertex records. No coupling to the core.

The headline of this plan is that **none of the existing research notes
need to be rewritten**. The `Transducer` they describe becomes the
`SymTransducer` with `rs = '[]`, every `Update` `Keep`, every guard a
single-input-equality. State refinement is the canonical multi-event
model (see EP-20 / MasterPlan 7): the AST stays a strict letter FST,
and the library ships ergonomic support — `Keiki.Core.applyEvents` for
chunk replay, `Keiki.Decider.toMultiDecider` (with `DriverConfig`) for
transparent driver chains through user-declared internal vertices, and
`Keiki.Builder.chainTo` for syntactic compression of multi-event
authoring — so callers can drive multi-event chains end-to-end without
observing the intermediate vertices. The workflow runtime document's
runtime loop is unchanged. What changes is that data flow becomes a
first-class part of the formalism, not a graft, and `apply` returns to
being derivable.
