---
id: 60
slug: first-class-collection-registers-design-gated
title: "First-class collection registers, design-gated"
kind: exec-plan
created_at: 2026-06-06T14:41:11Z
intention: "intention_01ktensqv9ecmv5cd5jrbcfej7"
master_plan: "docs/masterplans/14-keiki-and-keiki-codec-json-dsl-improvements-surfaced-by-the-seihou-consumer-audit.md"
---

# First-class collection registers, design-gated

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

keiki is a Haskell library for building *symbolic-register transducers*: a way to
describe an event-sourced aggregate (a thing whose current state is rebuilt by
replaying a log of past events) as a small state machine whose edges carry a
*guard* (a condition on the current state and the incoming command), an *update*
(how the registers — the named state fields — change), and an *output* (the
event(s) the edge emits). keiki's distinctive promise is that you never hand-write
the replay function: it *derives* event-to-state replay by inverting each edge's
output, and it certifies at build time, with an SMT solver (z3), that the schema is
well-formed (the event uniquely determines the command, no input data is silently
hidden, every edge is reachable and single-valued).

Today that promise holds cleanly only for *scalar* register slots — a slot holding
one `Int`, one `Bool`, one enum. The moment a slot holds a **collection** (a
`Map`, a `Set`, a `[list]`) and you want to mutate it *per element* (insert one
entry, delete one key, adjust one element's field) or *guard on its contents*
("this key is already present", "no element is still open"), keiki forces you to
escape into an **opaque closure** — a Haskell function `TApp1 (\m -> Map.insert k v m) ...`
that captures the key and value where no analysis can see them. That escape works
at runtime but silently surrenders all three of keiki's build-time guarantees for
the collection-bearing aggregate: the event-to-command inverter (`solveOutput`)
goes blind, the hidden-input check (`checkHiddenInputs`) is defeated, and the
symbolic single-valuedness checker collapses the guard to a meaningless free
Boolean.

After this change (if it ships — see the gate below), an author can declare a slot
as a keyed collection and express per-element insert/delete/update and content
guards through a **structural AST vocabulary** — real syntax-tree nodes the
analyses can read — so that collection-bearing aggregates become first-class keiki
citizens while runtime replay stays mechanically derived (no hand-written
`apply`). Concretely, you will be able to author a `BlockerBoard` mini-aggregate (a
`Map BlockerId BlockerState` of blockers with a "can't close the board while any
blocker is unresolved" lifecycle guard) with **zero `TApp`**, watch it
`reconstitute` correctly over a battery of command sequences, see
`checkHiddenInputs` pass it clean (and *fail* a deliberately-silent mutation), see
`solveOutput` invert an edge that emits a collection-derived field, and read an
*honest, queryable* symbolic-analysis status for its collection-guarded edges.

**This is a design-gated plan.** It is the only plan in MasterPlan 14 that touches
keiki's core formalism (the `Term` / `Update` / `HsPred` syntax trees and the
symbolic layer). It deliberately *opens* with a design/ratification milestone (M1)
that produces a working prototype plus a written analysis and then **STOPS** for an
explicit maintainer GO/NO-GO before any change is made to `src/Keiki/`. A NO-GO is a
legitimate outcome: collections stay opaque-`TApp`-only and the consumer uses the
fallbacks catalogued in §8 of the design note. The implementation milestones (M2
onward) do not start until a GO is recorded in the Decision Log. This mirrors the
ratification gate of EP-47 (the prior core-touching plan) exactly; see
`docs/masterplans/13-keiki-api-improvements-surfaced-by-the-rei-migration.md`, whose
EP-47 M1 "is a hard ratification gate, not an ordinary first milestone: it produces
the research note, a prototype, and a written analysis/recommendation, then STOPS
for an explicit maintainer go/no-go before any [core] change."


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented
here, even if it requires splitting a partially completed task into two ("done" vs.
"remaining"). This section must always reflect the actual current state of the work.

- [x] M1 (design + ratification gate) — prototyped the structural collection
      vocabulary in `test/Keiki/CollectionSpike.hs` *without touching* `src/Keiki/`;
      demonstrated zero-`TApp` authoring of `BlockerBoard`; showed the `solveOutput`
      (`stepOne` recoverability) and `checkHiddenInputs` (union-coverage) behavior on
      the structural shapes; wrote the FR6 Option A vs B decision (recommend **B**);
      reconciled with the three Seihou cases (need flat-list ergonomics, not the
      symbolic story); confirmed INV1–INV6 satisfiable with mechanical evidence per
      invariant (18 hspec examples, part of 322 total, 0 failures, 0 warnings). See
      the "M1 Ratification Analysis" section. **STOPPED for maintainer GO/NO-GO.**
      (2026-06-06)
- [x] GATE: maintainer decision recorded in the Decision Log — **NO-GO** on the core
      change, **signpost-first** alternative chosen (follow-up plan EP-67). M2–M5 are
      deferred, not pursued. (2026-06-06)
- [~] M2–M5 (GATED) — **NOT pursued** (NO-GO at the gate). Deferred until a real
      consumer with a genuine keyed-collection in-aggregate invariant appears; revisit
      this gate with that concrete shape (and prefer the flat-list variants identified
      in the Seihou reconciliation). The cheap guardrail lives in EP-67 instead.
        - M2 (FR1 slot kinds + FR2 `UInsert`/`UDelete`/`UAdjust`) — deferred.
        - M3 (FR3 guards + FR4 `TLookupField`) — deferred.
        - M4 (FR6 Option B status) — deferred.
        - M5 (FR5 builder verbs + `BlockerBoard` suite) — deferred.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- The design note (`docs/research/collection-registers-design.md`) §6 acceptance
  criterion 2 calls for "a QuickCheck property test (the suite's `hspec` +
  `QuickCheck` stack)". That stack does **not** exist in this repo: both
  `keiki.cabal`'s `keiki-test` stanza and `jitsurei/jitsurei.cabal`'s
  `jitsurei-test` stanza depend on `hspec` only — there is no `QuickCheck` or
  `hedgehog` dependency, and `test/Spec.hs` / `jitsurei/test/Spec.hs` are manual
  aggregators (explicit `import qualified … Spec` lines, not `hspec-discover`).
  This matches the finding recorded in MasterPlan 13's Surprises & Discoveries.
  Consequence: the reconstitute "property" in this plan is written as a **finite
  enumeration** of command sequences, not a generator-driven QuickCheck property.
- The design note's top matter (Status line and the 2026-05-20 "Consumer
  reassessment") says **"No committed consumer as of 2026-05-20"** because Rei's
  Intention withdrew. **That is now stale.** The Seihou consumer
  (`/Users/shinzui/Keikaku/bokuno/keiro-runtime-jitsurei`) has three verified
  whole-list-in-command cases (see Context and Orientation), reviving the design's
  motivation. M1 must reconcile the design with these concrete cases.

- **M1 finding — the Seihou cases need only whole-list emptiness, not keyed
  membership.** Spot-checking the three committed cases on 2026-06-06 confirmed all
  three are flat `[a]` slots assigned wholesale (`B.slot @"x" =: d.x`), but the
  sharper discovery is their *in-keiki guard*: `IncidentCommand/Domain/Incident.hs`
  lines 378 and 428 guard with `B.requireGuard (B.reg @"activeResourceIds" .== lit [])`
  — a whole-list **emptiness** check, which is *already structural today* (a `PEq`
  over a list literal), needing no collection vocabulary at all. The hospital cases
  (`Capacity.hs`, `Hospital.hs`) likewise store the whole precomputed list and push
  append/remove/membership entirely outside keiki. **Consequence for the gate:** the
  committed consumer does **not** exercise per-element structural updates or
  `PMember`/`PAll` at all today; its only in-aggregate collection guard is emptiness,
  already covered. The collection feature would be an *ergonomic + future-proofing*
  improvement for Seihou (letting it move append/remove/membership invariants back
  inside keiki structurally), not a current blocker. This materially lowers the
  urgency and argues for the cheaper FR6 Option B. (verified 2026-06-06)
