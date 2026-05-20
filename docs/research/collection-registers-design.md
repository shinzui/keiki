# First-class collection registers in keiki

Status: requirement / feasibility probe (not yet scheduled under a MasterPlan).
**No committed consumer as of 2026-05-20** — the original motivating consumer
withdrew after a boundary re-analysis; see the Consumer-reassessment callout below.

> **Validated against the code on 2026-05-20** and reconciled with the GSM
> widening that shipped under MasterPlan 7 / EP-19 on 2026-05-16. This note's
> first draft was written during the 2026-05-02 → 2026-05-16 window, when EP-20
> (state-refinement ergonomics) was the *selected* path and EP-19 (GSM widening)
> was marked **Cancelled**. That selection was **reversed**: `Edge.output` is now
> `[OutTerm rs ci co]` — a *static* per-edge event list — replay runs through the
> `InFlight` streaming wrapper (`applyEventStreaming` / `reconstitute`), and
> state refinement is retired as the canonical multi-event model. The note's core
> technical thesis survives intact, because GSM widening touched `output`, not
> the `Term` language, `solveOutput`, or the symbolic layer — but every claim
> that assumed a `Maybe`-shaped output or a "letter-FST settled direction" has
> been corrected (see INV2–INV4, §1, and §7).

> **Consumer reassessment, 2026-05-20 — the motivating consumer withdrew.** Rei's
> Intention (the §0/§1 motivating example) re-ran its DDD aggregate-boundary
> analysis against the actual decider and found it does **not** need this feature.
> Its sub-entity collections existed only for (a) idempotency dedup and (b)
> *sub-entity-local* validation — **not** for any cross-entity transactional
> invariant (every boundary-spanning rule is already enforced eventually, in the
> application layer against the read model). So the correct redesign makes the
> Intention *root* a **scalar** aggregate, promotes the lifecycle-bearing
> sub-entities (Blocker, Review, Delegation) to their own small scalar aggregates,
> and demotes the lifecycle-less ones (Action, Outcome, Dependency, Support) to
> value-events with id-based idempotency. That is precisely the §8
> "sub-entity-as-aggregate" path — here the *correct* design, not a fallback.
> **Net effect: this note has no committed consumer.** It remains a sound spec for
> a *genuine* value-object collection that carries a true in-aggregate invariant
> (the case Intention turned out not to be) — treat it as speculative until such a
> consumer actually appears, and prefer the §8 split whenever a "collection" is
> really a set of entities with their own identity and lifecycle.

This note specifies a candidate feature for the keiki pure core: register slots
that hold **keyed collections** (associative maps, sets, ordered lists) with a
**structural, AST-level vocabulary** for per-element insert / delete / update and
content guards. It is written as a requirement plus an honest feasibility
analysis so the maintainer can decide whether to build it, and if so under what
contract.

The original motivating consumer was external: the Rei application
(`/Users/shinzui/Keikaku/bokuno/rei-project/rei`, see its MasterPlan #8 to
migrate onto keiro/keiki/kiroku, child plan EP-6). Rei's `Intention` aggregate is
a single event stream whose state carries **seven sub-entity collections** —
`Map BlockerId BlockerState`, `[ActionState]`, `[OutcomeState]`, and similar maps
for dependencies, supports, delegations, and reviews (knowledge, tasks,
reflections, guidance, and embeds also ride the stream but are *passenger events*,
`evolve s _ = s`, not folded into state) — each mutated *per element* by commands
(`DeclareBlocker`, `ResolveBlocker`, `RecordAction`, …). It read as the single
hardest aggregate to express on keiki, which is why this note was written. **As of
the 2026-05-20 reassessment above, that motivation no longer holds:** the correct
boundary redesign removes the collections from the aggregate entirely, so the
requirement below stands as a general spec for value-object collections rather than
a Rei-driven one. It is written so a reader with keiki context (but no Rei context)
can implement and accept it.


## 1. What the current AST does, and where collections bite

