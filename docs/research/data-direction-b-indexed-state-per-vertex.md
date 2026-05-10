# Direction B: Indexed State, Data Per Vertex

The `ExtTransducer s ctx c e` from `docs/historical/fst-as-workflow-runtime.md` §1 grafts a
single uniform `ctx` onto a finite control state. That works when every
control vertex carries the same data shape. It breaks the moment two
vertices want different fields:

```haskell
-- Pending  carries: submittedDoc, requiredCount
-- Awaiting carries: approvedBy, rejectedBy, requiredCount, submittedDoc
-- Approved carries: finalApprovers, completedAt
```

Three escape hatches, all bad:

1. Union the fields into one record, accept that `Pending`'s
   `approvedBy` is meaningless. Lose the type system.
2. Make every field `Maybe`. Pattern matching becomes a soup of
   `fromJust` and "this can't happen here" comments.
3. Make `ctx` a sum type `PendingCtx | AwaitingCtx | ApprovedCtx`.
   Every site that touches `ctx` re-pattern-matches on the tag — and
   the relationship between control state `s` and which `ctx`
   constructor is live becomes a runtime invariant the compiler
   doesn't enforce.

Direction B says: **make the control vertex a type-level index, and
let the data type carried by a state be a function of that index.**
`State 'Pending` and `State 'Awaiting` are different types with
different fields. The compiler knows which fields exist where.

---

## 1. The Type

The vertex is a kind, lifted from a sum via `DataKinds`. The state is
a GADT indexed by it. The transducer is parameterised by the *family*
of states (one type-level kind), not by a single state type.

```haskell
{-# LANGUAGE DataKinds, KindSignatures, GADTs, StandaloneKindSignatures #-}
{-# LANGUAGE TypeFamilies, RankNTypes, ScopedTypeVariables #-}

-- The control vertex — a finite enumeration, lifted to the type level.
data Vertex
  = Pending
  | Awaiting
  | Approved
  | Rejected

-- The data carried by each control vertex. A GADT, so each
-- constructor names its vertex and brings its own fields.
data State (v :: Vertex) where
  PendingS   :: { docId         :: DocumentId
                , requiredCount :: Int
                } -> State 'Pending

  AwaitingS  :: { awDocId       :: DocumentId
                , awRequired    :: Int
                , approvedBy    :: Set UserId
                , rejectedBy    :: Set UserId
                } -> State 'Awaiting

  ApprovedS  :: { apDocId       :: DocumentId
                , apApprovers   :: Set UserId
                , apAt          :: UTCTime
                } -> State 'Approved

  RejectedS  :: { reDocId       :: DocumentId
                , reReason      :: Text
                } -> State 'Rejected
```

`State 'Pending` has exactly two fields. `State 'Awaiting` has four.
Mixing them is a type error. No `Maybe`s, no "this constructor never
fires here" comments.

For "the current state, but I don't know which vertex":

```haskell
-- Existential wrapper. Carries a singleton so we can pattern match
-- on the vertex at runtime when we need to.
data SomeState where
  SomeState :: SVertex v -> State v -> SomeState

-- Singleton for Vertex. Either hand-written or via the `singletons`
-- library. Hand-rolled is ~10 lines and carries no dep.
data SVertex (v :: Vertex) where
  SPending   :: SVertex 'Pending
  SAwaiting  :: SVertex 'Awaiting
  SApproved  :: SVertex 'Approved
  SRejected  :: SVertex 'Rejected
```

I'd hand-roll the singleton — `singletons` is a big TH dep for what
amounts to one `data` declaration per workflow. The
`Data.Singletons.TH` `genSingletons ['Vertex]` shortcut is nice if you
already pay for it elsewhere; otherwise skip.

The `Transducer` itself becomes:

```haskell
data Transducer (v0 :: Vertex) c e = Transducer
  { delta   :: forall v. SVertex v -> State v -> c -> Maybe SomeState
  , omega   :: forall v. SVertex v -> State v -> c -> Maybe e
  , initial :: State v0
  , isFinal :: forall v. SVertex v -> Bool
  }
```

The transducer is parameterised by the *initial* vertex `v0`. `delta`
takes a state at *some* vertex and returns a state at *some* (possibly
different) vertex — that's `SomeState`. `omega` is unchanged in
shape. `isFinal` is a property of the vertex alone (not the data), so
it takes the singleton.

