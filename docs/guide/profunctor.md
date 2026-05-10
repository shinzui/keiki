# Profunctor wrappers and variance combinators

How to reshape a transducer's input or output alphabet without
rebuilding it. `Keiki.Profunctor` exports an existential wrapper
plus four small combinators that contramap commands, covariant-map
events, dimap both, or filter incoming commands. They are the
tools you reach for when **the transducer is fine, but the alphabet
needs to change at the boundary**.

This guide assumes you've read `user-guide.md` and at least
skimmed `composition.md`. For the design rationale and the
variance discussion that drove the choices, see
`docs/plans/27-existential-wrapper-for-symtransducer-plus-profunctor-instance-and-variance-combinators.md`
and `docs/masterplans/9-profunctor-and-category-instances-on-symtransducer.md`.

---

## 0. When to reach for this module

| If your shape is… | Use | Why |
|---|---|---|
| One service receives a wide command sum, and you want to dispatch a slice of it to a specific aggregate | `lmapMaybeCi router` | Pre-filters: commands that don't match the slice fail every guard at the boundary; nothing else fires. |
| A new event-schema version (`EventV2`) ships and you need to upcast the existing aggregate's `EventV1` to it on the wire | `rmapCo upcast` | Post-composes: forward emissions are upcasted before crossing the runtime boundary; aggregate code is untouched. |
| You want to plug a keiki transducer into ecosystem code that expects `Data.Profunctor.Profunctor` (lens optics, free-arrow DSLs, generic plumbing) | `someSymTransducer` then `dimap` / `lmap` / `rmap` | The wrapper hides `rs` and `s`, exposing the standard `Profunctor` shape. |
| A keiki transducer needs both a command rename and an event rename in one step | `dimapTransducer fIn fOut` (or `dimap` on the wrapper) | Equivalent to `rmapCo fOut . lmapCi fIn`; documented as the one-shot helper. |
| You want to compose two aggregates whose alphabets *almost* match, but one has a wrapper newtype | `lmapCi unwrap` or `rmapCo wrap` on the offending side, *then* `compose` | The wrapper rewrites the AST so the natural-alphabet `compose` typechecks. |

What this module is **not** for:

- *Two aggregates running in parallel or sequentially.* That's
  `compose` / `alternative` / `feedback1` from `Keiki.Composition`.
  This module reshapes one transducer; it doesn't combine two.
- *Effectful (IO/Reader/State) wrapping.* Effects live at the
  runtime boundary; the wrapper is pure.
- *Replay-from-events on a rewritten transducer.* `lmapCi` /
  `rmapCo` / `dimapTransducer` lose `solveOutput`'s round-trip on
  the rewritten edges. See §3 below for the precise contract.

---

## 1. The wrapper

```haskell
data SomeSymTransducer ci co where
  SomeSymTransducer
    :: SymTransducer (HsPred rs ci) rs s ci co
    -> SomeSymTransducer ci co

someSymTransducer
  :: SymTransducer (HsPred rs ci) rs s ci co
  -> SomeSymTransducer ci co
someSymTransducer = SomeSymTransducer
```

`SomeSymTransducer ci co` hides the register-file slot list `rs`
and the control vertex `s`, exposing only the input and output
alphabets. The predicate carrier is fixed to `HsPred` because
`Keiki.Composition`'s combinators are pinned to that carrier.

You wrap a concrete transducer with `someSymTransducer`. You
unwrap by pattern-matching on the constructor — but the inner
`rs` and `s` are skolem types and **may not escape the pattern
match** (so you can't return them from a `let` binding outside
the case expression). In practice you do whatever you need with
the inner transducer inside the case branch.

```haskell
case someThing of
  SomeSymTransducer t ->
    print (length (edgesOut t (initial t)))   -- fine
```

The wrapper's `Profunctor` and `Functor` instances let you write
the standard ecosystem combinators:

```haskell
import Data.Profunctor (dimap, lmap, rmap)

-- Dimap: rename both sides at once.
adapted :: SomeSymTransducer NewCmd NewEvent
adapted = dimap newToOld oldToNew (someSymTransducer aggregate)

-- Just rename the output:
v2 :: SomeSymTransducer EmailCmd EmailEventV2
v2 = rmap upcastV1ToV2 (someSymTransducer emailDelivery)

-- Functor over `co`:
v2 = fmap upcastV1ToV2 (someSymTransducer emailDelivery)
```

---

## 2. The four standalone combinators

The wrapper instances delegate to four standalone combinators
that work on the **concrete** `SymTransducer` type. Use the
standalone form when you want to keep `rs` and `s` visible — for
example, when you'll feed the result into `compose` afterward.

```haskell
lmapCi
  :: (ci' -> ci)
  -> SymTransducer (HsPred rs ci)  rs s ci  co
  -> SymTransducer (HsPred rs ci') rs s ci' co

lmapMaybeCi
  :: (ci' -> Maybe ci)
  -> SymTransducer (HsPred rs ci)  rs s ci  co
  -> SymTransducer (HsPred rs ci') rs s ci' co

rmapCo
  :: (co -> co')
  -> SymTransducer (HsPred rs ci) rs s ci co
  -> SymTransducer (HsPred rs ci) rs s ci co'

dimapTransducer
  :: (ci' -> ci)
  -> (co  -> co')
  -> SymTransducer (HsPred rs ci)  rs s ci  co
  -> SymTransducer (HsPred rs ci') rs s ci' co'
```

Internally, each of these walks the closed AST of every edge in
the transducer (`HsPred`, `Term`, `Update`, `OutTerm`, `OutFields`,
`InCtor`, `WireCtor`) and threads the contramap or covariant map
through every position the type parameter occupies. The result
is a new `SymTransducer` value with the same number of edges,
the same `initialRegs`, the same `isFinal`, and the same vertex
type — just rewritten alphabets.

---

## 3. The variance caveat — read this once

`SymTransducer`'s `ci` parameter is **bivariant**: it appears
contravariantly in `InCtor.icMatch :: ci -> Maybe (RegFile ifs)`
and covariantly in `InCtor.icBuild :: RegFile ifs -> ci`. The
covariant occurrence is what `Keiki.Core.solveOutput` uses to
recover `ci` from a wire event during replay.

A naive `lmapCi (f :: ci' -> ci)` cannot rewrite `icBuild` because
it lacks the inverse direction `ci -> ci'`. The same is true of
`rmapCo (g :: co -> co')` for `WireCtor.wcMatch :: co -> Maybe fs`.

**The decision (recorded in MP-9's Decision Log):** keiki ships
the standard `Profunctor` interface and accepts a documented loss:

- `lmapCi f` and `lmapMaybeCi f` produce a transducer whose
  rewritten `InCtor.icBuild` is **poisoned** with a runtime error.
  Forward processing is unaffected; *only* `solveOutput` (and
  therefore `applyEvent` / `reconstitute` / `Decider.evolve`) is
  broken on rewritten edges.
- `rmapCo g` produces a transducer whose rewritten
  `WireCtor.wcMatch` is **`const Nothing`**. `solveOutput` returns
  `Nothing` on rewritten edges. Forward processing is unaffected.

In one sentence: **rewritten transducers are forward-only.**
Use them when you're processing live commands or post-composing
events for the wire. Don't use them as the source of truth for an
event-replay path — keep the un-rewritten transducer around for
that.

If you accidentally call `solveOutput` on a `lmapCi`-rewritten
edge and force the result, you get a clear runtime error naming
the constructor:

```
Keiki.Profunctor: icBuild on a contramapped InCtor "SendEmail"
was invoked. lmapCi/lmapMaybeCi-rewritten transducers cannot
rebuild ci from a wire event via solveOutput. See the haddock
for Keiki.Profunctor.lmapCi.
```

That's the contract: forward yes, replay no, error if you try.

---

## 4. Real-world use case: command routing with `lmapMaybeCi`

A common shape in event-sourced services: one HTTP gateway accepts
a wide command sum and dispatches each command to the correct
aggregate. Without keiki, you write a hand-rolled `case` for every
aggregate. With `lmapMaybeCi`, each aggregate gets pre-filtered to
*its* slice of the sum:

```haskell
data CmdAll
  = ToBilling   BillingCmd
  | ToShipping  ShippingCmd
  | ToInventory InventoryCmd
  deriving (Eq, Show)

routeBilling   :: CmdAll -> Maybe BillingCmd
routeBilling (ToBilling c) = Just c
routeBilling _             = Nothing

routeShipping  :: CmdAll -> Maybe ShippingCmd
routeShipping (ToShipping c) = Just c
routeShipping _              = Nothing

billingRouted   = lmapMaybeCi routeBilling   billingAggregate
shippingRouted  = lmapMaybeCi routeShipping  shippingAggregate
inventoryRouted = lmapMaybeCi routeInventory inventoryAggregate
```

Each routed transducer accepts the whole `CmdAll`. On a `ToBilling`
input, only `billingRouted`'s edges fire (the structural
`PInCtor` guards in `shippingRouted` / `inventoryRouted` see
`Nothing` from their routers and fail). The runtime can fan one
input out to all three routed transducers without per-aggregate
dispatch logic.