A register slot can already hold a collection: `RegFile` slots are
`(Symbol, Type)` pairs (`src/Keiki/Core.hs`, `data RegFile`), so
`'("blockers", Map BlockerId BlockerState)` is a legal slot today. **Storage is
not the gap.** Runtime replay is not the gap either: `runUpdate (USet ix term)`
(`src/Keiki/Core.hs`) re-evaluates `term` *forward* against the current register
file and input, and `term` may read the prior slot value via `TReg`. So a
collection mutation written as a `USet` over a `TApp` term reconstructs correctly
on replay — replay (`reconstitute` / `applyEventStreaming`, threading the
post-EP-19 `InFlight` wrapper) recovers the command from each observed event via
`solveOutput`, then re-runs e.g. `Map.insert k v (TReg blockers)` against the
register file already accumulated during replay. (Post-EP-19, `Edge.output` is a
list `[OutTerm rs ci co]`; the *head* of each edge's list is the event
`solveOutput` inverts against, and a collection edge that is *also* multi-event
streams its tail through `InFlight` like any other — see INV2.)

What the current AST actually lacks is **structural visibility** of collection
operations, which costs both ergonomics and every static analysis keiki sells:

1. **No collection vocabulary in `Term`.** The term language is `TLit`, `TReg`,
   `TInpCtorField`, `TApp1`, `TApp2` (`src/Keiki/Core.hs`, `data Term`). There is
   no map/set/list operation, and `TApp2` caps applied functions at arity 2,
   while `Map.insert :: k -> v -> Map k v -> Map k v` is arity 3. So every
   element mutation is forced through an **opaque** `TApp` closure
   (`TApp1 (\m -> Map.insert k v m) (TReg blockers)`, capturing `k`/`v` inside
   the closure where no analysis can see them). Awkward to write, and invisible
   downstream.