The `SVertex v` argument to `delta`/`omega` is technically redundant —
the GADT constructor in `State v` already determines `v` — but
threading it explicitly makes pattern matching cleaner and avoids
needing `Typeable` constraints to recover the vertex.

Concrete `delta` clause:

```haskell
delta SPending (PendingS d n) (StartReview d' n')
  | d == d'   = Just $ SomeState SAwaiting
                  (AwaitingS d n Set.empty Set.empty)
  | otherwise = Nothing

delta SAwaiting (AwaitingS d n approved rejected) (SubmitApproval uid)
  | uid `Set.member` approved = Nothing
  | Set.size approved + 1 >= n =
      Just $ SomeState SApproved
        (ApprovedS d (Set.insert uid approved) <currentTime>)
  | otherwise =
      Just $ SomeState SAwaiting
        (AwaitingS d n (Set.insert uid approved) rejected)

delta SApproved _ _ = Nothing  -- terminal
delta SRejected _ _ = Nothing
```

Note: `<currentTime>` is a problem — pure `delta` can't fetch
wall-clock. This is one of the open tensions; see §7.

---

## 2. Events and Commands

The trade-off is real and it cuts both ways. Two encodings:

### 2a. Flat sums with payloads

Commands and events stay as ordinary sum types whose constructors
carry data:

```haskell
data Cmd
  = StartReview DocumentId Int
  | SubmitApproval UserId
  | SubmitRejection UserId Text
  | Escalate UserId

data Event
  = ReviewStarted DocumentId Int
  | ApprovalRecorded UserId
  | RejectionRecorded UserId Text
  | ThresholdReached UserId UTCTime
  | EscalationGranted UserId
```

Pros:
- `Eq`, `Show`, `Generic`, JSON instances are trivial.
- `delta`/`omega` consume `c` uniformly; the `case (s, c) of`
  pattern from the existing docs still works.
- Reconstitution from a `[Event]` list is straightforward.

Cons:
- The compiler doesn't enforce "`SubmitApproval` only makes sense in
  `'Awaiting`." You discover that at runtime via `Nothing`.
- We've moved the data into sum constructors but the *correlation
  between command and vertex* is still a runtime invariant.

### 2b. Indexed commands and events

```haskell
data Cmd (v :: Vertex) where
  StartReviewC      :: DocumentId -> Int -> Cmd 'Pending
  SubmitApprovalC   :: UserId -> Cmd 'Awaiting
  SubmitRejectionC  :: UserId -> Text -> Cmd 'Awaiting
  EscalateC         :: UserId -> Cmd 'Awaiting

data Event (v :: Vertex) where
  ReviewStartedE     :: DocumentId -> Int -> Event 'Pending
  ApprovalRecordedE  :: UserId -> Event 'Awaiting
  ...
```

Now `delta`'s type can be sharper:

```haskell
delta :: forall v. SVertex v -> State v -> Cmd v -> Maybe SomeState
```

The compiler enforces that you can't even *call* `delta` with a
`StartReviewC` on an `'Awaiting` state. The dispatch layer must
classify the incoming command's vertex before invoking `delta`.

Cons:
- Existential wrappers everywhere at the boundary: `SomeCmd`,
  `SomeEvent`, decoded from JSON.
- Folding events for reconstitution gets harder — see §6.
- The cross product `(state vertex, command vertex)` collapses to
  diagonal cases only; you've lost the ability to express "this
  command in this state is invalid" as a value-level `Nothing` because
  you ruled it out at the type level. That's a feature for invariants,
  but it forces the *router* to do the partiality work that `delta`
  used to do.

**Recommendation: 2a, with an optional escape hatch.**

Indexed commands look elegant but they fight the wire. Commands enter
the system from JSON / queue messages; events leave to a store. Both
boundaries lose the type index immediately. The cost of indexed
commands is paid every time you decode, route, or persist; the benefit
shows up only in `delta`'s signature.

The state being indexed is genuinely worth it because state lives
*inside* the runtime — it's never serialised as a typed value, only as
events. Commands and events are wire types; state is a runtime type.
Index what stays inside, leave wire types flat.

