---
id: 67
slug: collection-slot-opaque-mutation-signpost-validatetransducer-warning-and-guidance
title: "Collection-slot opaque-mutation signpost: validateTransducer warning and guidance"
kind: exec-plan
created_at: 2026-06-06T17:34:15Z
intention: "intention_01ktensqv9ecmv5cd5jrbcfej7"
master_plan: "docs/masterplans/14-keiki-and-keiki-codec-json-dsl-improvements-surfaced-by-the-seihou-consumer-audit.md"
---

# Collection-slot opaque-mutation signpost: validateTransducer warning and guidance

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This plan is the **signpost-first** resolution of MasterPlan 14's Req 4 (collections),
chosen at the EP-60 ratification gate
(`docs/plans/60-first-class-collection-registers-design-gated.md`, Decision Log: NO-GO).
EP-60's M1 analysis established that keiki will **not** (for now) add first-class
collection registers to the core formalism. The remaining problem worth solving is the
one future consumers actually *trip over*: when an author reaches for an **opaque
closure** (`TApp1`/`TApp2`) inside an edge **guard** to express a condition keiki's
structural predicate language can't — most often "is this key in the collection?", "are
all elements resolved?", a `Map.member`/`all`/`null` lifted through `TApp` — keiki's
symbolic single-valuedness and dead-edge analyses **silently** treat that guard as an
unconstrained free Boolean (`src/Keiki/Symbolic.hs` `translateTermSym` emits
`SBV.free "app1"`). The checks then *under-verify*: they report no determinism/dead-edge
problem not because the edge is sound, but because they couldn't see the guard. The
author believes keiki verified their collection-branching edge; it didn't. Nothing tells
them.

After this change, two things exist that did not before:

1. **A new, opt-in `validateTransducer` warning** — `OpaqueGuard` — that flags any edge
   whose guard predicate contains an opaque `TApp` term, with a message naming the edge
   and explaining that the symbolic analyses cannot see through it (so its
   single-valuedness was not actually verified). It is purely additive: a new
   `TransducerValidationWarning` constructor and a new `ValidationOptions` field
   (`warnOpaqueGuards`, default `False` to preserve the meaning of
   `defaultValidationOptions` for existing consumers). An author auditing symbolic
   coverage turns it on and gets a structured, pattern-matchable list of exactly which
   guards are invisible to the solver.

2. **A documentation recipe** — a short guide section that explains, honestly: storing a
   whole collection that arrives *structurally on the command* (the keiro-runtime-jitsurei
   `B.slot @"x" =: d.x` pattern) is fine and fully visible; the degradation happens only
   when you **guard on or derive outputs from** collection contents through an opaque
   `TApp`; the cheapest sound options today are (a) keep the collection's invariants in
   the application layer against the read model (what keiro-runtime-jitsurei does), or (b) split a
   lifecycle-bearing sub-entity into its own scalar aggregate (the §8
   "sub-entity-as-aggregate" path); and first-class collection registers are **deferred**
   (link EP-60) until a real keyed-collection consumer appears.

You can see it working two ways. (1) `cabal test keiki-test` runs a new spec proving that
an edge with an opaque collection-style guard produces an `OpaqueGuard` warning when
`warnOpaqueGuards = True`, that a fully-structural transducer produces none, and that the
warning stays silent under `defaultValidationOptions` (backward compatibility). (2) The
guide page renders the recipe with the three honest options and the EP-60 deferral
pointer.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M1: added the `OpaqueGuard` arm to `TransducerValidationWarning` and the
      `warnOpaqueGuards :: Bool` field to `ValidationOptions` (default `False` in
      `defaultValidationOptions`), in `src/Keiki/Core.hs`; exported `opaqueGuardWarnings`
      for parity with `hiddenInputWarnings`. (2026-06-06)
- [x] M1: added the structural walkers `termHasOpaqueApp` / `predHasOpaqueTerm` and the
      `opaqueGuardWarnings` producer; wired it into `validateTransducer`. (2026-06-06)
