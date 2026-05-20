# Case study — decomposing `AgentQualificationDecider` onto keiki

Status: worked sketch / validation note. Not a scheduled plan.

This note takes a real production aggregate —
`MlsService.Domain.AgentQualification.AgentQualificationDecider`
(`mls-service-v2`) — and shows how it lands on keiki when modeled *with
the grain* (`docs/guide/modeling-collections.md`). It is the concrete
companion to that guide: the guide states the rule, this note runs a
hard real-world aggregate through it.

The original is the modeling guide's §5 hard case in the wild: its state
is three `Map ChapterId …` collections (one holding a record of six
`Set PropertyId`), its guards branch on collection contents, and several
of its commands emit a **data-dependent number of events**. As a single
aggregate it does not fit keiki — the data-dependent output arity is not
even expressible (keiki edges have a *static* output list; `INV4` in the
collection note, `gsm-widening-design.md` §10). Decomposed along
`ChapterId`, it fits cleanly, and keiki earns its keep on the part that
matters: the `NotQualified ⇄ Qualified` lifecycle.


## 1. The decomposition map

| Original (one aggregate) | keiki home |
|---|---|
| `Map ChapterId QualificationStatus` (control fact) | the **vertex** of a per-chapter stream (`NotQualified` / `Qualified`) |
| `Map ChapterId ChapterSalesData` (8 numerics) | **scalar tally registers** on that stream (§3 of the guide) |
| `Map ChapterId AgentTransactionRecord` (6 `Set PropertyId`) | **runtime idempotency** (dedup by `(propertyId, role)` at dispatch), not pure-core state |
| one transaction → N matching chapters (`foldl'`/`chaptersWithMatchingAreas`) | **routing/fan-out** in the subscription layer: one command per target stream |
| `QualifyAgent` emitting one event per chapter | the router dispatches one `QualifyCheck` per chapter stream |
| `CorrectInvalidAdjustments` emitting one event per invalid property | a **saga** issuing one correction command per `(chapter, property)` |
| `…TransactionIgnored` events | gone — they were artifacts of cramming routing + dedup into the aggregate |
| agent-wide `MemberRemoved → DeletedAgent` | a small **coordinator/Process** that `Retire`s the agent's chapter streams |

Everything that made the original un-keiki — nested collections,
content guards, variable output arity — is either turned into a scalar
tally or pushed to the layer that owns it (routing → dispatch,
idempotency → runtime). What remains is a small, analyzable machine.


## 2. The `ChapterQualification` aggregate

**Stream identity:** `(MemberId, ChapterId)` — one stream per
agent-chapter pair. The original's outer `Map ChapterId` *is* the set of
streams.

### Vertices

```haskell
data Vertex = NotQualified | Qualified | Retired
  deriving stock (Eq, Show, Enum, Bounded)

-- initial = NotQualified ;  isFinal Retired = True ;  isFinal _ = False
```

### Registers (the tallies)

`ChapterSalesData`'s eight fields become eight scalar tallies — the
exact pattern `Jitsurei.OrderCart` uses for `itemCount`. No map.

```haskell
type ChapterQualRegs =
  '[ '("listingVolume",   Money)     -- Σ close prices, listing role
   , '("colistingVolume", Money)     -- co-listing + primary-colisting
   , '("buyerVolume",     Money)
   , '("cobuyerVolume",   Money)     -- co-buyer + primary-cobuyer
   , '("listingSides",    Int)
   , '("colistingSides",  Int)
   , '("buyerSides",      Int)
   , '("cobuyerSides",    Int)
   , '("qualifiedAt",     UTCTime)   -- stamped on the NotQualified → Qualified edge
   ]
```

`initialRegs` seeds the eight tallies to `0` (and `qualifiedAt` to a
sentinel epoch) so the threshold guard never reads an `uninit:` slot.
Following keiki's own convention (`Jitsurei.OrderCart`'s `Money = Word64`),
`Money` here is `Word64` minor units (cents), **not** `Scientific`;
making money guards solver-visible is the follow-up EP (§5).

### Alphabets

Post-routing (the router already decided this chapter matches), the
per-chapter command set collapses the original's ~25 commands to a small
set; the six record commands fold to four roles (the "primary" variants
hit the same tally):

