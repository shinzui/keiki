# Modeling collections

You have an aggregate, and a part of its state is naturally "many of
something": line items, participants, blockers, seat holders, reviews.
The reflex from object/relational modeling is to put a `Map K V` or a
`[X]` in the aggregate's register and mutate it per element.

**In keiki, that reflex is usually wrong** — not because keiki can't
*store* a collection (it can; a `'("holders", Map UserId SeatHolder)`
slot is legal), but because a collection in a register quietly forfeits
the thing keiki exists to give you: build-time analyzability of guards
and mechanically-derived replay. The analyses keiki sells
(`checkHiddenInputs`, `isSingleValuedSym`, reachability) live in a
small, decidable predicate fragment. A collection's *contents* fall
outside it.

This guide gives you a rule and two patterns that keep you inside the
fragment, and is honest about the one case where neither fits.

> **One-line rule.** Project the collection down to the scalar facts
> your guards actually need; promote any element that has its own
> identity *and* lifecycle into its own aggregate. Reach for a
> collection register only when you have measured that you can't.


## 1. Why a collection in a register is a smell

keiki's predicate language (`HsPred`) is deliberately small:
equality (`PEq`), input-constructor match (`PInCtor`), and the Boolean
connectives. That is the fragment the SBV/z3 layer translates, so it is
the fragment over which `isSingleValuedSym` (no two edges fire at once)
and `symIsBot` (reachability/emptiness) give you *real answers* rather
than a shrug.

A guard that branches on a collection's contents — "is this key
present?", "are *all* elements resolved?", "how many are open?" — has no
structural form in that language. Today it can only be written by
wrapping `Data.Map`/list code in an opaque `TApp` closure, and the
symbolic layer translates a `TApp` to a *fresh, unconstrained* variable.
That is sound (it never claims a false guarantee) but it carries **no
information**: the guard becomes invisible to every analysis. So the
moment your aggregate's lifecycle turns on collection contents, you've
moved keiki's headline guarantee off exactly the logic that most needs
it.

Ergonomics and replay degrade too (`Map.insert k v` is arity-3 and
won't fit `TApp2`; collection-derived output fields stop being
invertible by `solveOutput`), but the verification loss is the one that
matters, because it's the one you can't get back by writing more code.


## 2. The rule

Ask two questions about the "many of something":

```
                ┌─────────────────────────────────────────────┐
                │ Does each element have its own identity AND   │
                │ a lifecycle (states it moves through, its own │
                │ commands, its own audit)?                     │
                └───────────────┬──────────────────┬───────────┘
                              no │                  │ yes
                                 ▼                  ▼
                ┌────────────────────────┐  ┌────────────────────────┐
                │ Do your guards only     │  │ It is its own aggregate.│
                │ need set-level facts    │  │ Give it a stream;       │
                │ (a count, "all", "none",│  │ coordinate via a Process│
                │ a sum, a flag)?         │  │ / compose. The parent   │
                │   → project to a SCALAR │  │ keeps a scalar summary  │
                │     (a tally). §3       │  │ of the set. §4          │
                └────────────────────────┘  └────────────────────────┘
```

Most "collections" you reach for are the left branch — you don't
actually need the elements as first-class state, you need a *fact about
the set*. The right branch is for genuine sub-entities. The genuinely
hard case (both, plus a set-wide invariant) is §5.


## 3. Pattern A — project to a scalar (the tally)

If your aggregate's logic only needs *facts about the set* — how many,
whether any, whether all, a running total — keep those facts as scalar
registers and maintain them on the write path. Don't keep the elements.

This is exactly what the shipped `Jitsurei.OrderCart` does: a cart's
contents are summarised by `itemCount :: Word32`, "evolved by `TApp1`
arithmetic on AddItem/RemoveItem" — there is no `Map ProductId Line` in
the register at all.

Worked sketch — a `Subscription` that grants seats, where the logic only
cares "how many seats are in use" and "is the subscription idle":