- [x] M1: extended `test/Keiki/ValidationSpec.hs` with three opaque-guard cases (fires when
      enabled + names the edge; none for the structural `cleanT`; silent — full `== []` —
      under `defaultValidationOptions`). (2026-06-06)
- [x] M1: `cabal build keiki` and `cabal test keiki-test` both pass (325 examples, 0
      failures; no new warnings on the touched files). (2026-06-06)
- [x] M2: added the "Opaque guards and collections" recipe subsection to
      `docs/guide/user-guide.md` §8 (structural storage is fine; opaque guards silently
      degrade; the `warnOpaqueGuards` audit; the three honest options + EP-60 deferral
      pointer), cross-linked from the §3.4 guards section. (2026-06-06)
- [x] Final: updated Surprises/Decision Log/Outcomes; all acceptance criteria verified. (2026-06-06)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **The signpost target is the opaque *guard*, not the opaque *mutation*.** The EP-60 M1
  reconciliation found that the three keiro-runtime-jitsurei collection cases store a whole list that
  arrives *structurally* on the command (`B.slot @"x" =: d.x`, i.e.
  `USet ix (TInpCtorField …)`), which is fully visible to every analysis — `solveOutput`
  inverts it and `checkHiddenInputs` sees the whole list on the wire. So an opaque
  *update* is not where the silent degradation lives (updates replay forward soundly
  regardless of opacity, and are never inverted). The degradation is in **guards** (and
  collection-derived *outputs*): an opaque `TApp` inside an `HsPred` becomes a free SBV
  Boolean, silently defeating the single-valuedness/dead-edge checks. This plan therefore
  flags opaque *guard terms*, which is the precise locus of the "you think it was
  verified but it wasn't" footgun. (Verified against `src/Keiki/Symbolic.hs`
  `translateTermSym` lines 461–462 and the keiro-runtime-jitsurei files on 2026-06-06.)