(Direction A or C may revisit this; this note is scoped to B.)

---

## 3. The `apply` Story

This is the central question. With per-vertex data, can `apply` still
be derived mechanically from the transducer?

The flat-state derivation was:

```
apply :: s -> e -> Maybe s
apply s e = listToMaybe
  [ s' | c <- [minBound..maxBound]
       , Just e' <- [omega t s c], e' == e
       , Just s' <- [delta t s c]
       ]
```

That recipe needs `(Enum c, Bounded c)` and `Eq e`. Two things break
in the indexed world:

1. **Commands carry data.** `StartReview docId n` is no longer
   enumerable — `docId` is a `UUID`. We can't `[minBound..maxBound]`
   over `Cmd`. This is the same issue ExtTransducer hit; it's not new
   to indexed state, but it's still here.

2. **State carries data, and `apply` must reconstruct it.** If the
   event is `ApprovalRecorded uid`, then `apply (AwaitingS d n a r)
   (ApprovalRecorded uid)` must produce `AwaitingS d n (Set.insert uid
   a) r`. The event payload (`uid`) plus the prior state determine
   the new state's data, but there is no `omega⁻¹` shortcut: we're
   not enumerating commands and looking for matches, we're *running
   the data update logic* of the transition.

So no, `apply` cannot be mechanically derived. The user must provide
it. This is the same situation as `ExtTransducer` — and the contract
the user must uphold is the indexed analog of event-determinism:

```haskell
-- For every (vertex v, state s : State v, command c) such that
-- delta v s c = Just (SomeState v' s'),
-- and omega v s c = Just e,
-- the user-provided apply must satisfy:
--
--    apply v s e == Just (SomeState v' s')

apply :: forall v. SVertex v -> State v -> Event -> Maybe SomeState
```

The signature mirrors `delta` but consumes an `Event` instead of a
`Cmd`. Crucially the *result* is `SomeState` because applying an event
to a `'Pending` state may legitimately move us to `'Awaiting`.

The user writes `apply` by case-analysing `(SVertex, State v, Event)`:

```haskell
apply SPending (PendingS d n) (ReviewStarted d' n')
  | d == d' && n == n' = Just $ SomeState SAwaiting
                           (AwaitingS d n Set.empty Set.empty)
  | otherwise          = Nothing

apply SAwaiting s@(AwaitingS d n a r) (ApprovalRecorded uid) =
  let a' = Set.insert uid a
  in if Set.size a' >= n
       then Nothing  -- this event should have been ThresholdReached
       else Just $ SomeState SAwaiting (AwaitingS d n a' r)

apply SAwaiting (AwaitingS d n a r) (ThresholdReached uid t) =
  Just $ SomeState SApproved
    (ApprovedS d (Set.insert uid a) t)

apply _ _ _ = Nothing
```

The contract under indexed state:

> For every `(v, s :: State v, c)` where `delta sV s c = Just (SomeState vV' s')`
> and `omega sV s c = Just e`:
> `apply sV s e` must equal `Just (SomeState vV' s')` *up to whatever
> equality you can express on `SomeState`* — see §8 for the catch.

The catch is that we need an `Eq` instance on `SomeState`, which means
either deriving it via `forall v. Eq (State v)` and a singleton
comparison, or writing it by hand. Neither is hard, but it's not free.

Property test, written for a single vertex:

```haskell
prop_eventDeterminism_Awaiting :: Property
prop_eventDeterminism_Awaiting = property $ do
  s <- forAll genAwaitingState
  c <- forAll genAwaitingCmd
  case (delta t SAwaiting s c, omega t SAwaiting s c) of
    (Just s', Just e) ->
      apply SAwaiting s e === Just s'
    _ -> discard
```

You write one prop per vertex (or one parameterised over `SVertex` if
you can be bothered with `SomeState` generators). With small finite
vertices this is fine.

---

## 4. Projections

Input projection (Acceptor over commands) and output projection
(Acceptor over events) both still exist, but they project out the
data dimension.

```haskell
data Acceptor (v0 :: Vertex) a = Acceptor
  { aTransition :: forall v. SVertex v -> State v -> a -> Maybe SomeState
  , aInitial    :: State v0
  , aIsFinal    :: forall v. SVertex v -> Bool
  }

inputProjection :: Transducer v0 c e -> Acceptor v0 c
inputProjection t = Acceptor
  { aTransition = delta t
  , aInitial    = initial t
  , aIsFinal    = isFinal t
  }
```