- **M1 finding — the design note's `stepOne`/`TApp` claim is stale; current code
  returns `Just []`, not `Nothing`.** The note's §1 point 2 says `gatherInpEntries`/
  `stepOne` "return `Nothing` for `TApp1` and `TApp2`". The *current* code
  (`src/Keiki/Core.hs` lines 1349–1359, verified 2026-06-06) returns `Just []` for
  `TApp1`/`TApp2`/`TArith` — they are skipped and verified forward by EP-47's
  recompute-and-verify, contributing no command information but **not** breaking the
  gather. The EP-60 plan's Context section already reflects the current behavior; the
  spike models it faithfully (`stepOneSlots` never returns `Nothing`). The real INV2
  distinction is therefore *visibility* (register-recoverable vs analysis-blind
  closure), not `Just`-vs-`Nothing`. FR4's `TLookupField` must classify as
  register-recoverable (`FromRegisters` in the spike), joining `TReg`. (verified
  2026-06-06)
- **M1 deliverable — the ratification spike compiles and passes.**
  `test/Keiki/CollectionSpike.hs` (18 hspec examples, part of the 322-example
  `keiki-test` run, 0 failures, 0 warnings) models the FR1–FR6 vocabulary as a local
  mini-AST and demonstrates: zero-`TApp` authoring of `BlockerBoard`; INV1 derived
  replay matching a reference oracle; INV2 `TLookupField` joining the structural side;
  INV3 flagging a silent ε-edge insert while passing an on-wire insert; INV4 static
  output arity; INV6 forced long replay; and FR6 Option B's named, queryable
  `SkippedCollectionGuard` status. No `src/Keiki/` file was touched. (2026-06-06)


## Decision Log

Record every decision made while working on the plan.

- Decision: Structure this as a design-gated plan, exactly like EP-47 in
  MasterPlan 13. M1 produces a prototype + written analysis and then STOPS for an
  explicit maintainer GO/NO-GO before any edit to `src/Keiki/`. M2+ are gated behind
  a recorded GO; a NO-GO is a legitimate outcome (collections stay opaque-`TApp`,
  the consumer uses the §8 fallbacks).
  Rationale: this is the only plan in MasterPlan 14 that touches keiki's core
  formalism (the `Term`/`Update`/`HsPred` ASTs and the symbolic layer). The
  maintainer must review prototype-backed evidence before committing to an
  irreversible-in-spirit change to the foundation.
  Date: 2026-06-06

- Decision: Redirect the consumer audit's flat list-term proposal (`tCons`,
  `tAppend`, `tRemove`, `tMember`, `tNotMember`, `tLength`) to the keyed-collection
  vocabulary of `docs/research/collection-registers-design.md` (FR1 slot kinds, FR2
  structural `Update`s, FR3 structural guards, FR4 `TLookupField`, FR5 builder
  verbs).
  Rationale: the audit's flat ops are sound *only if* they avoid the three traps the
  design note §1 identifies — they must be structural AST nodes (not `TApp` sugar),
  symbolic degradation must be honest and queryable (not a silent opaque pass), and
  output arity must stay static (no "one event per element"). The keyed-collection
  vocabulary is the form that satisfies all three. See "Why the naive proposal is
  insufficient" below.
  Date: 2026-06-06

- Decision: Recommend FR6 Option B (graceful, queryable degradation) as the v1
  contract, subject to M1 ratification.
  Rationale: Option A (full SMT array/finite-set translation, plus quantifiers for
  `PAll`/`PAny`) is materially harder than keiki's current quantifier-free predicate
  set and risks defeating the single-valuedness gate. Option B keeps collection
  guards runtime-evaluable and replay-sound while classifying collection-guarded
  edges as explicitly "not symbolically verified" via a *named, queryable* status —
  honest about the boundary, and preserving verification for the scalar part of
  every aggregate. A later EP can upgrade specific guard forms to Option A. The
  Seihou cases (set-like membership over `[a]`) appear to need only Option B.
  Date: 2026-06-06

- Decision: Treat the design note's "no committed consumer" status as superseded by
  the Seihou consumer.
  Rationale: Seihou has three verified `[a]`-register cases that carry a whole
  precomputed list on the command and store it wholesale, pushing append/remove/
  member invariants outside keiki. This is exactly the value-object-collection case
  the note was waiting for; the gate must reconcile the design with these cases.
  Date: 2026-06-06