```haskell
data ChapterQualCmd
  = RecordListing   RecordData | RecordColisting RecordData
  | RecordBuyer     RecordData | RecordCobuyer   RecordData
  | RemoveListing   RemoveData | …                            -- 4 removal verbs
  | UpdateListingPrice PriceData | …                          -- 4 price-update verbs
  | AdjustListingForCoAgent AdjustData | AdjustBuyerForCoAgent AdjustData
  | QualifyCheck    CheckData    -- carries minVolume, minSides, at, memberId, chapterId
  | RequalifyCheck  CheckData
  | Retire          RetireData   -- from the agent-removal coordinator

data ChapterQualEvent
  = ListingRecorded RecordedData | …                          -- one per record verb
  | ListingRemoved  RemovedData  | …
  | ListingPriceUpdated PriceUpdatedData | …
  | CoAgentListingAdjusted AdjustedData | CoAgentBuyerAdjusted AdjustedData
  | AgentQualified  QualifiedData
  | AgentNoLongerQualified DisqualifiedData
  | AgentRetired    RetiredData
```

`InCtor`/`WireCtor` values are TH-derived (`deriveAggregateCtors`,
`deriveWireCtors`); not shown.

### The weighted totals (the one escape)

The credit formula (`mkTotalVolume`/`mkTotalSides`, with the 0.5
co-agent multiplier) has no arithmetic constructor in `Term`, so it is
built with `TApp` — the same escape `Jitsurei.LoanApplication` accepts
for `creditScore >= 650`. Sides are doubled to stay in `Int` and avoid a
fractional `0.5`:

```haskell
weightedVolume :: Term ChapterQualRegs ci Money
weightedVolume =
  TApp2 (\primary co -> primary + 0.5 * co)
        (TApp2 (+) #listingVolume #buyerVolume)
        (TApp2 (+) #colistingVolume #cobuyerVolume)

-- 2 * totalSides, integer-valued:
weightedSidesx2 :: Term ChapterQualRegs ci Int
weightedSidesx2 =
  TApp2 (\primary co -> 2 * primary + co)
        (TApp2 (+) #listingSides #buyerSides)
        (TApp2 (+) #colistingSides #cobuyerSides)
```

### The transducer

```haskell
chapterQualification :: SymTransducer (HsPred ChapterQualRegs ChapterQualCmd)
                                      ChapterQualRegs Vertex ChapterQualCmd ChapterQualEvent
chapterQualification = buildTransducer NotQualified initialRegs isFinal $ do

  B.from NotQualified do
    -- Accumulate. Self-loop, no control change. (one per role; listing shown)
    B.onCmd inCtorRecordListing $ \d -> B.do
      B.slot @"listingVolume" .= TApp2 (+) #listingVolume d.closePrice
      B.slot @"listingSides"  .= TApp1 (+ 1) #listingSides
      B.emit wireListingRecorded ListingRecordedFields
        { propertyId = d.propertyId, closePrice = d.closePrice, at = d.at }
      B.goto NotQualified
    -- … RecordColisting/Buyer/Cobuyer, the four removals, the four price
    --   updates, and the two co-agent adjustments are analogous self-loops
    --   that bump/cut the relevant tally and emit their event …

    -- THE analyzable transition: cross the threshold.
    B.onCmd inCtorQualifyCheck $ \d -> B.do
      B.requireGuard
        (    PEq (TApp2 (>=) weightedVolume   d.minVolume)    (lit True)
        `pand` PEq (TApp2 (>=) weightedSidesx2 (twice d.minSides)) (lit True))
      B.slot @"qualifiedAt" .= d.at
      B.emit wireAgentQualified AgentQualifiedFields
        { memberId = d.memberId, chapterId = d.chapterId, qualifiedAt = d.at }
      B.goto Qualified

    B.onCmd inCtorRetire $ \d -> B.do
      B.emit wireAgentRetired AgentRetiredFields { at = d.at }
      B.goto Retired

  B.from Qualified do
    -- Still accumulating while qualified (self-loops, as above).
    B.onCmd inCtorRecordListing $ \d -> B.do
      B.slot @"listingVolume" .= TApp2 (+) #listingVolume d.closePrice
      B.slot @"listingSides"  .= TApp1 (+ 1) #listingSides
      B.emit wireListingRecorded ListingRecordedFields
        { propertyId = d.propertyId, closePrice = d.closePrice, at = d.at }
      B.goto Qualified

    -- THE analyzable transition: fall back below the threshold.
    B.onCmd inCtorRequalifyCheck $ \d -> B.do
      B.requireGuard
        (PNot ( PEq (TApp2 (>=) weightedVolume   d.minVolume)    (lit True)
         `pand` PEq (TApp2 (>=) weightedSidesx2 (twice d.minSides)) (lit True)))
      B.emit wireAgentNoLongerQualified DisqualifiedFields
        { memberId = d.memberId, chapterId = d.chapterId, disqualifiedAt = d.at }
      B.goto NotQualified

    B.onCmd inCtorRetire $ \d -> B.do
      B.emit wireAgentRetired AgentRetiredFields { at = d.at }
      B.goto Retired
```