The acceptor's "language" is now: sequences of commands carrying
arbitrary payloads such that the resulting walk through the *vertex
graph* (projecting away the data) reaches a final vertex. The data
has not been projected away — it's still flowing through, because
`delta` consumes it — but the *acceptance criterion* depends only on
the vertex.

For output projection, the same trick works using user-provided
`apply`:

```haskell
outputProjection :: Transducer v0 c e -> (forall v. SVertex v -> State v -> Event -> Maybe SomeState) -> Acceptor v0 Event
outputProjection t userApply = Acceptor
  { aTransition = userApply
  , aInitial    = initial t
  , aIsFinal    = isFinal t
  }
```

The "language of valid event sequences" is well-defined: any sequence
of events that, fed through `apply`, doesn't return `Nothing` at any
step.

What we *don't* get for free: derived `outputProjection` without a
user-provided `apply`. Same as ExtTransducer. The user pays once.

---

## 5. Composition

The flat composition was:

```haskell
compose :: Transducer s1 c e1 -> Transducer s2 e1 e2 -> Transducer (s1, s2) c e2
```

Indexed: each transducer has its own vertex kind. The product
transducer's vertex is the pairwise product:

```haskell
data ProductVertex v1 v2 = ProductVertex v1 v2

data ProductState (pv :: ProductVertex v1 v2) where
  ProductS :: State1 a -> State2 b -> ProductState ('ProductVertex a b)
```

…except that's not legal Haskell directly — `ProductVertex v1 v2` has
the wrong kind to be promoted that way without
`PolyKinds`. The cleaner formulation:

```haskell
{-# LANGUAGE PolyKinds, TypeOperators #-}

-- A product vertex pairs vertices from two different families.
data PV a b = PV a b

-- The state at a product vertex is a pair of states, one at each component.
data ProductState (s1 :: k1 -> Type) (s2 :: k2 -> Type) (pv :: PV k1 k2) where
  PS :: s1 a -> s2 b -> ProductState s1 s2 ('PV a b)
```

Then:

```haskell
compose
  :: Transducer (v0 :: k1) c e1
  -> Transducer (w0 :: k2) e1 e2
  -> ComposedTransducer (PV k1 k2) ('PV v0 w0) c e2
```

The seam: `omega` of `T1` returns a flat `Maybe e1` (events are
flat per §2), which feeds `delta`/`omega` of `T2`. Data flows through
because `e1` carries its payload as an ordinary value. The product
state's data is just the pair of the two component datas.

Concretely the step is:

```haskell
deltaP :: SVertex ('PV v w) -> ProductState s1 s2 ('PV v w) -> c -> Maybe SomeProductState
deltaP (SPV svV swV) (PS s1 s2) c =
  case (delta t1 svV s1 c, omega t1 svV s1 c) of
    (Just (SomeState svV' s1'), Just e1) ->
      case delta t2 swV s2 e1 of
        Just (SomeState swV' s2') ->
          Just $ SomeProductState (SPV svV' swV') (PS s1' s2')
        Nothing -> Nothing
    (Just (SomeState svV' s1'), Nothing) ->
      Just $ SomeProductState (SPV svV' swV) (PS s1' s2)  -- ε from T1
    (Nothing, _) -> Nothing
```

The `SPV` singleton tracks both component vertices. `SomeProductState`
is the existential at the product level.

Honest assessment: the *type* of `compose` is hairier than the flat
case, but the *implementation* is line-for-line the same as the flat
version. The pain is in the signatures and the wrapper types
(`SomeProductState`, `SPV`), not in the logic. If we provide them as
library types once, downstream users compose without seeing the
internals.

One genuine new question: composition assumes `T2`'s input alphabet is
`T1`'s output alphabet. With flat events this is just type equality.
There's no new wrinkle from indexed *state* (since events stayed
flat). Indexed events would force the seam to existentialise — that's
why §2 recommended flat events.

---

## 6. Reconstitution