```haskell
type SubscriptionRegs =
  '[ '("seatLimit",   Word16)
   , '("activeSeats", Word16)   -- the tally; no Map of holders
   ]

B.from Active do
  B.onCmd inCtorAssignSeat $ \d -> B.do
    B.slot @"activeSeats" .= TApp1 (+ 1) #activeSeats
    B.emit wireSeatAssigned SeatAssignedFields { user = d.user, at = d.at }
    B.goto Active

  B.onCmd inCtorReleaseSeat $ \d -> B.do
    B.slot @"activeSeats" .= TApp1 (subtract 1) #activeSeats
    B.emit wireSeatReleased SeatReleasedFields { user = d.user, at = d.at }
    B.goto Active

  -- The payoff: a *set-wide* condition expressed as a scalar equality.
  B.onCmd inCtorCancel $ \d -> B.do
    B.requireGuard (#activeSeats .== lit (0 :: Word16))  -- PEq ✅
    B.emit wireSubscriptionCancelled CancelledFields { at = d.at }
    B.goto Cancelled
```

### Why this keeps you verifiable

The cancel guard is `#activeSeats .== lit 0` — a `PEq`. The
symbolic layer translates it structurally, so `isSingleValuedSym` can
prove the `Cancel` edge can't fire alongside another edge, and
reachability can answer "is `Cancelled` reachable?". The equivalent on a
collection register, `Map.null holders` or `all released holders`, would
be an opaque `TApp` and the solver would learn nothing.

This is the move that matters most for "Intention-shaped" aggregates:
the universal guard **"can't close while *any* element is unresolved"**,
which is a `PAll`-over-elements quantifier on a collection, collapses to
**`openCount == 0`** — a plain `PEq` that keiki verifies today. You
maintain `openCount` by incrementing on add and decrementing on resolve;
replay re-derives it mechanically (no hand-written `apply`), and
`checkHiddenInputs` still holds because the element data is on the wire.

### Honest about the boundary

- The *increment* `TApp1 (+ 1)` is opaque to the solver — but that's the
  **update**, not a guard. Single-valuedness reasons about *guards*, so
  an opaque counter update doesn't cost you anything there.
- Only the **equality** fragment is verifiable. An *ordering* tally guard
  like `activeSeats < seatLimit` is not structural today; it routes
  through `TApp` exactly as `Jitsurei.LoanApplication`'s
  `creditScore >= 650` guard does (`PEq (TApp1 (>= 650) …) (lit True)`).
  That's a small, well-understood gap — a candidate for a future
  ordering predicate — and nowhere near the array+quantifier theories a
  collection-content guard would need. Where you can, phrase the
  decisive guard as the equality boundary (`== 0`, `== seatLimit`/full)
  rather than the inequality.

**Use a tally when** your guards and outputs only need counts, sums,
"any/all/none", or a small fixed set of summary flags — and you never
need to address an individual element by key from inside this
aggregate's logic.


## 4. Pattern B — promote the element to its own aggregate

If each element has its own identity *and* lifecycle — states it moves
through, commands that target it, its own audit trail — then it isn't a
field of the parent. It's an aggregate. Give it its own stream and a
`SymTransducer`, and it gets the *full* keiki guarantees (derived
`apply`, single-valuedness, reachability) for its own lifecycle, instead
of disappearing into an opaque `Map` value where none of them apply.

Continuing the example: if a seat assignment can be `Assigned →
Suspended → Released`, can be reassigned, carries a suspension reason and
per-seat audit — model `SeatAssignment` (keyed by `seatId`) as its own
aggregate. The `Subscription` stops holding the holders and becomes a
**coordinator** that keeps only the §3 tally.

Coordinate the two streams with a **Process** — a transducer whose input
alphabet is *events* from one context and whose output alphabet is
*commands* to another (see `Jitsurei.CoreBankingSync` and
`loan-application-tutorial.md` §9–10):

```
SeatAssignment stream            Process (events ▸ commands)        Subscription stream
─────────────────────            ───────────────────────────        ───────────────────
SeatAssigned  ───────────────▶   on SeatAssigned  ▸ emit          ▶  IncrementActiveSeats
SeatReleased  ───────────────▶   on SeatReleased  ▸ emit          ▶  DecrementActiveSeats
```

Stitch a single-stream pipeline with `compose` (sequential), branch
disjoint inputs with `alternative`, or close a one-step aggregate↔policy
loop with `feedback1` — all in `docs/guide/composition.md`. The
composite's vertex type stays the pair of the two aggregates' vertices;
no synthetic state leaks, and the composite is still checkable with
`isSingleValuedSym`.