(`pand` = `PAnd`; `twice = TApp1 (* 2)`. The qualify/requalify guards are
the same predicate; one edge takes it, the other its negation.)


## 3. What keiki verifies here (and what it doesn't)

What you *gain* by decomposing — none of which the original aggregate
could offer:

- **Single-valuedness is real, not vacuous.** At each vertex the edges
  are disjoint by **input constructor** (`PInCtor`, which the SBV layer
  translates exactly): `RecordListing` vs `QualifyCheck` vs `Retire` from
  `NotQualified` can't co-fire. `isSingleValuedSym (withSymPred …)`
  proves it.
- **Reachability** of `Qualified` and `Retired` is a mechanical query.
- **Replay is derived** (`reconstitute`) — no hand-written `evolve`. The
  original's ~270 lines of `evolve`/`evolveWith*` collapse into the
  `Update` terms on the edges.
- **`checkHiddenInputs`** is meaningful again: each recorded event
  carries the data its edge consumed.

What stays an **escape** (honestly):

- The **threshold guard** is `TApp`-wrapped — ordering (`>=`) over a
  `TApp`-derived weighted sum of `Money`. The solver sees it as an
  opaque free Boolean. This does **not** cost the control guarantees
  above (those rest on `PInCtor` + vertex), but the *content* of "did
  they cross the bar" is unverified. Three gaps stack here, in closing
  order: **(a)** the money type (`Word64`) and **(b)** an ordering
  predicate are both delivered by the follow-up EP-41 (§5), after which
  `weightedVolume >= minVolume` is a structural `PCmp` over `Word64`
  terms; **(c)** the `weightedVolume` *operand* is still a `TApp` sum, so
  full verification of the threshold additionally needs structural
  arithmetic terms — the remaining sibling EP. (A common workaround that
  needs none of these: maintain the weighted total as its own scalar
  tally register and compare *that* directly, keeping the operand
  structural.)


## 4. What moved out of the aggregate — and where it went

The original crammed three non-aggregate concerns into the decider;
decomposition relocates each to where keiki's architecture already puts
it:

- **Routing / fan-out** (one transaction → all area-matching chapters,
  `chaptersWithMatchingAreas`): a **subscription/router** that reads the
  raw transaction and dispatches one command to each matching
  `(member, chapter)` stream. The data-dependent count lives in the
  messaging fabric, not on a transducer edge — so keiki's static
  output-list invariant is never violated. (See `effects-boundary.md`:
  the pure core is per-stream; dispatch is the runtime's job.)
- **Idempotency / dedup** (the six `Set PropertyId`): dedupe by
  `(propertyId, role)` at the command boundary in keiro. The sets were
  pure plumbing for "already processed?", which is the canonical
  idempotency concern keiki delegates to the runtime (collection note
  §7). If dedup must be domain-level, push to per-`(chapter, property,
  role)` granularity — heavier, but still on-grain.
- **Agent lifecycle** (`MemberRemoved`): a tiny coordinator/Process that,
  on the agent-level removal event, emits a `Retire` command to each of
  the agent's chapter streams (the events-in/commands-out shape of
  `Jitsurei.CoreBankingSync`).
- **`CorrectInvalidAdjustments`** (scan all chapters, emit one correction
  per invalid property): a saga that issues one per-`(chapter, property)`
  correction command; each stream handles a single correction →
  static output.


## 5. Follow-up

The keiki *capability* gaps this exercise surfaces (everything else is
modeling) are symbolic visibility of money/numeric values and of ordering
guards, so the qualification threshold can be verified rather than escaped
through `TApp`. These are scoped as
`docs/plans/41-symbolic-numeric-and-ordering-guards-sym-money-fixed-width-ints-ordering-predicate.md`,
which adds `Sym` instances for the fixed-width integer types (money is
`Word64` minor units per keiki convention — §3(a)) and a structural
ordering predicate `PCmp` (§3(b)). Two related gaps stay sibling
follow-ons in that plan: structural arithmetic terms (needed so the
`weightedVolume` *operand* in §3(c) is visible) and per-slot translator
memoization (needed so repeated reads of one register share a solver
variable).


## Pointers

- `docs/guide/modeling-collections.md` — the rule this note applies.
- `docs/research/collection-registers-design.md` — the road not taken
  (this aggregate is its motivating shape, and still doesn't want it).
- `Jitsurei.OrderCart` — the tally pattern shipped.
- `Jitsurei.LoanApplication` — the `TApp` threshold-guard escape in a
  shipped aggregate.
- `Jitsurei.CoreBankingSync` — the coordinator/Process shape.
- Source under study:
  `mls-service-v2/.../Domain/AgentQualification/AgentQualificationDecider.hs`.