```haskell
reconstitute :: Transducer v0 c e -> [Event] -> Maybe SomeState
reconstitute t events =
  foldlM step (SomeState (singletonOf (initial t)) (initial t)) events
  where
    step (SomeState sv s) e = userApply sv s e
```

`foldlM` over `Maybe`: if any step returns `Nothing`, the whole replay
fails. The key signature point: the return is `Maybe SomeState`, not
`Maybe (State v)` for any specific `v`, because we cannot know
statically which vertex the event sequence terminates in.

To *use* the returned state at a known vertex, the caller pattern
matches:

```haskell
case reconstitute t events of
  Just (SomeState SApproved s@(ApprovedS{})) ->
    -- type-refined here: s :: State 'Approved
    "approved by " <> show (apApprovers s)
  Just (SomeState SAwaiting s@(AwaitingS{})) ->
    "still waiting"
  Just _ -> "other"
  Nothing -> "corrupt history"
```

The pattern match on the singleton refines the type of `s`. This is
the standard GADT-existential dance and it's the price of admission.

Helper `withState`:

```haskell
withState :: SomeState -> (forall v. SVertex v -> State v -> r) -> r
withState (SomeState sv s) k = k sv s
```

…lets callers continuation-pass when they don't want to inline the
match.

A subtle point on reconstitution: `singletonOf (initial t)` requires
that we can produce an `SVertex v0` from `initial t :: State v0`. The
cleanest way is to add a typeclass:

```haskell
class KnownVertex (v :: Vertex) where
  vertexSing :: SVertex v

instance KnownVertex 'Pending   where vertexSing = SPending
instance KnownVertex 'Awaiting  where vertexSing = SAwaiting
instance KnownVertex 'Approved  where vertexSing = SApproved
instance KnownVertex 'Rejected  where vertexSing = SRejected

-- Then Transducer requires KnownVertex v0 implicitly via initial:
initial :: KnownVertex v0 => State v0
```

…or just store the singleton alongside the initial state in the
transducer record. Either works.

---

## 7. Ergonomics

Honest accounting versus `ExtTransducer s ctx c e`:

**What gets harder.**

- Pattern matching is heavier. `case s of` becomes `case (sv, s) of`
  with GADT refinement. The compiler often needs explicit signatures
  to figure out impossibility.
- Error messages around GADT inference are notoriously bad. A wrong
  vertex tag produces "couldn't match `'Awaiting` with `'Pending`"
  several frames removed from the actual mistake.
- Existential wrappers (`SomeState`, `SomeProductState`) appear in
  signatures and force callers to pattern match before they can use
  the data.
- Effectful step functions need to thread the singleton:
  `step :: forall v. SVertex v -> State v -> c -> m (Maybe SomeState)`
  is a `forall`-quantified field, which fights `EffTransducer m c e`'s
  existential-state encoding from `docs/historical/future-directions-profunctors-effects-and-composition.md` §6. Combining
  Direction B with the coalgebraic encoding needs care.
- Pure `delta` cannot read the clock for `ApprovedS apAt`. Either
  events carry the timestamp (clock lives at the boundary that emits
  the event), or `delta` becomes effectful (Direction-B-plus-§6).
- `Enum`/`Bounded` on state is gone — see §8.

**What gets easier.**

- The fields a vertex carries are exactly the fields it needs. No
  `Maybe`. No "this is `Nothing` whenever `s == Pending`" comments.
- Refactoring is robust. Add a field to `AwaitingS` and the compiler
  flags every site that constructs an `AwaitingS`. Under uniform
  `ctx` you'd silently default the new field.
- Vertex–data correlation is enforced. You cannot accidentally read
  `approvedBy` while in `'Pending`.
- Documentation reads itself: the GADT IS the spec.

**When indexed is worth it.**

Use indexed state when:
1. Two or more vertices carry genuinely different fields, AND
2. The fields are non-trivial (not just one or two values), OR
3. You're shipping the type to a domain expert who reads it as a
   spec.

Stick with `ExtTransducer s ctx c e` (uniform context) when:
1. All vertices share the same data shape, OR
2. The differences are small and `Maybe` accurately models "absent
   in this state," OR
3. The workflow is going to be regenerated/rewritten frequently
   enough that the GADT refactoring tax exceeds the safety win.