The trade-off: routed transducers are forward-only (the variance
caveat). The reading path — replaying events from the log — must
go through the un-routed `billingAggregate` etc. directly. In
practice this matches the typical architecture: writes go through
the dispatcher; reads go through aggregate-specific projections.

---

## 5. Real-world use case: event-schema versioning with `rmapCo`

Schemas evolve. An aggregate that emits `EmailEventV1` can be
adapted to emit `EmailEventV2` on the wire without touching the
aggregate definition:

```haskell
data EmailEventV2 = EmailEventV2
  { v2Recipient :: Text
  , v2Subject   :: Text
  , v2SentAt    :: UTCTime
  , v2Schema    :: Int     -- new field: schema version tag
  } deriving (Eq, Show)

upcastV1ToV2 :: EmailEvent -> EmailEventV2
upcastV1ToV2 (EmailSent d) = EmailEventV2
  { v2Recipient = d.recipient
  , v2Subject   = d.subject
  , v2SentAt    = d.at
  , v2Schema    = 2
  }

emailDeliveryV2 :: SymTransducer (HsPred EmailRegs EmailCmd)
                                 EmailRegs EmailVertex
                                 EmailCmd EmailEventV2
emailDeliveryV2 = rmapCo upcastV1ToV2 emailDelivery
```

The aggregate's edges, register file, and B-views are unchanged.
Forward processing emits `EmailEventV2` values; runtime serializers
see the new schema. The original `emailDelivery` remains available
for replay against the un-upcasted V1 event log.

For a **read-side** schema downcast (consume V2, project to V1),
use `lmapCi (downcastV2ToV1)` on a transducer whose input is the
V1 event type — `lmapCi` makes the V2-to-V1 projection happen at
the dispatch boundary.

---

## 6. Real-world use case: ecosystem interop

The wrapper's `Profunctor` instance lets keiki transducers slot
into ecosystem code that expects the standard typeclass:

```haskell
import qualified Data.Profunctor as P

-- A generic adapter that takes any Profunctor-shaped value and
-- rewires its edges via two newtype-isomorphic conversions:
adaptBoundary
  :: (Profunctor p)
  => (newCmd -> oldCmd)
  -> (oldEvt -> newEvt)
  -> p oldCmd oldEvt
  -> p newCmd newEvt
adaptBoundary cmdIn evtOut = P.dimap cmdIn evtOut

-- Works for keiki:
let adaptedKeiki :: SomeSymTransducer ApiCmd ApiEvent
    adaptedKeiki = adaptBoundary apiToInternal internalToApi
                     (someSymTransducer internalAggregate)
```

