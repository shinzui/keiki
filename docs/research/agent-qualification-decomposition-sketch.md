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
money guards over `Word64` are solver-visible as of EP-41 (§5).

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

### The weighted totals (now mostly structural)

The credit formula (`mkTotalVolume`/`mkTotalSides`, with the 0.5
co-agent multiplier) used to have *no* arithmetic constructor in `Term`,
so it was built with `TApp`. Since EP-43 (structural arithmetic terms),
integer `+`/`-`/`*` are first-class `Term`s (`tadd`/`tsub`/`tmul`, spelled
here with the EP-45 operators `.+`/`.-`/`.*`) the SBV translator reads —
the same win that made `Jitsurei.LoanApplication`'s derived cap structural
(`appRequestedAmount <= appCreditScore * 1000`, now a structural `.*`
(`tmul`), no longer a `TApp`). The integer "doubled to stay in `Int`"
form is therefore fully solver-visible. A *fractional* `0.5` multiplier
is still out of scope (no `Double`/SReal — EP-43's boundary), so either
keep the doubling workaround (structural) or fall back to `TApp` for a
genuine fraction:

```haskell
-- 2 * totalSides, integer-valued — now fully structural (EP-43),
-- written with the EP-45 arithmetic operators (.* binds tighter than .+):
weightedSidesx2 :: Term ChapterQualRegs ci Int
weightedSidesx2 =
  lit 2 .* (#listingSides .+ #buyerSides)
    .+ (#colistingSides .+ #cobuyerSides)

-- The fractional-0.5 volume form still needs TApp (SReal is out of
-- scope); prefer the doubled integer form above when verification
-- matters. The integer sub-sums stay structural .+ terms:
weightedVolume :: Term ChapterQualRegs ci Money
weightedVolume =
  TApp2 (\primary co -> primary + 0.5 * co)
        (#listingVolume .+ #buyerVolume)
        (#colistingVolume .+ #cobuyerVolume)
```

### The transducer

```haskell
chapterQualification :: Guarded ChapterQualRegs Vertex ChapterQualCmd ChapterQualEvent
chapterQualification = buildTransducer NotQualified initialRegs isFinal $ do

  B.from NotQualified do
    -- Accumulate. Self-loop, no control change. (one per role; listing shown)
    B.onCmd inCtorRecordListing $ \d -> B.do
      B.slot @"listingVolume" .= #listingVolume .+ d.closePrice
      B.slot @"listingSides"  .= #listingSides  .+ lit 1
      B.emit wireListingRecorded ListingRecordedFields
        { propertyId = d.propertyId, closePrice = d.closePrice, at = d.at }
      B.goto NotQualified
    -- … RecordColisting/Buyer/Cobuyer, the four removals, the four price
    --   updates, and the two co-agent adjustments are analogous self-loops
    --   that bump/cut the relevant tally and emit their event …

    -- THE analyzable transition: cross the threshold.
    B.onCmd inCtorQualifyCheck $ \d -> B.do
      B.requireGuard
        (    weightedVolume  .>= d.minVolume
        .&&  weightedSidesx2 .>= twice d.minSides)
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
      B.slot @"listingVolume" .= #listingVolume .+ d.closePrice
      B.slot @"listingSides"  .= #listingSides  .+ lit 1
      B.emit wireListingRecorded ListingRecordedFields
        { propertyId = d.propertyId, closePrice = d.closePrice, at = d.at }
      B.goto Qualified

    -- THE analyzable transition: fall back below the threshold.
    B.onCmd inCtorRequalifyCheck $ \d -> B.do
      B.requireGuard
        (pnot ( weightedVolume  .>= d.minVolume
          .&&   weightedSidesx2 .>= twice d.minSides))
      B.emit wireAgentNoLongerQualified DisqualifiedFields
        { memberId = d.memberId, chapterId = d.chapterId, disqualifiedAt = d.at }
      B.goto NotQualified

    B.onCmd inCtorRetire $ \d -> B.do
      B.emit wireAgentRetired AgentRetiredFields { at = d.at }
      B.goto Retired
```

(`.&&` = `PAnd`, `pnot` = `PNot`; `twice t = t .* lit 2`, a structural
`tmul`. The qualify/requalify guards are the same predicate; one edge
takes it, the other its negation.)


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

- The **threshold guard** mixes structural and opaque parts. Ordering
  (`>=`) over a weighted sum of `Money`: three gaps stacked here, in
  closing order. **(a)** the money type (`Word64`) and **(b)** an
  ordering predicate (`PCmp`, the EP-45 operators `.<`/`.<=`/`.>`/`.>=`)
  are **now delivered** by EP-41 (done; §5) — so a threshold written as
  `weightedVolume .>= lit minVolume` (a `PCmp CmpGe`) is a structural
  comparison over `Word64` that the solver reads exactly,
  and a *constant* threshold (e.g. comparing a single tally register
  against a literal bound) is fully verifiable today. **(c)** the
  `weightedVolume` *operand*, when written with integer `.+`/`.*`, is now
  a structural `tadd`/`tmul` the solver reads (EP-43, done; §5) — so a
  *derived-quantity* threshold is fully verifiable too. The shipped
  instance is `Jitsurei.LoanApplication`'s `appRequestedAmount <=
  appCreditScore * 1000`, now a structural `.*` (`tmul`). (Only a *fractional*
  weight like `0.5` stays opaque, since `Double`/SReal is out of scope;
  use the doubled-integer form to keep it structural.) And two reads of
  the *same* register in one predicate **now share** a solver variable
  (EP-42 per-slot memoization, done; §5), so a self-mutex like `g ∧ ¬g`
  over a shared register is correctly reported unsatisfiable — which is
  exactly why `Jitsurei.LoanApplicationSymbolicSpec`'s single-valuedness
  gate is now proven (it needed both EP-42 and EP-43).


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

The keiki *capability* gaps this exercise surfaced (everything else is
modeling) were symbolic visibility of money/numeric values and of ordering
guards, so the qualification threshold can be verified rather than escaped
through `TApp`. These were scoped as — and **delivered by** —
`docs/plans/41-symbolic-numeric-and-ordering-guards-sym-money-fixed-width-ints-ordering-predicate.md`
(EP-41, complete): it adds `Sym` instances for the fixed-width integer
types (money is `Word64` minor units per keiki convention — §3(a)) and a
structural ordering predicate `PCmp` (§3(b)). So money equality and
`<`/`<=`/`>`/`>=` over `Word64` registers are now solver-visible, proven
by `Jitsurei.OrderCartSymbolicSpec` and the migrated
`Jitsurei.LoanApplication` threshold guards. The two related gaps are now
**also delivered** (MasterPlan 12): structural arithmetic terms — EP-43
(`docs/plans/43-structural-arithmetic-terms-in-the-keiki-term-language.md`),
so the `weightedVolume` *operand* in §3(c) is visible when written with
`tadd`/`tmul` (the `.+`/`.*` operators) — and per-slot translator
memoization — EP-42
(`docs/plans/42-per-slot-and-per-input-field-memoization-in-the-symbolic-translator.md`),
so repeated reads of one register share a solver variable. With both,
`Jitsurei.LoanApplicationSymbolicSpec`'s single-valuedness gate is no
longer pending — it is proven (the self-mutex `approvalGuard ∧
¬approvalGuard` is unsatisfiable once the cap is structural and the
`#appCreditScore` reads are shared).

The guard and term snippets above are written in the EP-45 readable-DSL
surface — the dot-prefixed operators (`.>=`/`.<=`/`.==`/`.&&`/`.+`/`.*`,
with `pnot`) and the `Pred`/`Guarded` type synonyms. These are thin
definitional aliases for the same `PCmp`/`PEq`/`PAnd`/`PNot`/`tadd`/`tmul`
constructors and the `SymTransducer (HsPred …)` carrier, so the AST — and
therefore everything this note claims about evaluation, replay, and
solver visibility — is byte-for-byte unchanged. See
`docs/plans/45-readable-guard-dsl-dot-prefixed-predicate-operators-and-type-synonyms.md`
(EP-45) and user-guide §3.4.


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