(More to be added during implementation.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Make the warning target **opaque guard terms** (an edge whose `HsPred`
  contains a `TApp1`/`TApp2`), rather than "opaque mutation of a collection slot" as
  originally framed at the EP-60 gate.
  Rationale: the precise analysis (see Surprises) shows an opaque *update* is not unsound
  — it replays forward correctly and is never inverted, so it surrenders nothing. The
  silent degradation is in *guards*: an opaque guard becomes a free Boolean that the
  symbolic determinism/dead-edge analyses cannot see, so they under-verify without
  saying so. Flagging opaque guards is the honest, high-value signpost; it also
  generalizes FR6 Option B's "queryable unverified status" idea onto the
  `validateTransducer` surface, for all opaque guards (collection or not). The doc recipe
  carries the collection-specific framing the gate asked for.
  Date: 2026-06-06

- Decision: Default the new check **off** (`warnOpaqueGuards = False` in
  `defaultValidationOptions`); it is an opt-in audit lint, not a soundness error.
  Rationale: opaque guards are sometimes legitimate and intentional, and existing
  consumers (including keiro-runtime-jitsurei) assert `validateTransducer defaultValidationOptions t == []`
  — turning this on by default could newly fail those assertions, a backward-compat
  break (INV-style). Keeping it opt-in preserves the meaning of `defaultValidationOptions`
  while giving authors a one-flag way to audit "which of my guards did the solver
  actually see?" The doc recipe is the always-visible part; the warning is the power
  tool. If experience shows default-on is wanted, revisit with evidence.
  Date: 2026-06-06

- Decision: Reuse the existing `EdgeRef s` locator and the additive warning-machinery
  shape EP-56 left in place, rather than introducing any new locator or restructuring
  `validateTransducer`.
  Rationale: MasterPlan 14's Integration Points and EP-56's Surprises commit every later
  validation warning to the typed `EdgeRef s` and an additive `TransducerValidationWarning`
  arm. This plan honors that: one new constructor, one new option field, one new producer
  concatenated into `validateTransducer`.
  Date: 2026-06-06


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

Both milestones landed as specified; the plan delivered the signpost-first resolution of
MasterPlan 14's Req 4.

- **M1 (warning).** `validateTransducer` gained an opt-in `OpaqueGuard` check
  (`warnOpaqueGuards`, default off) that flags every edge whose guard contains an opaque
  `TApp` term — the structural signature of a collection-content condition lifted through a
  closure, which the symbolic analyses translate to a free SBV variable and therefore
  cannot verify. The implementation is purely additive (one warning arm, one option field,
  two structural walkers mirroring `termReadsInput`, one producer reusing the typed
  `EdgeRef`, one `concat` line) and reuses exactly the machinery EP-56 left extensible.
  `cabal test keiki-test` passes (325 examples, 0 failures), and the load-bearing
  backward-compat case — `validateTransducer defaultValidationOptions opaqueT == []` —
  confirms the default surface is unchanged for existing consumers.
- **M2 (docs).** `docs/guide/user-guide.md` §8 now carries the honest recipe: storing a
  whole collection structurally is fine and fully verified; the silent degradation is in
  *guards*; `warnOpaqueGuards` is the audit; and the three options (application-layer
  invariant, sub-entity-as-aggregate split, or the deferred first-class registers) point
  the reader at the sound paths and at EP-60.

The key reframing (recorded in the Decision Log and Surprises): the warning targets opaque
*guards*, not opaque *mutations*. An opaque update replays forward soundly and is never
inverted, so it surrenders nothing; the "you thought it was verified but it wasn't" footgun
lives entirely in guards. This makes the signpost both precise and genuinely useful beyond
collections — it audits *any* guard the solver can't see. No gaps; the plan is fully
delivered and additive (nothing that compiled or passed before changed).


## Context and Orientation

This plan touches the keiki library at `/Users/shinzui/Keikaku/bokuno/keiki`. You need only
this file and the repository. Every code fact below was verified against the tree on
2026-06-06; line numbers may drift, so locate by name.

Terms, in plain language:

- **Transducer / edge / guard.** keiki models an event-sourced aggregate as a state
  machine. Each *edge* fires when its *guard* (a boolean predicate over the registers and
  the incoming command) holds. A guard is a value of type `HsPred rs ci`.
- **`Term` and the opaque escape hatch.** A `Term rs ci ifs r` is an expression. Its
  *structural* constructors (`TLit`, `TReg`, `TInpCtorField`, `TArith`) are readable by
  keiki's analyses; `TApp1 :: (a -> r) -> Term … a -> Term … r` and
  `TApp2 :: (a -> b -> r) -> …` carry a **raw Haskell function the analyses cannot see**.
  They are how an author expresses something keiki has no structural node for — including
  collection operations like `Map.member`/`all`/`null` lifted into a guard.
- **`validateTransducer`.** A pure, solver-free build-time check (added by EP-56) that
  returns `[TransducerValidationWarning s]`. A project asserts
  `validateTransducer defaultValidationOptions t == []` in a unit test.
- **Symbolic blindness.** `src/Keiki/Symbolic.hs`'s `translateTermSym` maps `TApp1`/`TApp2`
  to a fresh `SBV.free` variable — a sound over-approximation that carries *no
  information*. A guard branching through a `TApp` thus looks, to the single-valuedness
  (`isSingleValuedSym`) and dead-edge analyses, like an unconstrained Boolean. The checks
  cannot prove anything about it, so they say nothing — which reads as "no problem found."

Key files and exact facts (verified):

- `src/Keiki/Core.hs`:
  - `data Term … where … TApp1 …; TApp2 …` (around line 306) — the opaque constructors.
  - `data HsPred (rs :: [Slot]) (ci :: Type)` (around line 544): `PTop`, `PBot`,
    `PAnd`/`POr`/`PNot`, `PEq` (carries two `Term`s), `PInCtor`, `PCmp` (carries two
    `Term`s). The terms inside `PEq`/`PCmp` are where an opaque `TApp` lands in a guard.
  - `data TransducerValidationWarning s` (around line 1607) — the extensible warning
    union, currently `HiddenInput` / `NondeterministicPair` / `PossiblyDeadEdge`, all
    carrying the typed `EdgeRef s` (or `s` + indices) and a `tvwDetail :: String`.
    `deriving stock (Eq, Show)`.
  - `data ValidationOptions` (around line 1644) with `failOnEpsilonReadsInput`,
    `checkDeterminism`, `checkReachability`; `defaultValidationOptions` (around line 1655)
    sets all `True`. `deriving stock (Eq, Show)`.
  - `validateTransducer opts t = concat [ … ]` (around line 1677) — concatenates each
    enabled check's warnings. This is the single wiring site.
  - `data EdgeRef s = EdgeRef { edgeSource :: s, edgeIndex :: Int }` (around line 970) —
    the shared locator; `edgesOut t s` lists a vertex's edges, numbered by
    `zip [0..]` exactly as `hiddenInputWarnings` does (around line 1713).
  - `data Edge phi rs ci co s where …` (around line 654) and
    `data SymTransducer phi rs s ci co = SymTransducer { edgesOut :: s -> [Edge …] , … }`
    (around line 666). The edge's `guard` is reachable by pattern-matching the `Edge`
    (the `Edge.update` write-set is existential — GHC-55876 — but the **guard** is not;
    read it through the `Edge` record/pattern).
  - Existing structural term walkers to mirror: `termHasInpCtorField` (around line 1534)
    and `termReadsInput` (around line 1520) show the exact recursion shape over the `Term`
    constructors, including the `TApp1`/`TApp2`/`TArith` arms.
- `src/Keiki/Symbolic.hs`: `translateTermSym _env (TApp1 _f _t) = SBV.free "app1"` and
  `(TApp2 _f _a _b) = SBV.free "app2"` (around lines 461–462) — the blindness this plan
  signposts.
- `test/Keiki/ValidationSpec.hs` — EP-56's spec for `validateTransducer`; the new cases
  go here (it already builds small transducers and asserts warning lists). Registered in
  `keiki.cabal` (`other-modules`) and `test/Spec.hs` as
  `Keiki.Core.validateTransducer (EP-56)`.
- `docs/guide/user-guide.md` — §8 "Common errors" has a "Build-time" and "Hidden-input
  warnings" area where the recipe (or a cross-link to it) fits; the guards operator
  section is §3.4.

Independence: this plan is additive and self-contained. It adds one constructor, one
option field, two small walkers and one producer to `src/Keiki/Core.hs`, test cases to an
existing spec, and documentation. It does **not** change any existing signature or the
behavior of `defaultValidationOptions`, so nothing that compiles or passes today breaks.
Its soft predecessor EP-56 (the `validateTransducer` machinery) is already Complete.


## Plan of Work

Two milestones. M1 is the warning (code + test); M2 is the documentation. M1 is described
first because M2 references the warning it adds. Both are independently verifiable.


### Milestone M1 — the `OpaqueGuard` warning

Scope: add an opt-in `validateTransducer` check that flags edges whose guard contains an
opaque `TApp` term. At the end, `cabal test keiki-test` runs new cases proving it fires
when enabled, is silent by default, and names the offending edge.

Edits, all in `src/Keiki/Core.hs` unless noted:

1. **New warning arm.** Add to `data TransducerValidationWarning s` (keep the
   `deriving stock (Eq, Show)`):

   ```haskell
   | {- | An edge whose guard contains an opaque 'TApp' term. The symbolic
     single-valuedness and dead-edge analyses translate such a term to an
     unconstrained free variable, so they cannot see through the guard and
     silently under-verify it. Most often this is a collection-content
     condition (membership, "all resolved", size) lifted through a closure;
     see the user guide and EP-60 for the options. Advisory, not a soundness
     error: opt in via 'warnOpaqueGuards'.
     -}
     OpaqueGuard
       { tvwEdge :: EdgeRef s
       , tvwDetail :: String
       }
   ```

   Note `tvwEdge` and `tvwDetail` field names already exist on other arms; with
   `DuplicateRecordFields` (on in `keiki.cabal` `shared-extensions`) this is fine, exactly
   as `HiddenInput` and `PossiblyDeadEdge` already share `tvwEdge`/`tvwDetail`.

2. **New option field.** Add `warnOpaqueGuards :: Bool` to `data ValidationOptions` (with a
   haddock `-- ^ run the opaque-guard audit (opt-in; default off)`) and set
   `warnOpaqueGuards = False` in `defaultValidationOptions`. Because `ValidationOptions`
   derives `Eq, Show` and is constructed only at known sites, adding a field is safe; grep
   for `ValidationOptions {` constructions in `test/` and update any positional/record
   constructions (EP-56's tests build it by record syntax, so the new field must be added
   there — the compiler will name every site via `-Wincomplete-record-updates` /
   missing-field errors).

3. **Structural walkers.** Add, near `termReadsInput`:

   ```haskell
   -- | Does the term contain an opaque 'TApp1'/'TApp2' anywhere?
   termHasOpaqueApp :: Term rs ci ifs r -> Bool
   termHasOpaqueApp (TLit _)            = False
   termHasOpaqueApp (TReg _)            = False
   termHasOpaqueApp (TInpCtorField _ _) = False
   termHasOpaqueApp (TApp1 _ _)         = True
   termHasOpaqueApp (TApp2 _ _ _)       = True
   termHasOpaqueApp (TArith _ a b)      = termHasOpaqueApp a || termHasOpaqueApp b

   -- | Does the guard predicate branch on an opaque term?
   predHasOpaqueTerm :: HsPred rs ci -> Bool
   predHasOpaqueTerm PTop          = False
   predHasOpaqueTerm PBot          = False
   predHasOpaqueTerm (PAnd p q)    = predHasOpaqueTerm p || predHasOpaqueTerm q
   predHasOpaqueTerm (POr p q)     = predHasOpaqueTerm p || predHasOpaqueTerm q
   predHasOpaqueTerm (PNot p)      = predHasOpaqueTerm p
   predHasOpaqueTerm (PEq a b)     = termHasOpaqueApp a || termHasOpaqueApp b
   predHasOpaqueTerm (PInCtor _)   = False
   predHasOpaqueTerm (PCmp _ a b)  = termHasOpaqueApp a || termHasOpaqueApp b
   ```

   (These mirror the existing `termHasInpCtorField`/`termReadsInput` shape exactly. The
   compiler's `-Wincomplete-patterns` guards against a future `Term`/`HsPred` constructor
   being missed.)

4. **The producer.** Add, near `hiddenInputWarnings`:

   ```haskell
   opaqueGuardWarnings ::
       (Bounded s, Enum s) =>
       SymTransducer (HsPred rs ci) rs s ci co ->
       [TransducerValidationWarning s]
   opaqueGuardWarnings t =
       [ OpaqueGuard
           { tvwEdge = EdgeRef{edgeSource = s, edgeIndex = n}
           , tvwDetail =
               "guard contains an opaque TApp term the symbolic analyses cannot "
                 ++ "see through; its single-valuedness was not verified"
           }
       | s <- [minBound .. maxBound]
       , (n, e) <- zip [(0 :: Int) ..] (edgesOut t s)
       , predHasOpaqueTerm (guardOf e)
       ]
   ```

   where `guardOf` pattern-matches the `Edge` to read its `guard` (use the existing field
   selector if it is total, else a small `case e of Edge{guard = g} -> g`; the guard, unlike
   `update`, has no existential, so this is straightforward). Note `opaqueGuardWarnings` is
   specialised to the `HsPred` carrier (it must walk the predicate AST), exactly as
   `validateTransducer` already is.

5. **Wire into `validateTransducer`.** Add one element to the `concat`:

   ```haskell
   , if warnOpaqueGuards opts then opaqueGuardWarnings t else []
   ```

6. **Export.** Add `OpaqueGuard` is reached through the already-exported
   `TransducerValidationWarning (..)`; the new `ValidationOptions` field is reached through
   the already-exported `ValidationOptions (..)`. No export-list edit needed beyond
   confirming both use `(..)` (they do).

Acceptance for M1: `cabal build keiki` compiles; `cabal test keiki-test` passes with new
cases (below) green.


### Milestone M2 — the documentation recipe

Scope: a short, honest guide section on opaque collection guards and the options, plus a
cross-link. At the end the guide explains when opacity is fine, when it silently degrades
verification, the `warnOpaqueGuards` audit flag, and the deferral of first-class
collections (EP-60).

Add a subsection — recommended location: a new short block under
`docs/guide/user-guide.md` §8 (Common errors), or appended to the guards operator section
§3.4 — covering, in order:

1. **The structural-storage case is fine.** Storing a whole collection that arrives on the
   command (`B.slot @"items" =: d.items`) is a structural input read: `solveOutput` inverts
   it and `checkHiddenInputs` sees the whole list on the wire. No degradation. (This is the
   keiro-runtime-jitsurei pattern.)
2. **Opaque *guards* are where verification silently degrades.** A guard that lifts
   `Map.member`/`all`/`null`/`elem` through `TApp` (because keiki has no structural
   collection predicate) becomes a free Boolean to the symbolic checker, which then cannot
   verify the edge's single-valuedness or reachability — and says nothing. Show the
   `warnOpaqueGuards = True` audit:

   ```haskell
   validateTransducer defaultValidationOptions { warnOpaqueGuards = True } myTransducer
   -- ⇒ [ OpaqueGuard { tvwEdge = EdgeRef { edgeSource = …, edgeIndex = … }, … }, … ]
   ```

3. **The honest options today.** (a) Keep the collection's invariant in the application
   layer against the read model (what keiro-runtime-jitsurei does — its only in-aggregate guard is whole-list
   emptiness, `reg .== lit []`, which *is* structural). (b) Split a lifecycle-bearing
   sub-entity into its own scalar aggregate (the "sub-entity-as-aggregate" path), getting
   full keiki guarantees per sub-aggregate. (c) First-class collection registers (structural
   `UInsert`/`PMember`/`TLookupField`) are **deferred** — see
   `docs/plans/60-first-class-collection-registers-design-gated.md` (NO-GO at the M1 gate)
   and `docs/research/collection-registers-design.md` — and may be revived if a real
   keyed-collection consumer appears.

Then add a one-line cross-link from wherever the guide introduces guards (§3.4) or the
build-time checks (§8): "Guarding on collection contents needs an opaque `TApp` today,
which the symbolic checker can't see; enable `warnOpaqueGuards` to audit for it and see
<this section>."

Acceptance for M2: the guide contains the recipe with the three options and the EP-60
deferral pointer, and is cross-linked. (Documentation outcome; verify by reading.)


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki`.

1. Edit `src/Keiki/Core.hs`: add the `OpaqueGuard` arm, the `warnOpaqueGuards` option field
   (+ `defaultValidationOptions = … { warnOpaqueGuards = False }`), the
   `termHasOpaqueApp`/`predHasOpaqueTerm` walkers, the `opaqueGuardWarnings` producer, and
   the one `concat` element in `validateTransducer`.

2. Fix any `ValidationOptions { … }` construction sites the compiler flags (EP-56 tests
   build it by record syntax; add the new field there).

3. Extend `test/Keiki/ValidationSpec.hs` with the cases below.

4. Build and test:

   ```bash
   cabal build keiki
   cabal test keiki-test
   ```

   Expected: the `Keiki.Core.validateTransducer (EP-56)` group gains the new opaque-guard
   examples, all passing.

5. Edit `docs/guide/user-guide.md` per M2 and add the cross-link.

6. Re-run `cabal test keiki-test` to confirm no regression.


## Validation and Acceptance

The plan is complete when all of the following hold:

- `cabal build keiki` succeeds; `cabal test keiki-test` passes.
- New `ValidationSpec` cases prove:
  - An edge whose guard is `requireGuard (TApp1 (\m -> Map.member k m) (reg @"items") .== lit True)`
    (a collection-style opaque guard) yields exactly one `OpaqueGuard` warning naming that
    edge's `EdgeRef`, **when** `warnOpaqueGuards = True`.
  - A fully structural transducer (guards use only `PEq`/`PCmp`/`PInCtor` over
    `TReg`/`TInpCtorField`/`TLit`) yields **no** `OpaqueGuard` warning even with
    `warnOpaqueGuards = True`.
  - The same opaque-guard transducer yields **no** `OpaqueGuard` warning under
    `validateTransducer defaultValidationOptions` (backward compatibility — the load-bearing
    assertion that existing consumers' `== []` tests do not newly fail).
- `docs/guide/user-guide.md` contains the recipe (structural-storage-is-fine; opaque-guards
  degrade; the three options; the EP-60 deferral pointer) and is cross-linked.

Beyond compilation: the warning is *structured* — the test pattern-matches the
`OpaqueGuard` constructor and its `EdgeRef`, not a string — so a downstream project can act
on it programmatically (e.g. assert its own transducers have no unaudited opaque guards).


## Idempotence and Recovery

Every edit is additive. Re-running is safe: a duplicate constructor or field is a compile
error the build flags, so if a step seems already applied, read the file and skip it. To
roll back, remove the `OpaqueGuard` arm, the `warnOpaqueGuards` field (and its
`defaultValidationOptions` setting), the two walkers, the producer, and the one `concat`
line, then revert the test and doc edits. None of this is destructive, and because the new
option defaults `False`, even a half-applied state cannot change existing behavior under
`defaultValidationOptions`.


## Interfaces and Dependencies

Libraries/modules:

- `Keiki.Core` (`src/Keiki/Core.hs`) — owns `TransducerValidationWarning`,
  `ValidationOptions`, `validateTransducer`, `EdgeRef`, the `Term`/`HsPred` ASTs, and the
  existing structural walkers this plan mirrors. All edits land here.
- `hspec` — the test framework `keiki-test` already uses.
- `containers` — only in the *test* (a guard's opaque closure uses `Map.member`); already a
  `keiki-test` dependency (added in EP-57; see MasterPlan 14 Surprises).

Signatures that must exist at the end of M1:

```haskell
-- src/Keiki/Core.hs
data TransducerValidationWarning s
  = …
  | OpaqueGuard { tvwEdge :: EdgeRef s, tvwDetail :: String }

data ValidationOptions = ValidationOptions
  { failOnEpsilonReadsInput :: Bool
  , checkDeterminism        :: Bool
  , checkReachability       :: Bool
  , warnOpaqueGuards        :: Bool   -- new; default False
  }

termHasOpaqueApp  :: Term rs ci ifs r -> Bool
predHasOpaqueTerm :: HsPred rs ci -> Bool
opaqueGuardWarnings ::
  (Bounded s, Enum s) =>
  SymTransducer (HsPred rs ci) rs s ci co -> [TransducerValidationWarning s]
```

End of M2: `docs/guide/user-guide.md` contains the opaque-collection-guard recipe and a
cross-link.


## Git / Process

Commit to the current branch (`master`); do not create a feature branch. Conventional
Commits. Two commits are natural (warning, then docs). Every commit carries:

```text
MasterPlan: docs/masterplans/14-keiki-and-keiki-codec-json-dsl-improvements-surfaced-by-the-seihou-consumer-audit.md
ExecPlan: docs/plans/67-collection-slot-opaque-mutation-signpost-validatetransducer-warning-and-guidance.md
Intention: intention_01ktensqv9ecmv5cd5jrbcfej7
```

Suggested commit subjects:

```text
feat(validate): add opt-in OpaqueGuard warning for guards the solver can't see
docs(guide): recipe for opaque collection guards and the sub-aggregate split
```