- GATE DECISION: **NO-GO** on the core-formalism change (FR1–FR6 / milestones M2–M5),
  choosing the **signpost-first** alternative instead.
  Rationale: M1 established that (a) the committed consumer (Seihou) is not blocked — its
  only in-keiki collection guard is whole-list emptiness, already structural; (b) the real
  thing future consumers "trip over" is *not knowing* that an opaque whole-collection `=:`
  silently surrenders keiki's symbolic + hidden-input guarantees, which is a *discoverability*
  problem, not a missing-AST problem; and (c) building the full feature speculatively (zero
  consumers exercising the hard keyed path) risks both a wrong, irreversible AST cut and
  entrenching a boundary anti-pattern (the §8 sub-entity-as-aggregate split is often the
  better design — it is exactly what the original Rei consumer chose). The cheapest move that
  actually prevents future tripping is therefore a **signpost**: a documentation recipe plus a
  `validateTransducer` warning (EP-56 is Complete and left its machinery extensible) that fires
  when a collection-typed slot is mutated opaquely — turning the silent footgun into a
  build-time nudge toward either the §8 split or a future first-class-collections request. This
  is scoped as a small follow-up plan, **EP-67**
  (`docs/plans/67-collection-slot-opaque-mutation-signpost-validatetransducer-warning-and-guidance.md`), under MasterPlan 14. The full
  feature (this plan's M2–M5) is **deferred, not rejected**: if a real consumer with a genuine
  keyed-collection in-aggregate invariant materializes, revisit this gate with that concrete
  shape in hand (and prefer the flat-list variants the Seihou reconciliation identified).
  Date: 2026-06-06
  (Chosen by the user at the M1 ratification gate.)


## M1 Ratification Analysis (the GO/NO-GO basis)

This section is the written analysis the ratification gate requires. It is backed by
the runnable prototype `test/Keiki/CollectionSpike.hs` (18 hspec examples, all green).
It records the FR6 recommendation, the Seihou reconciliation, and a per-invariant
satisfiability argument, and ends with the maintainer decision the gate is waiting on.


### A. FR6 decision — recommend **Option B** (graceful, queryable degradation)

The crux (design note §5) is whether collection guards translate to z3
(`src/Keiki/Symbolic.hs`).

- **Option A (full symbolic).** Translate `PMember`/`PNotMember`/`PSizeCmp` to z3
  array/finite-set theory and `PAll`/`PAny` to quantifiers. Highest value (collection
  lifecycle guards become machine-verified single-valued), but `PAll`/`PAny`
  quantifiers materially exceed keiki's current quantifier-free predicate set
  (`PEq`/`PInCtor`/`PCmp` + Boolean connectives) and carry a real risk of making
  `isSingleValuedSym` undecidable or impractically slow.
- **Option B (recommended).** Keep collection guards runtime-evaluable and
  replay-sound, but have `translateTermSym`/`translatePred` classify a
  collection-guarded edge via a **named, queryable status** rather than the *current*
  silent `SBV.free "neq"`/`"app1"` free Boolean (which a caller cannot distinguish
  from a real verification). The scalar part of every aggregate keeps full
  verification. The spike models this as `SymStatus = Verified | SkippedCollectionGuard String`
  and asserts a scalar guard is `Verified` while a `PMember` guard is
  `SkippedCollectionGuard "PMember"` — honest and inspectable.

**Why Option B for v1.** The committed consumer (Seihou) does not exercise symbolic
verification of collection guards *at all* today — its only in-keiki collection guard
is whole-list emptiness (`reg .== lit []`), already structural and already verifiable
as a scalar `PEq`. So Option A's extra power buys the committed consumer nothing right
now, while its quantifier risk could destabilize the single-valuedness gate that the
*scalar* aggregates (all of `jitsurei`) depend on. Option B is strictly honest (no
silent opaque pass — the audit's own bar, strengthened to *queryable*), preserves
scalar verification, and leaves a clean upgrade path: a later EP can lift specific
guard forms (`PMember`, `PSizeCmp`) to Option A's array theory without changing the
surface. **Recommendation: ship Option B as the v1 contract; defer Option A.**


### B. Seihou reconciliation — the consumer needs ergonomics, not the symbolic story

The three committed cases (`activeResourceIds`, `pendingReservationIds`,
`availableServiceLines`) are **flat `[a]` value-lists**, not keyed maps: the command
carries the whole precomputed list and the aggregate stores it wholesale via `=:`.
Their only in-aggregate collection guard is **emptiness** (`reg .== lit []`), already
structural today. Append/remove/membership invariants live *outside* keiki, in the
application that builds the list before issuing the command.

Implications for the design:

1. **The keyed-`Map`/`Set` vocabulary does not naturally subsume them.** They are
   ordered/flat lists with set-like membership semantics. If the feature ships, the
   Seihou-facing surface they would actually use is the **ordered-list variants**
   (`UAppend`/`URemoveBy`, a list-level `PMember`/`PSizeCmp`), not `UInsert`/`UAdjust`
   over a `Map`. The `BlockerBoard` worked example (a true `Map BlockerId BlockerState`
   with per-element lifecycle) remains the right *acceptance* vehicle because it
   exercises the harder keyed path, but M2's FR1/FR2 must include the flat-list
   variants for the consumer to benefit.
2. **Option B is more than adequate for Seihou.** Because these cases currently push
   their invariants outside keiki entirely (opaque whole-list `=:`), even Option B's
   "explicitly unverified, but structurally visible and `checkHiddenInputs`-checked"
   status is a strict improvement over today.
3. **The feature is not a current blocker for Seihou.** It is an ergonomic +
   correctness-surface improvement (moving append/remove/membership back inside keiki
   structurally). This lowers the urgency relative to the design note's original
   framing and supports the cheaper Option B.


### C. INV1–INV6 satisfiability — all six are satisfiable by the design

Each invariant is argued below and, where mechanically checkable, demonstrated by a
spike example.

- **INV1 (derived replay).** `runCUpdate` re-evaluates a structural update *forward*
  against the current board and the command recovered by `solveOutput` — no
  hand-written `apply`. Spike: `reconstitute` over eight command sequences matches an
  independent reference oracle. *Satisfiable.* In the real implementation this is new
  arms of `runUpdate` (`src/Keiki/Core.hs` line 885) for `UInsert`/`UDelete`/`UAdjust`.
- **INV2 (`solveOutput` invertibility).** `TLookupField` reads a collection element
  from the register file, so it is register-recoverable and must join `TReg` on the
  structural side of `stepOne` (return `Just []`), never the would-be-`Nothing` opaque
  side. Spike: `classify (KLookup …) == FromRegisters` (identical to a literal read)
  and `stepOneSlots (KLookup …) == Just []`, distinct from the `OpaqueRecompute`
  closure. *Satisfiable.* Real change: a `TLookupField` arm in `stepOne`
  (`src/Keiki/Core.hs` lines 1348–1359) returning `Just []`.
- **INV3 (`checkHiddenInputs` understands collection updates).** `updateReadsInput`
  (`src/Keiki/Core.hs` line 1514) must recurse into the new collection `Update`
  constructors' terms, and the union-coverage walk must treat a silent collection
  mutation like a silent scalar one. Spike: `checkHiddenEdge` flags a `[]`-output
  (ε-edge) insert and a partially-covered insert, while passing an insert whose
  element data is fully on the wire. *Satisfiable.* This is the soft-dependency seam
  with EP-56 (already Complete): EP-56 left its warning machinery extensible, so the
  collection arms are additive (`src/Keiki/Core.hs` Surprises in MasterPlan 14).
- **INV4 (static output arity).** A per-element mutation is a *register update*, never
  a source of output multiplicity; each edge's `output` list length is fixed at
  construction. Spike: `outputArity` is a function of the command only, constant `1`
  per edge, independent of board contents. *Satisfiable* and structurally enforced by
  the existing `[OutTerm rs ci co]` shape (no change needed; it is a non-goal to widen
  to data-dependent length).
- **INV5 (backward compatibility).** All new constructors are additive; no existing
  signature changes. Spike: real keiki `evalTerm (TLit 42)` still evaluates unchanged;
  all 304 pre-existing examples stay green alongside the 18 new ones. *Satisfiable.*
- **INV6 (NoThunks discipline).** Collection slot writes must force enough structure
  to avoid thunk towers. Spike: a 2000-command replay over `Data.Map.Strict` (strict
  in values) forces fully (the summed severities are computed, proving no bottom/leak).
  *Satisfiable.* Real change: extend `setSlotN`'s WHNF discipline and the
  `NoThunks (RegFile rs)` instance (`src/Keiki/NoThunks.hs`) to the collection element
  type, using strict-spine containers.

**Conclusion of the analysis:** the design note's vocabulary, with FR6 Option B and
the flat-list variants the Seihou cases need, satisfies all six invariants; the
prototype demonstrates each mechanically-checkable one. The cost is moderate and
additive; the only formalism risk (FR6 quantifiers) is sidestepped by Option B. The
one caveat the maintainer should weigh against GO is **urgency**: the committed
consumer is not currently blocked (§B.3), so this can also be reasonably deferred.


### D. The decision

**STATUS: awaiting maintainer GO/NO-GO.** Per the gate, M2–M5 do not begin until a GO
is recorded in the Decision Log above. A NO-GO is legitimate: collections stay
opaque-`TApp`-only and Seihou keeps its current whole-list `=:` storage plus the §8
fallbacks. Either way, the M1 spike and this analysis are committed (additive, no core
change).


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

- **M1 (ratification gate) — complete, awaiting decision.** The prototype
  (`test/Keiki/CollectionSpike.hs`, 18 green examples, no `src/Keiki/` change) and the
  written analysis (the "M1 Ratification Analysis" section above) deliver exactly what
  the gate asked for: a `TApp`-free authoring demonstration, the inverter/hidden-input
  behavior on structural shapes, a prototype-backed FR6 **Option B** recommendation, a
  Seihou reconciliation (the consumer needs ergonomics + flat-list variants, not the
  symbolic story), and an INV1–INV6 satisfiability argument with mechanical evidence
  for each checkable invariant. The headline finding that reframes the original vision:
  the committed consumer's only in-keiki collection guard is whole-list emptiness
  (already structural), so this feature is an ergonomic/correctness-surface improvement
  rather than a current blocker — which both supports the cheaper Option B and means a
  NO-GO/deferral has a low consumer cost.
- **Gate outcome: NO-GO, signpost-first.** The maintainer chose to *not* build the core
  formalism change (M2–M5) and instead address the real, recurring problem — consumers not
  realizing an opaque whole-collection `=:` silently surrenders keiki's guarantees — with a
  cheap, reversible guardrail: a documentation recipe plus a `validateTransducer` warning on
  opaque mutation of a collection-typed slot. That work is the follow-up plan **EP-67**
  (`docs/plans/67-collection-slot-opaque-mutation-signpost-validatetransducer-warning-and-guidance.md`). The full feature is deferred, not
  rejected; revisit this gate if a real keyed-collection consumer appears. This plan (EP-60) is
  therefore complete at its defined terminal state — the ratification gate — with M2–M5
  intentionally not pursued.


## Context and Orientation

This section assumes you know nothing about keiki. Read it before anything else.
Every file is named by its full repository-relative path from the repo root
`/Users/shinzui/Keikaku/bokuno/keiki`. The authoritative design this plan
*implements* (subject to the gate) is `docs/research/collection-registers-design.md`
— read it in full; this plan summarizes it self-containedly but references it for
detail.


### What a keiki transducer is, in plain terms

A *register file* is the aggregate's state: a list of named, typed slots. In keiki a
slot list has kind `[Slot]` where a `Slot` is a `(Symbol, Type)` pair — for example
`'("severity", Severity)` or `'("activeResourceIds", [ResourceId])`. The type
`RegFile rs` holds the values for slot list `rs` (defined in `src/Keiki/Core.hs`).

A *transducer* is a state machine. Each *edge* carries:

- a **guard** — a value of type `HsPred rs ci` (`ci` is the command/input symbol
  type), a small predicate AST testing the current registers and the incoming
  command;
- an **update** — a value of type `Update rs w ci`, describing which slots change
  (`w` is the type-level list of written slot names);
- an **output** — `[OutTerm rs ci co]`, a *static* list of events to emit (`co` is
  the event/output symbol type).

You never write the replay function. keiki *derives* event-to-state replay: given an
observed event, `solveOutput` (in `src/Keiki/Core.hs`) **inverts** the edge's output
to recover the command that produced it, then re-runs the edge's update forward
against the registers accumulated so far. That is the whole point of the library:
"the event uniquely determines the command, certified at build time."


### The three syntax trees this plan touches

Verified against `src/Keiki/Core.hs` on 2026-06-06.

**`Term rs ci ifs r`** (around line 256) — an expression producing a value of type
`r`. Its constructors:

```haskell
data Term (rs :: [Slot]) (ci :: Type) (ifs :: [Slot]) (r :: Type) where
  TLit          :: r -> Term rs ci ifs r
  TReg          :: Index rs r -> Term rs ci ifs r
  TInpCtorField :: InCtor ci ifs -> Index ifs r -> Term rs ci ifs r
  TApp1         :: (a -> r) -> Term rs ci ifs a -> Term rs ci ifs r
  TApp2         :: (a -> b -> r) -> Term rs ci ifs a -> Term rs ci ifs b -> Term rs ci ifs r
  TArith        :: (Num r, Typeable r) => NumOp -> Term rs ci ifs r -> Term rs ci ifs r -> Term rs ci ifs r
```

The first three are **structural** — the solver and the inverter can read them.
`TLit` is a constant; `TReg ix` reads register slot `ix`; `TInpCtorField ic ix`
reads field `ix` of the command. `TApp1`/`TApp2` are **opaque** escape hatches: they
carry a raw Haskell function the solver cannot see, capped at arity 2 — which is why
`Map.insert :: k -> v -> Map k v -> Map k v` (arity 3) cannot even be expressed as
one `TApp`. `TArith` is structural *when* the numeric type is in the SBV registry,
opaque otherwise.

**`HsPred rs ci`** (around line 483) — the guard AST:

```haskell
data HsPred (rs :: [Slot]) (ci :: Type) where
  PTop    :: HsPred rs ci
  PBot    :: HsPred rs ci
  PAnd    :: HsPred rs ci -> HsPred rs ci -> HsPred rs ci
  POr     :: HsPred rs ci -> HsPred rs ci -> HsPred rs ci
  PNot    :: HsPred rs ci -> HsPred rs ci
  PEq     :: (Eq r, Typeable r) => Term rs ci ifs1 r -> Term rs ci ifs2 r -> HsPred rs ci
  PInCtor :: InCtor ci ifs -> HsPred rs ci
  PCmp    :: (Ord r, Typeable r) => Cmp -> Term rs ci ifs1 r -> Term rs ci ifs2 r -> HsPred rs ci
```

There is no collection-content predicate; "is this key a member?" can only be
written by lifting `Map.member` through an opaque `TApp` inside a `PEq`, which the
solver reads as a fresh free Boolean.

**`Update rs w ci`** (around line 385) — how registers change:

```haskell
data Update (rs :: [Slot]) (w :: [Symbol]) (ci :: Type) where
  UKeep    :: Update rs '[] ci
  USet     :: KnownSymbol s => IndexN s rs r -> Term rs ci ifs r -> Update rs '[s] ci
  UCombine :: Update rs w1 ci -> Update rs w2 ci -> Update rs (Concat w1 w2) ci
```

Crucially, `runUpdate (USet ix t) regs ci = setSlotN ix (evalTerm t regs ci) regs`
(line 812): a `USet` re-evaluates its term **forward** against the *current* register
file and command, and the term may read the prior slot value via `TReg`. So a
collection mutation written as `USet "blockers" (TApp1 (Map.insert k v) (TReg blockers))`
*does* replay correctly — the gap is not storage or replay, it is **structural
visibility**. FR2's job is to add structural `Update` constructors that carry
**terms** (not closures) so the analyses can see the mutation. The smart constructor
`combine` (line 404) carries a `Disjoint w1 w2` constraint that statically rejects
two writes to the same slot in one edge.


### How the three analyses read these trees (the exact integration sites)

These are the verified sites the implementation milestones must change.
`src/Keiki/Core.hs`:

- **`solveOutput` (line 1086)** and its helper **`gatherInpEntries` / `stepOne`
  (lines 1156–1176).** `stepOne` walks each output field and decides whether it
  contributes recoverable command information. The verified arms:

  ```haskell
  stepOne (TLit _)               _val _ = Just []          -- structural, no command info
  stepOne (TReg _)               _val _ = Just []          -- structural, recoverable from replayed regs
  stepOne (TInpCtorField ic2 ix) val ic1
    | icName ic1 == icName ic2 = Just [ByIndex ix val]     -- structural, carries the command field
    | otherwise                = Nothing
  stepOne (TApp1 _ _)            _val _ = Just []           -- opaque, skipped (recompute-and-verify)
  stepOne (TApp2 _ _ _)          _val _ = Just []           -- opaque, skipped
  stepOne (TArith _ _ _)         _val _ = Just []           -- skipped (recompute-and-verify)
  ```

  The key contrast for INV2: `TReg` returns `Just []` because it is recoverable from
  the *replayed register file* (structural side). `TApp1`/`TApp2` return `Just []`
  too, but as derived fields that are recomputed-and-verified forward (the EP-47
  mechanism) — they carry *no command information of their own*. FR4's
  `TLookupField` must join the **structural** side: it is an element read of a
  collection slot, recoverable from the replayed register file, so it returns
  `Just []` as a structural read (like `TReg`), keeping the edge invertible — not the
  opaque side. A collection-derived *command-carrying* field would be a
  `TInpCtorField`-shaped contribution; the point is `TLookupField` must not poison
  the edge the way an opaque `TApp` does.

- **`checkHiddenInputs` (around line 1188).** The build-time analysis that, for each
  edge, checks whether the emitted output(s) can mechanically recover the input on
  replay. For a non-empty output list it groups the emitted events' fields and flags
  a command slot only if the **union** of fields visited across *all* the edge's
  emitted events leaves it unrecovered; an `output = []` (ε-) edge whose `update`
  reads the input is flagged outright (it is silent on the wire). INV3 requires this
  walk to **understand** collection updates: a `UInsert`/`UAdjust` whose element data
  *is* on the wire must not be flagged; one whose element data is *not* on the wire (a
  silent collection mutation) **must** be flagged. The helper `updateReadsInput`
  (lines 1309–1311) currently knows only `UKeep`/`USet`/`UCombine`; it must learn the
  new collection constructors.

`src/Keiki/Symbolic.hs`:

- **`translateTermSym` (line 432) / `translatePred`** translate the ASTs to SBV
  (the bindings to z3). The verified opaque arms: `translateTermSym _env (TApp1 _f _t) = SBV.free "app1"`
  and `(TApp2 _f _a _b) = SBV.free "app2"` (lines 442–443) — a fresh, unconstrained
  symbolic variable carrying *no information*. A `PEq` over a non-symbolic operand
  likewise becomes a fresh free Boolean. So any guard branching on collection
  contents collapses to an opaque free Boolean today.
- **`isSingleValuedSym` (line 620)** and **`symIsBot` (line 601)** are the analyses
  FR6 must either extend (Option A) or honestly bypass with a queryable status
  (Option B). `symSatExt` is the full witness extractor. z3 is available via the
  `sbv` dependency.

`src/Keiki/NoThunks.hs` plus `setSlotN`'s WHNF bang (the `!`-forcing slot writer used
by `runUpdate`): INV6 requires collection slot writes to force enough structure to
avoid *thunk towers* (deferred, unevaluated computations piling up) under long
replay. A lazy `Map`/`[]` spine accumulated across thousands of replayed events is
the failure mode to design against.

`keiki.cabal` already depends on `containers` (line 72, so `Data.Map`/`Data.Set`
are available) and `sbv` (line 76). INV5 requires all new constructors to be
*additive* so existing example aggregates compile unchanged.


### Where worked examples and tests live (verified)

The worked-example aggregates live in the **`jitsurei`** sub-package (Japanese for
"worked example/case study"): library modules under `jitsurei/src/` (e.g.
`jitsurei/src/Jitsurei/EmailDelivery.hs`, `jitsurei/src/Jitsurei/UserRegistration.hs`,
`jitsurei/src/Jitsurei/OrderCart.hs`, `jitsurei/src/Jitsurei/LoanApplication.hs`),
with spec modules under `jitsurei/test/` registered in **both**
`jitsurei/jitsurei.cabal` (`exposed-modules` for the lib, `other-modules` for the
test) and the manual aggregator `jitsurei/test/Spec.hs`. The keiki library's own
unit/prototype specs live under `test/` and register in `keiki.cabal`'s
`other-modules` and `test/Spec.hs`. Both test suites are **hspec-only** (no
QuickCheck — see Surprises). The keiki suite is `keiki-test`; the examples suite is
`jitsurei-test`.

Build and test from the repo root `/Users/shinzui/Keikaku/bokuno/keiki`:

```bash
cabal build keiki
cabal test keiki-test
cabal test jitsurei-test
```


### The committed consumer — why now (the Seihou cases)

The design note was written for Rei's Intention aggregate, which then withdrew,
leaving "no committed consumer as of 2026-05-20". **That status is now stale.** The
Seihou consumer at `/Users/shinzui/Keikaku/bokuno/keiro-runtime-jitsurei` has three
verified cases of a whole list carried in a command and assigned wholesale (via the
`=:` builder operator) to a `[a]` register slot:

- `activeResourceIds :: [ResourceId]` —
  `services/incident-command/src/IncidentCommand/Domain/Incident.hs` (register slot
  declared in the slot list, carried as a command field on `DispatchResourceData`,
  assigned via `B.slot @"activeResourceIds" =: d.activeResourceIds`). Verified
  2026-06-06.
- `pendingReservationIds :: [TransferReservationId]` —
  `services/hospital-capacity/src/HospitalCapacity/Domain/Capacity.hs`.
- `availableServiceLines :: [ServiceLine]` —
  `services/hospital-capacity/src/HospitalCapacity/Domain/Hospital.hs`.

In all three, the **command carries the whole precomputed list** and the aggregate
just stores it; append/remove/member invariants live *outside* keiki, in the
application that builds the list before issuing the command. This is exactly the
value-object-collection case the design note was waiting for. Critically, these are
*set-like membership over `[a]`* — they look like flat ordered lists with
member/append/remove semantics, **not** keyed maps. Part of M1's job is to confirm
whether the keyed-Map/Set vocabulary subsumes them or whether flat-list variants
(`UAppend`/`URemoveBy`, `PMember` over a list) suffice, and to confirm Option B is
adequate for them (these cases currently push their invariants outside keiki
entirely, so even Option B's "explicitly unverified" status is a strict improvement
over today's opaque `=:` of a whole list).


### Why the naive audit proposal is insufficient (must be understood)

The consumer audit proposed flat list term operations:

```haskell
tCons, tAppend :: Term ... [a] -> ...
tRemove        :: Eq a => ...
tMember, tNotMember :: Eq a => Term ... a -> Term ... [a] -> HsPred rs ci
tLength        :: Term ... [a] -> Term ... Int
```

These are sound **only if** they avoid three traps the design note §1 identifies:

1. **They must be structural AST nodes, not `TApp` sugar.** If `tMember` or
   `tAppend` desugars to a `TApp` closure, it defeats `checkHiddenInputs`, defeats
   `solveOutput` invertibility, and defeats the symbolic checker — the exact
   guarantees the feature exists to restore. FR4 adds `TLookupField` *precisely* so
   that collection-derived **output** fields stay invertible: it must join `TReg` on
   the **structural** side of `gatherInpEntries`/`stepOne` (returning `Just []`,
   recoverable from the replayed register file), not the opaque `TApp` side
   (returning `Nothing`).

2. **Symbolic degradation must be honest and queryable, not silent.** A guard like
   `tMember` that silently becomes an opaque free SBV Boolean *silently defeats* the
   single-valuedness gate — the checker would report "single-valued" without having
   actually verified the collection-branching edge. FR6 Option B therefore requires a
   **named, queryable "not symbolically verified" status**, not a silent opaque
   pass. The audit's own criterion ("degrade to conservative opaque predicates, not
   incorrect solver claims") is close, but keiki's bar is stronger: the degradation
   must be *honest and queryable* — a caller must be able to ask "was this edge
   actually verified, or skipped?" and get a truthful answer.

3. **Static output arity must hold (INV4).** A collection op is a register
   **update**, never a source of "one event per element". An edge must not emit a
   number of events that depends on collection contents (data-dependent output
   length); that is the *conditional output list* the GSM-widening design defers, and
   it would defeat per-edge `checkHiddenInputs` decidability.

So this plan **accepts the need** the audit identified but **redirects the
implementation** to the design note's keyed-collection vocabulary, with FR6 Option B
(graceful, queryable degradation) as the recommended v1 contract.


### The functional requirements this plan carries (FR1–FR6)

Summarized self-containedly from `docs/research/collection-registers-design.md` §3
and §5; see the note for full sketches.

- **FR1 — Collection slot kinds.** A way to mark a slot's element schema so the AST
  knows it is a keyed collection (sketch: distinguished element types `MapReg k v`,
  `SetReg a`, `ListReg a`, or a `Collection c` class with associated key/element
  types). The element type `v` should itself be expressible as a sub-record so
  element fields are projectable (needed by FR4).
- **FR2 — Structural update combinators.** New `Update` constructors carrying
  **terms**, not closures:

  ```haskell
  UInsert :: CollectionSlot s rs (k, v) -> Term rs ci k -> Term rs ci v -> Update rs '[s] ci
  UDelete :: CollectionSlot s rs (k, v) -> Term rs ci k -> Update rs '[s] ci
  UAdjust :: CollectionSlot s rs (k, v) -> Term rs ci k -> ElemUpdate v ci -> Update rs '[s] ci
  -- ordered-list variants: UAppend, URemoveBy …
  ```

  where `ElemUpdate v ci` is itself a structural update over the element's
  sub-schema. These must compose under the existing `Disjoint`-checked `combine`:
  two different slots stay disjoint; two writes to the *same* collection slot in one
  edge must be rejected or explicitly sequenced.
- **FR3 — Structural guard combinators.** New `HsPred` constructors for collection
  content, evaluable at runtime and targetable by the symbolic layer:

  ```haskell
  PMember    :: CollectionSlot s rs (k, v) -> Term rs ci k -> HsPred rs ci
  PNotMember :: CollectionSlot s rs (k, v) -> Term rs ci k -> HsPred rs ci
  PSizeCmp   :: CollectionSlot s rs (k, v) -> Ordering -> Term rs ci Int -> HsPred rs ci
  PAll / PAny :: CollectionSlot s rs (k, v) -> ElemPred v ci -> HsPred rs ci   -- bounded quantifier over elements
  ```

- **FR4 — Structural element projection in terms/outputs.** A `Term` form to read an
  element field for an emitted event, without `TApp`:

  ```haskell
  TLookupField :: CollectionSlot s rs (k, v) -> Term rs ci k -> Index velems f -> Term rs ci f
  ```

  This is what makes collection-derived outputs invertible by `solveOutput` (INV2).
- **FR5 — Builder verbs.** A `Keiki.Builder` surface mirroring the existing `.=`/`=:`
  and `requireEq` ergonomics, e.g. `insertInto @"blockers" (key d.blockerId) (val …)`,
  `adjust @"blockers" (key d.blockerId) (sub @"status" .= d.status)`,
  `requireMember @"blockers" d.blockerId`, `requireNoOpen @"blockers"` (a `PAll`).
- **FR6 — Symbolic translation of collection guards (the crux; §5).** Make-or-break,
  decided in M1 *before* building. **Option A (full symbolic):** translate
  `PMember`/`PSizeCmp`/`PAll` to z3's array/finite-set theories — highest value,
  highest effort, real risk that quantified guards (`PAll`/`PAny`) defeat the
  single-valuedness gate. **Option B (graceful degradation — recommended):** keep
  collection guards runtime-evaluable and replay-sound, but have the symbolic checker
  **explicitly classify collection-guarded edges as "not symbolically verified"** via
  a named, queryable status, preserving verification for the scalar part of every
  aggregate. A later EP can upgrade specific guard forms to Option A.


### The invariants that MUST be preserved (acceptance gates INV1–INV6)

Summarized from `docs/research/collection-registers-design.md` §4.

- **INV1 — Runtime replay stays mechanically derived.** `applyEventStreaming` /
  `applyEvents` / `reconstitute` reconstruct collection state with **no hand-written
  `apply`**. The rejected "Approach 3 / direct MultiDecider with hand-written
  `apply`" must not be reintroduced. Replay re-runs the structural collection update
  forward against the command recovered by `solveOutput`.
- **INV2 — `solveOutput` inversion still works** for any edge whose output fields are
  structural (`TInpCtorField` / `TReg` / `TLookupField`). A collection edge must be
  invertible whenever a scalar edge with the same output shape would be — concretely,
  `TLookupField` joins `TReg` on the **structural** side of `stepOne` (returns
  `Just []`, recoverable from the replayed register file), not the opaque side.
- **INV3 — `checkHiddenInputs` understands collection updates.** A `UInsert`/`UAdjust`
  whose element data is recoverable from the emitted event(s) must **not** be flagged;
  one whose element data is not on the wire (a silent collection mutation) **must** be
  flagged, exactly as scalar slots are today.
- **INV4 — The output list stays *static* per edge.** A per-element mutation is a
  register update, never a source of output multiplicity. No "one event per element";
  the per-edge output length must be independent of register/collection contents.
- **INV5 — Backward compatibility.** Existing scalar aggregates
  (`Jitsurei.EmailDelivery`, `Jitsurei.UserRegistration`, `Jitsurei.OrderCart`,
  `Jitsurei.LoanApplication`) compile and pass unchanged; all new constructors are
  additive.
- **INV6 — NoThunks discipline.** Collection slot writes force enough structure to
  avoid thunk towers under long replay, consistent with `setSlotN`'s WHNF bang and
  the `NoThunks (RegFile rs)` instance in `src/Keiki/NoThunks.hs`. A lazy `Map`/`[]`
  spine accumulated across thousands of replayed events is the failure mode.


## Plan of Work

The work is organized as one ratification gate (M1) followed by four gated
implementation milestones (M2–M5). **M2–M5 do not begin until a maintainer GO is
recorded in the Decision Log.** A NO-GO closes the plan with no change to
`src/Keiki/`; the Seihou consumer then keeps its current opaque whole-list `=:`
storage (which already works at runtime) and the design note's §8 fallbacks remain
the path for any genuinely keyed-collection aggregate.


### Milestone M1 — Design ratification gate (prototype + analysis, NO core change)

**Scope.** Produce a working prototype that demonstrates the structural collection
vocabulary *without editing any file under `src/Keiki/`*, plus a written analysis
that lets the maintainer decide GO or NO-GO. The design already exists in
`docs/research/collection-registers-design.md`; M1 is "prototype + ratify the FR6
option + reconcile with the now-committed Seihou consumer", not "write the design
from scratch". This mirrors EP-47's M1 ratification gate exactly.

**What will exist at the end of M1.** A new scratch/spike module under `test/` (for
example `test/Keiki/CollectionSpike.hs`), registered in `keiki.cabal`'s
`other-modules` and in `test/Spec.hs`, that:

(a) **Prototypes the structural vocabulary** for the `BlockerBoard` worked example
   and/or the Seihou `[a]`-slot cases. Because M1 must not touch `src/Keiki/`, the
   prototype models the proposed `UInsert`/`UDelete`/`UAdjust`/`TLookupField`/
   `PMember`/… as a *local* mini-AST in the spike module (or as thin wrappers that
   compile to existing constructors only for demonstration), and shows by
   construction that authoring `BlockerBoard` needs **zero `TApp`** under the
   proposed vocabulary, and that the structural shapes feed `solveOutput` and
   `checkHiddenInputs` as designed. The aim is evidence, not the final
   implementation: prove FR2/FR4 authoring is `TApp`-free and that the inverter and
   hidden-input checker behave on the structural shapes.

(b) **Records the FR6 decision (Option A vs Option B) with evidence.** Demonstrate
   what `translateTermSym`/`translatePred` would do for a `PMember` guard under each
   option: Option A would need z3 array/finite-set theory (sketch the SBV calls and
   note the quantifier risk for `PAll`/`PAny`); Option B emits a *named, queryable*
   "unverified" status. The recommendation is **Option B** with the queryable status
   mechanism designed concretely (what the status value is, where
   `isSingleValuedSym`/`symIsBot` surface it, how a caller queries "was this edge
   verified or skipped?").

(c) **Reconciles with the three Seihou cases.** Determine whether the keyed
   Map/Set vocabulary subsumes the three `[a]` membership cases or whether flat
   ordered-list variants (`UAppend`/`URemoveBy`, `PMember` over a list) suffice. The
   working hypothesis (to be confirmed) is that the Seihou cases are *set-like
   membership over `[a]`* — flat lists, not keyed maps — and that Option B is
   adequate for them because they currently push their invariants outside keiki
   entirely, so any structural, queryable status is a strict improvement.

(d) **Confirms INV1–INV6 are all satisfiable** by the proposed design, with a short
   written argument per invariant (replay-forward derivation for INV1; `TLookupField`
   on the structural `stepOne` side for INV2; `updateReadsInput` extension for INV3;
   register-update-not-output-multiplicity for INV4; additivity for INV5; WHNF-forced
   collection writes for INV6).

**Commands to run.**

```bash
cabal build keiki
cabal test keiki-test
```

**Acceptance for M1.** The spike module compiles and its hspec cases pass,
demonstrating: zero-`TApp` authoring of the prototype aggregate; the inverter and
hidden-input behavior on the structural shapes; and a written FR6 recommendation,
Seihou reconciliation, and INV1–INV6 satisfiability argument captured *in this plan*
(Surprises & Discoveries and a new analysis subsection) plus, optionally, a short
research-note addendum. **Then STOP.** Record the maintainer GO or NO-GO in the
Decision Log before any M2 work begins.

**The gate.** This is a hard ratification gate. A NO-GO is legitimate and closes the
plan: collections stay opaque-`TApp`-only and the consumer uses the §8 fallbacks
(sub-entity-as-aggregate, or a hand-rolled decider behind the runtime store
adapter). A GO unlocks M2–M5. Record the decision verbatim with rationale and date.


### Milestone M2 (GATED) — Collection slot kinds and structural updates (FR1, FR2)

**Scope.** Behind a recorded GO, add to `src/Keiki/Core.hs`: the FR1 collection slot
kind machinery (so a slot's element schema is known to be a keyed collection), and
the FR2 structural `Update` constructors `UInsert`/`UDelete`/`UAdjust` (plus
ordered-list `UAppend`/`URemoveBy` if M1 found the Seihou cases need them), each
carrying **terms** not closures. Extend `runUpdate` (line 811) with arms for the new
constructors that re-evaluate forward against the current register file and command
(INV1). Ensure they compose under the `Disjoint`-checked `combine` (two writes to the
same collection slot in one edge are rejected or explicitly sequenced). Force enough
structure on collection slot writes to satisfy INV6 (extend `setSlotN`/the WHNF
discipline and the `NoThunks (RegFile rs)` instance in `src/Keiki/NoThunks.hs`).

**What will exist at the end.** A collection slot can be declared and mutated
per-element through structural `Update` constructors, and replay reconstructs the
collection with no hand-written `apply` (INV1). All existing aggregates still compile
(INV5, all-additive).

**Commands / acceptance.**

```bash
cabal build keiki
cabal test keiki-test
cabal test jitsurei-test
```

A small spike test forces a long replay sequence and asserts (via the existing
`NoThunks` machinery) that the collection slot has no residual thunks (INV6), and a
finite enumeration of insert/delete/adjust sequences reconstitutes the expected
`Map`/list (INV1). All existing suites stay green.


### Milestone M3 (GATED) — Structural guards and element projection (FR3, FR4)

**Scope.** Add the FR3 `HsPred` constructors `PMember`/`PNotMember`/`PSizeCmp`/
`PAll`/`PAny` (with runtime evaluation via the existing `evalPred`) and the FR4
`TLookupField` term to `src/Keiki/Core.hs`. Wire `TLookupField` into
`gatherInpEntries`/`stepOne` (lines 1156–1176) on the **structural** side: it returns
`Just []` as a register-file-recoverable read (joining `TReg`), so an edge that emits
a `TLookupField`-derived field stays invertible by `solveOutput` (INV2) — never the
opaque `Nothing` side that `TApp1`/`TApp2` would. Extend `checkHiddenInputs` (line
1188) and its helper `updateReadsInput` (lines 1309–1311) to understand the new
collection `Update` constructors so a silent collection mutation (element data not on
the wire) is flagged while a mutation whose element data *is* recoverable is clean
(INV3).

**Integration with EP-56 (soft dependency).** EP-56
(`docs/plans/56-build-time-validation-and-diagnostics-validatetransducer-determinism-and-dead-edge-analysis.md`)
builds structured build-time validation/diagnostics machinery (`validateTransducer`,
determinism and dead-edge analysis). INV3 requires `checkHiddenInputs` /
`validateTransducer` to understand collection `Update` constructors. The intended
division of labor: **EP-56 lands its warning/diagnostic machinery in an extensible
shape, and this plan (M3) adds the collection arms to it.** If EP-56 is not yet
landed when M3 runs, M3 extends `checkHiddenInputs` directly (the integration point
named above) and the collection arms can be folded into EP-56's framework later.

**What will exist at the end.** Collection content guards and element-field reads are
authorable structurally; `solveOutput` inverts an edge that emits a
`TLookupField`-derived field (INV2); `checkHiddenInputs` passes a clean collection
edge and flags a deliberately-silent collection mutation (INV3).

**Commands / acceptance.**

```bash
cabal build keiki
cabal test keiki-test
```

Tests assert: `solveOutput` inverts a `TLookupField` edge; `checkHiddenInputs`
returns clean for a recoverable collection mutation and a `HiddenInputWarning` for a
silent one.


### Milestone M4 (GATED) — Symbolic translation per the ratified FR6 option

**Scope.** Implement the FR6 option ratified at the M1 gate in `src/Keiki/Symbolic.hs`.
For the recommended **Option B**: extend `translateTermSym`/`translatePred` so that a
collection guard does **not** silently become a meaningless `SBV.free` Boolean;
instead, the edge carrying it is classified, via a **named, queryable status**, as
"not symbolically verified". `isSingleValuedSym` (line 620) and `symIsBot` (line 601)
(and `symSatExt`) must surface this status truthfully — a caller must be able to
distinguish "verified single-valued" from "skipped because collection-guarded". The
scalar part of every aggregate keeps full verification. For **Option A** (only if
ratified): translate `PMember`/`PSizeCmp` to z3 array/finite-set theories, with
`PAll`/`PAny` quantifiers handled or explicitly bounded.

**What will exist at the end.** A collection-guarded edge has a *defined, honest*
symbolic-analysis status that a test can assert — never a silent opaque pass.

**Commands / acceptance.**

```bash
cabal build keiki
cabal test keiki-test
```

A test asserts the chosen FR6 status on a collection-guarded edge (Option B: the
edge reports "unverified" queryably; Option A: it verifies symbolically), and the
z3-dependent symbolic tests for scalar aggregates behave exactly as today.


### Milestone M5 (GATED) — Builder verbs, the BlockerBoard worked example, and the §6 acceptance suite

**Scope.** Add the FR5 builder verbs to `src/Keiki/Builder.hs` (`insertInto`,
`adjust`, `requireMember`, `requireNoOpen`/`PAll` helpers, etc.), mirroring the
existing `.=`/`=:`/`requireEq` ergonomics and the indexed-monad write-tracking. Add
the `BlockerBoard` worked-example aggregate as `jitsurei/src/Jitsurei/BlockerBoard.hs`
(a `Map BlockerId BlockerState` register with commands `AddBlocker`,
`ResolveBlocker`, `EscalateBlocker`, and a lifecycle guard "cannot close the board
while any blocker is unresolved"), registered in `jitsurei/jitsurei.cabal`
`exposed-modules`. Add the acceptance test suite as
`jitsurei/test/Jitsurei/BlockerBoardSpec.hs`, registered in `jitsurei/jitsurei.cabal`
`other-modules` and in `jitsurei/test/Spec.hs`.

**What will exist at the end.** The §6 worked example, authored with zero `TApp`,
passing all six acceptance criteria below.

**Acceptance (the design note's §6, quoted).** The `BlockerBoard` aggregate must:

1. be authored with **zero `TApp`** (FR2–FR5);
2. have `reconstitute` over command sequences produce the correct `Map` (INV1) —
   written as a **finite enumeration** of command sequences (the suite is hspec-only;
   no QuickCheck — see Surprises), mirroring the existing example test style;
3. pass `checkHiddenInputs` clean, while a deliberately-silent collection mutation
   (element data not on the wire) *fails* it (INV3);
4. have `solveOutput` invert every edge whose output is structural, including an edge
   that emits a `TLookupField`-derived field (INV2);
5. under the chosen FR6 option, either verify symbolically (A) or report its
   collection-guarded edges as explicitly-unverified (B), asserted by a test;
6. leave all existing example aggregates and their suites green (INV5), with the
   z3-dependent symbolic tests behaving as today.

**Commands / acceptance.**

```bash
cabal build keiki
cabal test keiki-test
cabal test jitsurei-test
```

All six criteria above hold; both suites are green.


## Concrete Steps

Run everything from the repo root `/Users/shinzui/Keikaku/bokuno/keiki`.

**M1 (always runnable now).**

1. Read `docs/research/collection-registers-design.md` in full, then re-read §1, §3,
   §4, §5, §6.
2. Re-verify the cited code sites by reading them: `src/Keiki/Core.hs` lines ~256
   (`Term`), ~385 (`Update`), ~483 (`HsPred`), ~811 (`runUpdate`), ~1086
   (`solveOutput`), ~1156–1176 (`gatherInpEntries`/`stepOne`), ~1188
   (`checkHiddenInputs`), ~1309 (`updateReadsInput`); `src/Keiki/Symbolic.hs` lines
   ~432 (`translateTermSym`), ~601 (`symIsBot`), ~620 (`isSingleValuedSym`);
   `src/Keiki/NoThunks.hs`.
3. Spot-check the Seihou cases in
   `/Users/shinzui/Keikaku/bokuno/keiro-runtime-jitsurei` (the three files named in
   Context and Orientation) to confirm they remain whole-list `=:` assignments.
4. Create `test/Keiki/CollectionSpike.hs`; register it in `keiki.cabal`
   `other-modules` and `test/Spec.hs` (add `import qualified Keiki.CollectionSpike`
   and include its spec in the aggregator). Build and test:

   ```bash
   cabal build keiki
   cabal test keiki-test
   ```

   Expected: the suite compiles and passes, with the spike's cases demonstrating the
   prototype vocabulary (zero `TApp`) and the inverter/hidden-input behavior.
5. Write the FR6 decision, the Seihou reconciliation, and the INV1–INV6
   satisfiability argument into this plan (Surprises & Discoveries plus a new
   analysis subsection), then **STOP** and record the maintainer GO/NO-GO in the
   Decision Log.

**M2–M5** follow the per-milestone scope and commands above, and begin **only** after
a GO is recorded. Commit M1 deliverables (the spike and analysis are additive, no
core change); commit each implementation milestone as it lands. Do not create a
feature branch — commit to `master` (the user's policy). Conventional Commit messages
with the trailers shown under Git/Process below.


## Validation and Acceptance

The headline, human-verifiable outcome is the §6 `BlockerBoard` worked example (M5),
whose six criteria are quoted under M5 above. Until the gate opens, the verifiable
outcome is M1: a compiling, passing spike that proves the structural vocabulary is
`TApp`-free and that the inverter and hidden-input checker behave on the structural
shapes, plus a written, prototype-backed FR6 recommendation and INV1–INV6
satisfiability argument.

For each milestone, "success" is the named `cabal test` command(s) exiting green with
the asserted behavior; "failure" is a compile error, a failing hspec example, or a
solver disagreement. Because the test suites are hspec-only, every "property"
(notably the INV1 reconstitute property and the INV6 thunk-tower check) is a finite
enumeration with explicit expected results — not a generator-driven QuickCheck
property. A novice can tell success from failure by the hspec summary line (e.g.
`N examples, 0 failures`) and by the specific assertions described in each milestone.

The deepest acceptance is *behavioral, not structural*: it is not enough that new
constructors compile; the plan succeeds only when authoring `BlockerBoard` needs zero
`TApp`, replay reconstitutes the correct `Map`, `checkHiddenInputs` distinguishes a
clean collection edge from a silent one, `solveOutput` inverts a `TLookupField` edge,
and the FR6 status is asserted truthfully — all proven by tests that fail before the
change and pass after.


## Idempotence and Recovery

M1 is fully repeatable and safe: it adds only a spike test module and plan prose;
re-running `cabal build`/`cabal test` is non-destructive. If the spike module already
exists, edit it in place rather than recreating it; if it is already registered in
`keiki.cabal`/`test/Spec.hs`, do not duplicate the registration.

M2–M5 are additive by construction (INV5): all new constructors and builder verbs are
new names, so re-running a milestone's edits is safe as long as you check whether a
constructor/verb already exists before adding it. The `Disjoint`-checked `combine`
guards against accidental double-writes to a slot. If a milestone's change breaks an
existing suite, that is an INV5 violation — revert the offending edit and reconsider;
do not weaken an existing fixture to make it pass. The whole plan is recoverable from
this file alone: if work is interrupted, the Progress checklist and the Decision Log
(especially the GATE entry) say exactly where things stand and whether M2+ are
unlocked.


## Interfaces and Dependencies

**Libraries.** `containers` (already a `keiki.cabal` dependency, line 72) supplies
`Data.Map`/`Data.Set`/list operations for the collection slot kinds. `sbv` (line 76)
plus z3 supply the symbolic layer for FR6. `hspec` is the only test framework
(no QuickCheck/hedgehog).

**Modules touched (only after a GO).** `src/Keiki/Core.hs` (the `Term`, `Update`,
`HsPred` ASTs; `runUpdate`; `solveOutput`/`gatherInpEntries`/`stepOne`;
`checkHiddenInputs`/`updateReadsInput`), `src/Keiki/Symbolic.hs`
(`translateTermSym`/`translatePred`; `isSingleValuedSym`/`symIsBot`/`symSatExt`),
`src/Keiki/Builder.hs` (FR5 verbs), `src/Keiki/NoThunks.hs` (INV6 forcing).
New: `jitsurei/src/Jitsurei/BlockerBoard.hs` and
`jitsurei/test/Jitsurei/BlockerBoardSpec.hs` (M5); `test/Keiki/CollectionSpike.hs`
(M1). Register new modules in **both** the relevant `.cabal` (`exposed-modules` /
`other-modules`) and the manual aggregator `test/Spec.hs` or `jitsurei/test/Spec.hs`.

**Signatures that must exist by the end of each gated milestone** (sketches from the
design note FR2–FR4; exact shapes settled during implementation):

```haskell
-- M2 (FR1/FR2), in src/Keiki/Core.hs
UInsert :: CollectionSlot s rs (k, v) -> Term rs ci k -> Term rs ci v -> Update rs '[s] ci
UDelete :: CollectionSlot s rs (k, v) -> Term rs ci k -> Update rs '[s] ci
UAdjust :: CollectionSlot s rs (k, v) -> Term rs ci k -> ElemUpdate v ci -> Update rs '[s] ci

-- M3 (FR3/FR4), in src/Keiki/Core.hs
PMember      :: CollectionSlot s rs (k, v) -> Term rs ci k -> HsPred rs ci
PNotMember   :: CollectionSlot s rs (k, v) -> Term rs ci k -> HsPred rs ci
PSizeCmp     :: CollectionSlot s rs (k, v) -> Ordering -> Term rs ci Int -> HsPred rs ci
PAll, PAny   :: CollectionSlot s rs (k, v) -> ElemPred v ci -> HsPred rs ci
TLookupField :: CollectionSlot s rs (k, v) -> Term rs ci k -> Index velems f -> Term rs ci f

-- M4 (FR6 Option B), in src/Keiki/Symbolic.hs: a named, queryable status surfaced
-- by isSingleValuedSym / symIsBot distinguishing "verified" from "skipped
-- (collection-guarded)".

-- M5 (FR5), in src/Keiki/Builder.hs
insertInto    :: ...  -- @"slot" (key …) (val …)
adjust        :: ...  -- @"slot" (key …) (sub @"field" .= …)
requireMember :: ...  -- @"slot" key  →  PMember guard
```

**Dependencies and phasing.** This is the **formalism-touching keystone** of
MasterPlan 14 and is **Phase 3**: it runs after the Phase 1 parallel plans and after
Phase 2's EP-56. It has a **soft dependency** on EP-56
(`docs/plans/56-build-time-validation-and-diagnostics-validatetransducer-determinism-and-dead-edge-analysis.md`):
INV3 needs `checkHiddenInputs`/`validateTransducer` to understand collection `Update`
constructors. EP-56 should land its warning/diagnostic machinery in an extensible
shape and this plan adds the collection arms; if EP-56 is not done, this plan extends
`checkHiddenInputs` directly. There are no hard dependencies — M1 (the gate) is
runnable today against the current tree.


## Git / Process

Commit to the current branch `master` — do **not** create a feature branch (the
user's policy). Use Conventional Commits. M1's deliverables (the spike module plus the
analysis written into this plan) ARE committed, because they are additive and touch no
core code. M2–M5 are committed as they land, only after a GO is recorded. Do not
commit as part of authoring this plan file.

Every commit on this plan carries these trailers:

```text
MasterPlan: docs/masterplans/14-keiki-and-keiki-codec-json-dsl-improvements-surfaced-by-the-seihou-consumer-audit.md
ExecPlan: docs/plans/60-first-class-collection-registers-design-gated.md
Intention: intention_01ktensqv9ecmv5cd5jrbcfej7
```


## Revision Notes

- 2026-06-06 — Initial authored version, fleshing out the skeleton. Structured as a
  design-gated plan mirroring EP-47's M1 ratification gate (see
  `docs/masterplans/13-...md`). Carries over FR1–FR6 and INV1–INV6 from
  `docs/research/collection-registers-design.md`, recommends FR6 Option B (queryable
  unverified status), redirects the consumer audit's flat-list proposal to the
  keyed-collection vocabulary, and records that the Seihou consumer revives the
  design's motivation (the note's "no committed consumer" status is now stale). Code
  sites re-verified against `src/Keiki/Core.hs` and `src/Keiki/Symbolic.hs` on
  2026-06-06; both test suites confirmed hspec-only (reconstitute "property" written
  as finite enumeration, not QuickCheck despite the note's §6 wording).