2. **`solveOutput` cannot invert collection-derived outputs.** `solveOutput`
   recovers the input by walking `OutFields` structurally; `gatherInpEntries` /
   `stepOne` return `Nothing` for `TApp1` and `TApp2` (`src/Keiki/Core.hs`, the
   `stepOne` arms for `TApp1 _ _` and `TApp2 _ _ _` — still the case after
   EP-19). The moment an emitted event carries a field *derived from* a collection
   through a closure (e.g. `Map.size blockers`, or a blocker's prior status looked
   up by key, wrapped in `TApp`), that field is opaque to the inversion. If the
   opaque field is the one carrying the *input* data the edge's `update` consumes,
   the input is unrecoverable and `checkHiddenInputs` flags the edge (its
   union-coverage walk — see INV3 — leaves the `InCtor`'s slot unvisited).
   Structural register reads (`TReg`) are already fine here: `stepOne` returns
   `Just []` for them because they are recoverable from the *replayed register
   file* rather than from the wire. FR4's `TLookupField` exists to give collection
   element reads that same structural, non-opaque status.

3. **The symbolic checker cannot see collection guards.** `Keiki.Symbolic`'s
   SBV-backed `BoolAlg` over `HsPred` *does* translate `TApp1` / `TApp2`, but only
   to a fresh, unconstrained SBV variable (`translateTermSym` emits
   `SBV.free "app1"` / `"app2"`; a `PEq` over a non-`Sym` operand likewise emits
   `SBV.free "neq"`). That is a sound over-approximation that carries *no
   information*: any guard branching on collection contents ("blocker already
   present", "all actions complete", "board has no open blockers") collapses to an
   opaque free Boolean, so it is invisible to the single-valuedness and
   reachability analyses. keiki's distinctive build-time guarantee is lost
   precisely on the collection-bearing aggregate where it would be most valuable.

In short: collection-bearing aggregates are expressible and replay-sound *today*,
but only by escaping into opaque `TApp`, which surrenders ergonomics, the
`checkHiddenInputs` guarantee whenever outputs derive from collections, and the
symbolic verification story for collection-branching edges. This feature restores
those for the collection case.


## 2. Goal

Let an author declare a slot as a keyed collection and express per-element
insert / delete / update and content guards through a structural AST vocabulary,
so the existing analyses treat collection-bearing aggregates as first-class while
runtime replay stays mechanically derived. The acceptance bar: authoring a
mini-`Intention`-shaped aggregate (a board of blockers with a lifecycle guard)
must require **zero `TApp`**, must `reconstitute` correctly, must pass
`checkHiddenInputs` clean, and must have a defined, honest symbolic-analysis
status (see §6).


## 3. Functional requirements

- **FR1 — Collection slot kinds.** A way to mark a slot's element schema so the
  AST knows it is a keyed collection. Sketch: distinguished slot element types
  such as `MapReg k v`, `SetReg a`, `ListReg a` (or a `Collection c` class with
  associated key/element types). The element type `v` should itself be
  expressible as a sub-`RegFile` / record so element fields are projectable
  (needed by FR4).

- **FR2 — Structural update combinators.** New `Update` constructors (or smart
  builders compiling to them) that carry **terms**, not closures:

      UInsert  :: CollectionSlot s rs (k, v) -> Term rs ci k -> Term rs ci v -> Update rs '[s] ci
      UDelete  :: CollectionSlot s rs (k, v) -> Term rs ci k -> Update rs '[s] ci
      UAdjust  :: CollectionSlot s rs (k, v) -> Term rs ci k -> ElemUpdate v ci -> Update rs '[s] ci
      -- ordered-list variants: UAppend, URemoveBy …

  where `ElemUpdate v ci` is itself a structural update over the element's
  sub-schema (so `UAdjust "blockers" key (sub @"status" .= d.status)` sets one
  element field without an opaque function). These must compose under the
  existing `Disjoint`-checked `combine` (`src/Keiki/Core.hs`): writing two
  different slots stays disjoint; two writes to the *same* collection slot in one
  edge must be rejected or explicitly sequenced.

- **FR3 — Structural guard combinators.** New `HsPred` constructors for
  collection content, evaluable at runtime via `evalPred` and targetable by the
  symbolic layer (FR6):

      PMember    :: CollectionSlot s rs (k, v) -> Term rs ci k -> HsPred rs ci
      PNotMember :: CollectionSlot s rs (k, v) -> Term rs ci k -> HsPred rs ci
      PSizeCmp   :: CollectionSlot s rs (k, v) -> Ordering -> Term rs ci Int -> HsPred rs ci
      PAll/PAny  :: CollectionSlot s rs (k, v) -> ElemPred v ci -> HsPred rs ci   -- bounded quantifier over elements

- **FR4 — Structural element projection in terms/outputs.** A `Term` form to read
  an element field for use in an emitted event, without `TApp`:

      TLookupField :: CollectionSlot s rs (k, v) -> Term rs ci k -> Index velems f -> Term rs ci f

  This is what makes collection-derived outputs invertible by `solveOutput`
  (INV2) instead of opaque.

- **FR5 — Builder verbs.** `Keiki.Builder` surface mirroring the existing `(.=)` /
  `requireEq` ergonomics and the indexed-monad write-tracking, e.g.

      insertInto @"blockers" (key d.blockerId) (val …)
      adjust     @"blockers" (key d.blockerId) (sub @"status" .= d.status)
      requireMember    @"blockers" d.blockerId
      requireNoOpen    @"blockers"               -- PAll over an element predicate


## 4. Invariants that MUST be preserved (acceptance gates)

- **INV1 — Runtime replay stays mechanically derived.** `applyEventStreaming` /
  `applyEvents` / `reconstitute` reconstruct collection state with **no
  hand-written `apply`**. Approach 3 ("direct MultiDecider with hand-written
  `apply`") — catalogued in
  `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`
  (§"Approach 3") and rejected there as theoretically unsound because it forfeits
  the derived-`apply` property — must not be reintroduced. (The first draft cited
  `docs/research/multi-decider-via-state-refinement.md`; that is EP-20's
  now-superseded state-refinement note, which *discusses* and rejects Approach 3
  but is not its catalogue.) Replay re-runs the structural collection update
  forward against the command recovered by `solveOutput`.

- **INV2 — `solveOutput` inversion still works** for any edge whose output fields
  are structural (`TInpCtorField` / `TReg` / `TLookupField`). A collection edge
  must be invertible whenever a scalar edge with the same output shape would be.
  Concretely, `TLookupField` must join `TReg` on the *structural* side of
  `stepOne` (return `Just []`, recoverable from the replayed register file), not
  the opaque side with `TApp` (return `Nothing`). Under the post-EP-19 GSM
  output, "invertible" means: the **head** of the edge's `output` list inverts via
  `solveOutput` to recover the command, and any **tail** events (a multi-event
  collection edge) are matched by equality through the `InFlight` streaming
  wrapper — exactly as a scalar multi-event edge replays today.

- **INV3 — `checkHiddenInputs` understands collection updates.** A
  `UInsert`/`UAdjust` whose element data is recoverable from the emitted event(s)
  must **not** be flagged; one whose element data is *not* on the wire (a silent
  collection mutation) **must** be flagged, exactly as scalar slots are today.
  Note the post-EP-19 shape of the check (`src/Keiki/Core.hs`,
  `checkHiddenInputs`): for a non-empty `output` *list* it groups `OPack`s by
  `InCtor` name and flags a slot only if the **union** of fields visited across
  *all* of the edge's emitted events leaves it unrecovered; an `output = []`
  (ε-) edge whose `update` reads the input is flagged outright. So a collection
  edge that recovers its element data jointly across two emitted events is clean,
  while a silent ε-edge insert is flagged.

- **INV4 — The output list stays *static* per edge (GSM, not data-dependent).**
  Post-EP-19, `Edge.output` is already `[OutTerm rs ci co]` and the formalism is a
  GSM: each `OutTerm` is one emitted event and the list length is fixed at
  edge-construction time. The invariant the collection feature must preserve is
  that this length stays **static** — independent of register/collection contents.
  A per-element mutation (`UInsert`/`UDelete`/`UAdjust`) is a register **update**,
  never a source of output multiplicity: an edge must not emit "one event per
  element of the collection", because a data-dependent output arity is exactly the
  *conditional output list* that `docs/research/gsm-widening-design.md` §10 defers,
  and it would defeat per-edge `checkHiddenInputs` decidability and the
  well-definedness of `composeEdge`'s chain expansion. (This supersedes the first
  draft's "`Edge.output` is not widened / letter-FST settled direction" framing,
  which predated the 2026-05-16 GSM reversal. MasterPlan 7's settled direction is
  GSM widening (EP-19); EP-20's state refinement is *Superseded*.)

- **INV5 — Backward compatibility.** Existing scalar aggregates
  (`Jitsurei.EmailDelivery`, `Jitsurei.UserRegistration`, `Jitsurei.OrderCart`)
  compile and pass unchanged; all new constructors are additive.

- **INV6 — NoThunks discipline.** Collection slot writes force enough structure
  to avoid thunk towers under long-running replay, consistent with `setSlotN`'s
  WHNF bang and the `NoThunks (RegFile rs)` instance (`Keiki.NoThunks`, EP-23).
  A lazy `Map`/`[]` spine accumulated across thousands of replayed events is the
  failure mode to design against.


## 5. The crux / primary feasibility risk

**FR6 — Symbolic translation of collection guards (`src/Keiki/Symbolic.hs`).**
This is make-or-break and should be decided *before* building. keiki's
distinctive build-time capability — SBV/z3 single-valuedness (`isSingleValuedSym`)
and emptiness/reachability (`symIsBot`, `symSat`) over `HsPred` — is already
**shipped** (MasterPlan 2 EP-2), over a quantifier-free predicate set (`PEq`,
`PInCtor`, the Boolean connectives). Collection guards would translate to z3's
**array** and **finite-set** theories — possible in principle but materially
harder than the current set, and `PAll`/`PAny` introduce quantification, which can
make single-valuedness checks undecidable or impractically slow. Choose the v1
contract explicitly:

- **Option A (full symbolic).** Translate `PMember` / `PSizeCmp` / `PAll` to SMT
  arrays/sets. Highest value (Intention's lifecycle guards become verifiable),
  highest effort, real risk that quantified guards defeat the single-valuedness
  gate.

- **Option B (graceful degradation — recommended for v1).** Keep collection
  guards runtime-evaluable and replay-sound, but have the symbolic checker
  **explicitly classify collection-guarded edges as "not symbolically verified"**
  via a named, queryable status rather than silently passing or failing. This
  preserves verification for the scalar part of every aggregate and is honest
  about the boundary. A later EP can upgrade specific guard forms to Option A.

The choice determines whether this feature delivers keiki's headline guarantee
for Intention-shaped aggregates or "merely" restores ergonomics plus a clean
`checkHiddenInputs`. Both are worth shipping; only A removes the asterisk.


## 6. Acceptance criteria (worked example)

Add a `jitsurei` aggregate — `BlockerBoard`, a stand-in mini-`Intention` — with a
`Map BlockerId BlockerState` register and commands `AddBlocker`,
`ResolveBlocker`, `EscalateBlocker`, plus a lifecycle guard ("cannot close the
board while any blocker is unresolved"). It must:

1. be authored with **zero `TApp`** (FR2–FR5);
2. have `reconstitute` over random command sequences produce the correct `Map`
   (INV1) — a QuickCheck property test (the suite's `hspec` + `QuickCheck` stack),
   mirroring the existing example test style;
3. pass `checkHiddenInputs` clean, while a deliberately-silent collection
   mutation (element data not on the wire) *fails* it (INV3);
4. have `solveOutput` invert every edge whose output is structural, including an
   edge that emits a `TLookupField`-derived field (INV2);
5. under the chosen FR6 option, either verify symbolically (A) or report its
   collection-guarded edges as explicitly-unverified (B), asserted by a test;
6. leave all existing example aggregates and their suites green (INV5), with the
   z3-dependent symbolic tests behaving as today.


## 7. Non-goals

- **Data-dependent output arity** — an edge emitting a number of events that
  depends on collection contents (e.g. one `ElementAdded` per map entry). This is
  the *conditional output list* deferred by `gsm-widening-design.md` §10 and is
  ruled out by INV4. (Note: `Edge.output` *is* already a static list post-EP-19;
  the non-goal is data-dependent *length*, not lists per se. The first draft
  listed "widening `Edge.output` to a list" here as a *Cancelled* path — that was
  reversed on 2026-05-16 and is now the shipped foundation.)
- Hand-written `apply` / `evolve` for collections (violates INV1).
- Cross-aggregate collections or inter-stream references. A sub-entity that needs
  its own identity and lifecycle *across* streams is a separate aggregate, not a
  collection register — see §8.
- Runtime concerns (event-store batching, transactions, idempotency). keiki is
  the pure core; the runtime adapter (keiro) owns those.


## 8. Alternative, if this proves not worth the cost

If FR6 makes the symbolic story intractable, the consuming application has two
fallbacks that do not require this feature:

- **Sub-entity-as-aggregate.** Model each sub-entity instance (each blocker, each
  action) as its own small *scalar* `SymTransducer` on its own stream, coordinated
  by a process manager. No collection registers; full keiki guarantees per
  sub-aggregate. Cost: more streams and cross-stream coordination, and it departs
  from designs (like Rei's) that deliberately keep an aggregate's sub-entities in
  one stream.

- **Hand-rolled decider behind the runtime's store adapter.** Run the
  collection-heavy aggregate as a plain `decide`/`evolve` against the event store
  directly, not as a `SymTransducer`. It runs, but forfeits keiki entirely for
  that aggregate (no derived `apply`, no symbolic checks) — the thing this feature
  exists to avoid.

The existence of these fallbacks means the feature is an *improvement*, not a
blocker: it is the difference between Intention-shaped aggregates being
first-class keiki citizens versus being modeled around keiki's grain.