**The honest cost.** Decomposition buys per-element guarantees at the
price of more streams and *cross-stream coordination*: the parent's
tally is now eventually consistent with the children, and a workflow
that spans both is a Process you have to design and replay. That cost is
real — it is the reason this is a judgment call and not a law. But it is
keiki's *grain*: the library is built to compose verified small machines,
not to hide a big one inside a register.


## 5. The hard case — a set-wide invariant over elements that have lifecycles

The genuinely difficult shape is *both* branches at once: each element
has its own lifecycle **and** there is an invariant over the whole set —
"never more than `seatLimit` active seats", "no two holders for the same
desk", "at most one primary contact".

It is tempting to think a collection register solves this: put the
`Map` in one aggregate so a single guard can see the whole set. It
doesn't, for two reasons:

1. **It's a coordination problem, not a storage problem.** The hard part
   isn't holding the set; it's deciding atomically, against the current
   set, whether the next element is allowed. Even with the `Map` in a
   register, the guard you'd write — `Map.size holders < seatLimit` — is
   a collection-size comparison that keiki cannot verify, so the one
   invariant you most want checked is the one you've made opaque.
2. **The verifiable answer is a coordinator, not a container.** Keep the
   parent as the authority for the set-wide rule, holding the §3 tally,
   and have it *authorize* membership: a reservation step
   (`ReserveSeat` succeeds only while `activeSeats < seatLimit`, then the
   child is created) keeps the limit enforced at one point. The
   limit-boundary guard you most care about — "the subscription is now
   full", `activeSeats == seatLimit` — is then a verifiable `PEq`.

So even the hard case resolves to **§3 + §4** (a coordinator with a
tally, plus per-element aggregates), not to a collection register.


## 6. The road not taken: first-class collection registers

There is a written-up proposal to make collection registers
first-class — structural `UInsert`/`UAdjust`, content guards
`PMember`/`PAll`, element projection `TLookupField`
(`docs/research/collection-registers-design.md`). It is a careful
design, and it would restore ergonomics and a clean `checkHiddenInputs`
for the collection case. It is deliberately **not** the default this
guide points you to, because:

- Its own crux (FR6) admits that the recommended v1 keeps
  collection-guarded edges **"explicitly unverified"** — i.e. it gives
  up keiki's headline guarantee on precisely the collection-bearing
  aggregate that motivated it.
- The fully-verified variant needs z3 **array and finite-set** theories,
  and `PAll`/`PAny` introduce **quantifiers**, which can make the
  single-valuedness check undecidable or impractically slow — and a
  conservative `Unknown` from the solver degrades the gate for *scalar*
  edges too unless carefully fenced.

The bar for actually reaching for that feature, rather than §3–§5, is
high: you need per-element lifecycle **and** set-wide invariants **and**
an inability to tolerate cross-stream coordination **and** no need for
the element-level guards to be verified. If you can satisfy your
requirements with a tally, a decomposition, or a coordinator — and the
experience of `OrderCart`, `LoanApplication`, and the Process examples is
that you usually can — do that first. Treat the collection-register note
as the escape hatch you justify with a measured case, not the first
tool.


## 7. Quick reference

| You have… | …and you need | Model it as | Verifiable? |
|---|---|---|---|
| "many of something" | counts / sums / "any"/"all"/"none" / flags | scalar **tally** in the aggregate (§3) | yes, in the `PEq` fragment |
| elements with identity + lifecycle | per-element states, commands, audit | each element its **own aggregate**, coordinated by a **Process** / `compose` (§4) | yes, per element |
| both, plus a set-wide invariant | atomic "is the next one allowed?" | **coordinator** (tally + reservation) over per-element aggregates (§5) | the boundary guard, as a `PEq` |
| genuinely none of the above | structural per-element ops *with* content guards in one stream | the **collection-register proposal** (§6) — measured, not default | partial at best (FR6) |

**Pointers**

- `docs/guide/composition.md` — `compose`, `alternative`, `feedback1`.
- `loan-application-tutorial.md` §9–10 — a Process and `compose` wired
  end-to-end.
- `Jitsurei.OrderCart` — the tally pattern in a shipped aggregate.
- `Jitsurei.CoreBankingSync` — the events-in / commands-out Process shape.
- `docs/guide/why-smt.md` — what the verifiable fragment buys you, and
  why keeping guards inside it is worth the modeling effort.
- `docs/research/collection-registers-design.md` — the road not taken,
  for when the rule genuinely doesn't fit.