The same `adaptBoundary` works for `Kleisli IO`, `Star Maybe`,
`Costar f`, `Tagged`, lens optics, free-arrow DSLs, and anything
else with a `Profunctor` instance. Generic glue code stays generic;
keiki provides one of the implementations.

For lens-style optics specifically, the `Functor (SomeSymTransducer
ci)` instance lets you `fmap` a wire upcast through any lens that
expects a `Functor`-shaped target.

---

## 7. Real-world use case: bridging mismatched alphabets before `compose`

`Keiki.Composition.compose` requires `t1`'s output type to equal
`t2`'s input type. When the natural alphabets *almost* match —
say, one has a `Versioned` newtype wrapper — `lmapCi` / `rmapCo`
on the concrete transducer (not the wrapper) are the right
adapter:

```haskell
-- Stage 1's natural output is `Versioned EmailCmd`.
stage1
  :: SymTransducer (HsPred S1Regs S1Cmd)
                   S1Regs S1Vertex S1Cmd (Versioned EmailCmd)

-- Stage 2's natural input is `EmailCmd`.
emailDelivery
  :: SymTransducer (HsPred EmailRegs EmailCmd)
                   EmailRegs EmailVertex EmailCmd EmailEvent

-- The composite needs the alphabets to align. Two equivalent fixes:

-- Option A: rewrite stage 1's output to drop the wrapper.
stage1' = rmapCo unversion stage1

-- Option B: rewrite stage 2's input to expect the wrapper.
emailDelivery' = lmapCi versioned emailDelivery

-- Either yields a clean compose:
pipelineA = compose stage1' emailDelivery
pipelineB = compose stage1  emailDelivery'
```

Pick whichever side is more natural to rewrite. The variance
caveat applies to whichever side is rewritten — you lose
`solveOutput` round-trip *only* on the rewritten edges; the
other side's edges are unaffected. (`compose` itself does not
introduce a variance loss.)

---

## 8. Verifying a rewritten transducer

The standard verification gates work on rewritten transducers,
with one exception:

```haskell
-- Single-valuedness survives: the rewriter is structural and
-- preserves guard satisfiability.
isSingleValuedSym (withSymPred (lmapCi unwrap aggregate))
  `shouldBe` True

-- Hidden-input check survives: the OPack structure is preserved.
checkHiddenInputs (lmapCi unwrap aggregate) `shouldBe` []

-- solveOutput / applyEvent / reconstitute are LOSSY by design.
-- On a rewritten edge, solveOutput returns Just (poisoned-thunk)
-- for lmapCi or Nothing for rmapCo. Don't include rewritten
-- transducers in the replay path of a test that goes through
-- reconstitute. Use the un-rewritten aggregate for replay
-- assertions.
```

The test suite at `test/Keiki/ProfunctorSpec.hs` exercises every
combinator on `Jitsurei.EmailDelivery` and asserts each of
these contracts explicitly — copy from there as a template when
adding a new combinator-using test of your own.

---

## 9. Pointers

- `src/Keiki/Profunctor.hs` — implementation. Module haddock
  links back to this guide and to the design plan.
- `test/Keiki/ProfunctorSpec.hs` — the worked example fixture
  with one assertion per documented behaviour.
- `docs/guide/composition.md` — the heavier-weight `compose` /
  `alternative` / `feedback1` combinators when you actually want
  to combine two transducers (not just reshape one).
- `docs/plans/27-existential-wrapper-for-symtransducer-plus-profunctor-instance-and-variance-combinators.md`
  — design rationale, variance discussion, the three options
  considered for the variance contract.
- `docs/masterplans/9-profunctor-and-category-instances-on-symtransducer.md`
  — the parent MasterPlan; tracks EP-28 (Category instance) and
  EP-29 (Strong / Choice / Arrow) as follow-on work.
- `docs/research/architecture-comparison-keiki-vs-crem.md`
  — the named "ecosystem profunctor instances" gap this plan
  closes against crem.