The Multi-Approval workflow from `docs/historical/fst-as-workflow-runtime.md` is on
the boundary. `Pending` carries `(docId, requiredCount)`; `Awaiting`
adds `approvedBy, rejectedBy`; `Approved` and `Rejected` shed
collections and add finalisation data. Four vertices, four genuinely
different shapes, but small. Indexed is justified — barely.

The User Registration aggregate is *not* on the boundary in the other
direction: `PotentialCustomer` has nothing, `RequiresConfirmation`
has an email, `Confirmed` has email + confirmation timestamp,
`Deleted` has a deletion timestamp. Four vertices, four different
shapes. Indexed is clearly the right call.

---

## 8. What This Rules Out

Things that work in flat-state `Transducer s c e` and *don't* in the
indexed encoding:

**`Enum`/`Bounded` on the whole state type.** Gone. There is no
"`State`" type — there's a family of types `State 'Pending`,
`State 'Awaiting`, etc., one per vertex, each carrying arbitrary data.
You can still enumerate the *vertex* (`Vertex` is `Enum, Bounded` by
deriving), but not states.

Consequence: the `outputProjection` derivation that used
`[minBound..maxBound]` over commands AND states no longer applies to
states. Some library functions that used `forall s. Enum s, Bounded s`
need to be reformulated as `forall v. (KnownVertex v) => SVertex v ->
...` and called per-vertex.

**Exhaustive `(state, command)` property tests.** The flat
formulation:

```haskell
forall s c. case (delta s c, exec s c) of ...
```

becomes a per-vertex enumeration:

```haskell
forall v. forall (s :: State v). forall c. ...
```

with `s` generated by a hand-written `genState v` per vertex (since
data fields can be arbitrary). You lose "1 line check, 16 cases"; you
gain "16 lines, ∞ cases per vertex via random data." The control
graph is still finite and enumerable; the *data* has to be sampled.

**Simple structural `Eq` for graph analysis.** Functions like
"deadlock detection: are there states with no outgoing transitions?"
need to reason about the vertex graph, not the state graph. With
indexed state, two values of `State 'Awaiting` differing only in their
`approvedBy` set are observationally different but vertex-equivalent.
For graph analysis we project to the vertex:

```haskell
data VertexEdge = VertexEdge Vertex Vertex
deadlocks :: Transducer v0 c e -> [Vertex]
```

This works fine — the vertex is finite — but you can no longer ask
"is state `s` reachable from state `s'`" in the literal sense, only
"is vertex `v` reachable from vertex `v'`." The data dimension is
unbounded.

**Visualisation.** `toDot` from `docs/historical/future-directions-profunctors-effects-and-composition.md` §5 enumerates
`[minBound..maxBound]` over states and commands. Under Direction B,
`toDot` shows only the vertex graph; data updates are annotations,
not separate nodes. This is arguably *better* (state explosion
avoided) but it's a different artifact.

**Trivial `fmap`/`contramap` on state.** Because state doesn't appear
as a top-level type parameter on `Transducer` anymore (the kind
`Vertex` does, and the data is wired in via the GADT), there's no
`mapState` operation in the obvious sense. You'd have to provide a
per-vertex transformation `forall v. State v -> State' v`, which is
either trivial (all vertices the same) or genuinely needs per-vertex
logic.

---

## Open Questions

Two I couldn't adjudicate from the existing notes alone:

1. **Singletons: hand-rolled or `singletons` library?** The library
   pulls in TH and a non-trivial dep tree. Hand-rolling is ~10 lines
   per workflow. For a pure-core library, hand-rolling seems right;
   for an ergonomic API where users define their own workflows,
   `singletons-th` may be worth the dep. This is a packaging/policy
   call.

2. **Should the `Vertex` kind be open (per-workflow `data Vertex =
   ...`) or closed (a library-provided GADT extended via
   type-families)?** Per-workflow is straightforward but means every
   workflow defines its own `SVertex`, `KnownVertex`, etc. — that's
   ~20 lines of boilerplate per workflow. A library macro / TH
   splice could generate it. Or: accept the boilerplate as the cost
   of admission, since it makes errors clearer. I lean toward
   per-workflow + a `genWorkflowSingletons` TH helper, but the user
   may have a strong opinion on TH avoidance.
