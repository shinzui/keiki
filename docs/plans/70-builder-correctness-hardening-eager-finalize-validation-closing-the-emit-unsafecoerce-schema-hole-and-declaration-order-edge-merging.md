---
id: 70
slug: builder-correctness-hardening-eager-finalize-validation-closing-the-emit-unsafecoerce-schema-hole-and-declaration-order-edge-merging
title: "Builder correctness hardening: eager finalize validation, closing the emit unsafeCoerce schema hole, and declaration-order edge merging"
kind: exec-plan
created_at: 2026-07-12T04:16:45Z
master_plan: "docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md"
---

# Builder correctness hardening: eager finalize validation, closing the emit unsafeCoerce schema hole, and declaration-order edge merging

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

`Keiki.Builder` (`src/Keiki/Builder.hs`) is the do-notation DSL with which every real
keiki consumer authors its state machines ("transducers"). The 2026-07 architecture
review found five defects in it, two of them serious enough to gate the `0.1.0.0`
Hackage release. This plan fixes all five. After it lands:

1. A malformed edge — a `B.do` block that forgot `goto`, or called `goto` twice —
   fails the moment the transducer value is first evaluated, with a diagnostic naming
   the source vertex and edge index, **no matter which vertex the edge hangs off**.
   Today the error is a lazy thunk buried inside one vertex's edge list: if no test
   ever drives that vertex, the broken aggregate sails through construction, review,
   and CI, and explodes in production the first time that vertex is stepped. The
   module's own documentation claims eager behavior the code does not have; after
   this plan the documentation is true.
2. The one remaining `unsafeCoerce` in the builder (`reIndexPinnedInCtor`, used by
   `emit`) is deleted. Today a fields record built from the *wrong command's* payload
   projections type-checks and is silently coerced to the wrong schema — a latent
   wrong-dictionary crash (potentially a segfault) during replay. After this plan
   that program **does not compile**; the schema equality is carried by the types.
3. `emitWith`'s sibling hole (an explicit input constructor that contradicts the
   edge's guard, so a stored event replays as a *different command* than the one
   that produced it) becomes an eager, structural build-time error.
4. Two `from` blocks naming the same vertex now merge in declaration order (the
   documented behavior; today they merge reversed) and edge indices in diagnostics
   are consistent across merged blocks (today both blocks report "edge #0").
5. A register file that declares the same slot name twice — which today silently
   resolves every access to the *first* occurrence — is rejected at compile time at
   the `buildTransducer` boundary with a `TypeError` naming the duplicated slot.

You can see it working by building the library and running the test suite: new specs
prove each failure fires by forcing **only the transducer value** (never by poking a
specific vertex), and the whole in-repo consumer surface (`jitsurei` worked examples,
which use exactly the same authoring idioms as the external keiro consumer)
recompiles without a single call-site change.


## Progress

- [ ] M1: `finalizeEdge` returns `Either BuilderDefect Edge`; defects aggregated.
- [ ] M1: `buildTransducerEither` added; `buildTransducer` re-expressed on top of it.
- [ ] M1: validation forced when the `SymTransducer` is evaluated to WHNF (eager).
- [ ] M1: duplicate `from` blocks merge in declaration order; indices global per vertex.
- [ ] M1: `(Bounded v, Enum v)` constraints dropped from `buildTransducer`.
- [ ] M1: BuilderSpec cases 7/8 updated to force only the transducer; new eager,
      declaration-order, index-numbering, and `buildTransducerEither` specs added.
- [ ] M1: `cabal build all` and `cabal test all` green.
- [ ] M2 (prototype): `pin :: Maybe [Slot]` phantom threaded through `EdgeBuilder`;
      `emit` reads the pinned `InCtor` without coercion; `reIndexPinnedInCtor` deleted.
- [ ] M2 (prototype): EmailDelivery fixture + jitsurei EmailDelivery compile unchanged;
      mismatched-schema `emit` repro captured failing to compile (transcript in
      Surprises & Discoveries).
- [ ] M3: full library + all suites green under the pin change; jitsurei unchanged.
- [ ] M3: `emitWith` guard/output constructor-mismatch defect added to `finalizeEdge`;
      `slotNamesOf` exported from `Keiki.Core`; runtime spec for the mismatch.
- [ ] M3: `test/Keiki/BuilderTypeErrorsSpec.hs` (deferred-type-errors regression module)
      added and wired into `Spec.hs` + `keiki.cabal`.
- [ ] M4: `DistinctNames` TypeError family in `src/Keiki/Internal/Slots.hs`; constraint
      on `buildTransducer`/`buildTransducerEither`; duplicate-slot spec; Slots haddock fixed.
- [ ] M5: module haddocks corrected (finalize timing, merge order, emit, noEmit refs);
      `docs/research/edge-builder-dsl-shape.md` updated; CHANGELOG entries.
- [ ] M5: handoff note recorded in
      `docs/plans/68-require-explicit-emit-noemit-intent-on-every-builder-edge.md`;
      master plan registry row updated; `nix fmt -- --no-cache` clean.


## Surprises & Discoveries

- **Research (2026-07-12): every review citation verified against the working tree.**
  The lazy vertex map: `src/Keiki/Builder.hs:806-822` (`buildTransducer` binds
  `(_, vmap) = runVertexBuilder vb []` in a `where` clause and returns the
  `SymTransducer` record immediately; nothing forces `vmap`). The lazy error thunks:
  `finalizeEdge` at `src/Keiki/Builder.hs:714-744`. The false haddock claim ("caught
  at finalize time (when `buildTransducer` evaluates the `VertexBuilder` do-block)"):
  `src/Keiki/Builder.hs:117-121`. The coercion: `reIndexPinnedInCtor = unsafeCoerce`
  at `src/Keiki/Builder.hs:493-494`, used at line 479 in `emit`. The `emitWith` hole:
  `src/Keiki/Builder.hs:502-510`. The string-only downstream defense:
  `icName ic1 == icName ic2` in `gatherInpEntries` at `src/Keiki/Core.hs:1292-1294`.
  Reverse merge: `from` prepends at `src/Keiki/Builder.hs:787-790` and the
  contradicting haddock is at lines 797-800. Per-block index restart:
  `edgeIx = length acc` at `src/Keiki/Builder.hs:679` and `:704`. Silent duplicate
  slot resolution: the OVERLAPPING/OVERLAPPABLE `HasIndexN` pair at
  `src/Keiki/Internal/Slots.hs:107-120` against the module's pairwise-distinct
  invariant stated at `src/Keiki/Internal/Slots.hs:6-7`.
- **Compatibility scope (revised 2026-07-12):** stale runtime examples are not
  evidence for this plan. Re-check the builder surface against keiki's in-tree
  aggregates and current keiro source during implementation. The `pin` phantom and
  `emitWith` tightening are justified by their type-level correctness, not by an
  assumed absence of consumers.
- **Research (2026-07-12): the TH-generated fields record already carries the schema
  parameter we need.** `genTermFieldsRecord` in `src/Keiki/Generics/TH.hs:845-911`
  emits `data <Short>TermFields rs ci ifs` whose every field is
  `Term rs ci ifs T`, and a `ToOutFields (<Short>TermFields rs ci ifs) rs ci ifs fs`
  instance. The `ifs` is pinned by the `d.field` projections the user writes, so
  tying `emit`'s `ifs` to the `onCmd` pin (M2) requires **zero** TH changes and zero
  call-site changes.

(Add entries with evidence as implementation proceeds.)


## Decision Log

- Decision: implement eager validation by making `finalizeEdge` return
  `Either BuilderDefect (Edge …)` and aggregating defects in `buildTransducer`, rather
  than by `seq`-ing the existing `error` thunks.
  Rationale: an explicit defect sum is the extensible "case list" the master plan's
  integration point 2 demands — plan 68 adds its missing-emit-intent diagnostic as one
  more constructor instead of one more lazy `error`; it also enables reporting *all*
  defects at once and powers `buildTransducerEither`.
  Date: 2026-07-12

- Decision: add `buildTransducerEither` alongside the erroring `buildTransducer`.
  Rationale: tests and future tooling (doctors, LSP-style checks) want structured
  errors without exception plumbing; keiro keeps calling `buildTransducer` unchanged.
  The erroring form is a thin `either (error . render) id` wrapper, so there is one
  validation code path.
  Date: 2026-07-12

- Decision: single-defect error messages stay byte-identical to today's strings
  ("Keiki.Builder: edge #0 from A: goto missing. …"). Multiple defects render as those
  same strings joined by newlines.
  Rationale: the exact strings are asserted by existing tests (BuilderSpec cases 7/8,
  BuilderSpike) and by plan 68's spec; byte-compatibility means those assertions only
  need their *forcing site* updated, not their expected text.
  Date: 2026-07-12

- Decision: close the `emit` hole by type-level threading — a new phantom
  `pin :: Maybe [Slot]` on `EdgeBuilder` carrying the enclosing `onCmd`'s input
  schema — not by a runtime structural comparison.
  Rationale: the TH record already carries `ifs` (see Surprises), the review's
  worst-case (two same-named `InCtor`s with different schemas defeating the
  `icName` string check and running a dictionary at the wrong type) is only truly
  closed by types, and the consumer surface survey shows no one names the
  `EdgeBuilder` type, so adding a phantom is invisible at call sites. The runtime
  fallback described in the review remains the contingency if the M2 prototype fails
  (promotion criteria in M2).
  Date: 2026-07-12

- Decision: `emit` inside `onEpsilon` becomes a *compile-time* error (the pin is
  `'Nothing`, `emit` demands `'Just ifs`), replacing today's runtime "no enclosing
  onCmd" error at `src/Keiki/Builder.hs:482-486`.
  Rationale: strictly earlier diagnosis of the same misuse; the message moves into the
  haddock, and `emitWith` remains the documented ε-body form. No in-repo or keiro code
  hits this path.
  Date: 2026-07-12

- Decision: `emitWith` keeps its signature (it is pin-polymorphic and load-bearing in
  the keiro survey) but its "override the enclosing onCmd's InCtor" affordance is
  revoked: inside an `onCmd` edge, an output whose `InCtor` differs from the pinned one
  (by name or by slot-name list, compared via `slotNamesOf`) is an eager
  `BuilderDefect`. Inside `onEpsilon` it stays unconstrained.
  Rationale: the review showed the override lets an event invert to a different
  command than the one that fired — a replay-corruption primitive, the exact failure
  class this master plan exists to remove. No consumer uses the override (survey
  2026-07-12; in-repo `emitWith` appears only in BuilderSpec case 14, with the
  matching `InCtor`).
  Residual risk, accepted and documented: two `InCtor`s with the same name *and* the
  same slot-name list but different slot *types* still pass the structural check;
  fully closing that requires per-slot `Typeable` evidence on `InCtor` (a
  `Keiki.Core` API change) and is recorded as follow-up for the master plan, not done
  here.
  Date: 2026-07-12

- Decision: drop the `(Bounded v, Enum v)` constraints from `buildTransducer`
  (`src/Keiki/Builder.hs:806-813`).
  Rationale: the eager pass validates the *declared* vertex entries and needs neither
  bound; keeping documented-unused constraints is exactly the kind of API lie this
  master plan removes; removing constraints can never break a caller; and the
  hypothetical `withCompletenessCheck` combinator the haddock reserves them for can
  demand them on itself when it exists. Vertex types keep deriving `Enum`/`Bounded`
  anyway for `checkHiddenInputs`/`validateTransducer`.
  Alternative considered: use them for a reachability/completeness *error* in the
  eager pass — rejected because unmentioned vertices are documented as legitimately
  terminal, so completeness cannot soundly be an error, and a pure function has no
  warning channel.
  Date: 2026-07-12

- Decision: enforce slot-name distinctness at the `buildTransducer` boundary with a
  type-level `DistinctNames (Names rs)` constraint (a `TypeError` family in
  `Keiki.Internal.Slots`), not a runtime check.
  Rationale: zero runtime cost, fires at the author's desk, and matches the existing
  `Disjoint` machinery in the same module. Runtime testability is preserved via a
  small `-fdefer-type-errors` spec module (M3/M4). The check guards the builder
  boundary only; hand-authored AST transducers bypass it — noted in the Slots haddock
  and left to the master plan as possible follow-up on `RegFile` construction.
  This family is the canonical duplicate-slot-name constraint for the repository;
  EP-78 reuses `DistinctNames (Names rs)` on `RegFileToJSON` rather than defining a
  codec-local family. Keep its module/export and `TypeError` wording suitable for both
  Builder and codec callers.
  Date: 2026-07-12

- Decision: fix duplicate-`from` merge order by reversing the raw vertex list once in
  `buildTransducer` and left-fold-merging entries per vertex; assign edge indices
  *after* merging, per vertex, `0..n-1` in declaration order.
  Rationale: makes the haddock at `src/Keiki/Builder.hs:797-800` true instead of
  rewriting it to describe a bug; post-merge numbering is the only way two blocks for
  one vertex get distinct, stable indices in diagnostics.
  Date: 2026-07-12

- Decision (handoff, integration point 2 of the master plan): plan 68
  (`docs/plans/68-require-explicit-emit-noemit-intent-on-every-builder-edge.md`)
  implements its missing-emit-intent diagnostic as a new `BuilderDefect` constructor
  checked in this plan's `finalizeEdge`, **not** as the lazy `error` its current text
  assumes. Its "goto-arity precedes output-intent" precedence discovery is preserved
  by construction (defects are detected in `finalizeEdge` in the same case order).
  M5 of this plan records a dated note to that effect in plan 68 itself.
  Date: 2026-07-12


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

**The project.** keiki is a pure Haskell library (package `keiki`, source under
`src/`) for event sourcing: it models an aggregate as a *transducer* — a pure state
machine that reads commands, updates a typed *register file* (a heterogeneous record
of named slots), emits events, and moves between control *vertices*. A transition is
an `Edge` (`src/Keiki/Core.hs:627-635`): a guard predicate, a register update, a list
of output terms, and a target vertex. A `SymTransducer` (`src/Keiki/Core.hs:638-647`)
is a record of `edgesOut :: v -> [Edge …]` plus initial vertex, initial registers,
and a finality predicate. *Replay* means reconstructing state from stored events: each
output term is an `OPack` (`src/Keiki/Core.hs:504-517`) tying an input-side
constructor descriptor (`InCtor`, `src/Keiki/Core.hs:353-360` — a named
match/build round-trip for one command constructor, indexed by that constructor's
field schema `ifs :: [Slot]`, where `type Slot = (Symbol, Type)` at
`src/Keiki/Core.hs:188`) to an output-side `WireCtor` and an `OutFields` HList, so
`solveOutput` can mechanically invert an observed event back to the command that
produced it.

**The builder.** `src/Keiki/Builder.hs` (822 lines) is a three-layer monadic DSL over
those types: `VertexBuilder` (plain monad; `from` adds one `(vertex, edges)` entry),
`EdgeListBuilder` (plain monad; `onCmd`/`onEpsilon` each add one edge for the current
source vertex), and `EdgeBuilder` (an indexed state monad used via `QualifiedDo` as
`B.do`; its phantom `(w :: [Symbol])` tracks which slots the body has written so a
duplicated write is a compile error). An edge body accumulates a `PartialEdge`
(`src/Keiki/Builder.hs:249-266`); `finalizeEdge` (`:714-744`) closes it into an
`Edge`, raising `error` for a missing or duplicated `goto`. `buildTransducer`
(`:806-822`) runs the vertex builder and wraps the resulting association list in a
`SymTransducer`. The worked example at the top of the module haddock, and the real
consumers, all look like the EmailDelivery aggregate
(`jitsurei/src/Jitsurei/EmailDelivery.hs:164-181`, mirrored by the test fixture
`test/Keiki/Fixtures/EmailDelivery.hs`): `B.from V do B.onCmd inCtorX $ \d -> B.do
{ B.slot @"s" .= d.field; B.emit wireY YTermFields{…}; B.goto V' }`.

**Compatibility scope.** In-repo: the `jitsurei` example package (`jitsurei/src/Jitsurei/*.hs`)
and the test suite (`test/Keiki/BuilderSpec.hs`, `test/Keiki/BuilderSpike.hs`,
`test/Keiki/Fixtures/*.hs`). External compatibility is current keiro only. The
authoring surface must remain source-compatible where correctness permits:
`buildTransducer`, `from`, `onCmd`, `onEpsilon`, `requireGuard`/`requireEq`/
`requireGt` (and the other `requireCmp` wrappers), `slot`/`(.=)`/`(=:)`, `reg`,
`emit`/`emitWith`/`noEmit`, `goto`, `toOutFields`, `oNil`. New eager errors on
*genuinely malformed* edges are acceptable (they were latent bugs); new compile
errors on the mismatched-schema `emit` are the point.

**The five defects, precisely.**

*Defect 1 — lazy validation contradicting the docs.* `buildTransducer`
(`src/Keiki/Builder.hs:806-822`) binds `(_, vmap) = runVertexBuilder vb []` lazily
and immediately returns `SymTransducer { edgesOut = \v -> concatMap snd (filter
((== v) . fst) vmap), … }`. The missing-goto / double-goto `error`s live inside each
`Edge` value produced by `finalizeEdge` (`:714-744`), so they are forced only when
`edgesOut` is demanded *for that vertex* and the list element is evaluated. The
module haddock (`:117-121`) claims they are "caught at finalize time (when
`buildTransducer` evaluates the `VertexBuilder` do-block)" — false: nothing evaluates
it. Consequence: a malformed edge on a vertex no test drives passes construction and
every test, then crashes in production.

*Defect 2 — the `emit` coercion.* `onCmd` stores its `InCtor` in the `PartialEdge`
behind the existential wrapper `PeInCtor` (`:276-277`), erasing the schema `ifs`.
`emit` (`:459-486`) takes any record with a `ToOutFields rec rs ci ifs fs` instance;
its `ifs` is *unconstrained*, so to build the `OPack` it "re-establishes" the erased
equality with `reIndexPinnedInCtor = unsafeCoerce` (`:493-494`, applied at `:479`).
The justifying comment assumes the record's projections came from the same `onCmd`'s
`PayloadProj` — but nothing enforces it: a fields record built from a *different*
constructor's TH-derived projections (`inpOtherCtor #field`, whose `Term`s pin a
different `ifs`) type-checks and gets coerced. Downstream the only defense is the
string comparison `icName ic1 == icName ic2` in `gatherInpEntries`
(`src/Keiki/Core.hs:1292-1294`); two same-named `InCtor`s with different schemas
defeat it, and `assemble` (`src/Keiki/Core.hs:390-413`) then runs a typeclass
dictionary at the wrong type — undefined behavior, potentially a segfault.

*Defect 2b — the `emitWith` sibling hole.* `emitWith` (`:502-510`) packs an
explicitly supplied `InCtor` with no coercion — but also with no check against the
edge's guard (set by `onCmd` to `matchInCtor ic`). An edge guarded on command X whose
output packs `InCtor` Y stores an event that *replays as command Y*: state divergence
between the live path and replay.

*Defect 3 — reverse merge and restarting indices.* `from` prepends its entry
(`entry : vs`, `:787-790`), and `buildTransducer` concatenates matching entries in
list order, so two `from` blocks for one vertex merge in **reverse** declaration
order — contradicting the haddock at `:797-800` ("in declaration order"). Separately,
`edgeIx = length acc` (`:679`, `:704`) counts within one block's accumulator, so each
block's first edge is "edge #0" in diagnostics even when it is the vertex's third
edge overall.

*Defect 4 — unused constraints.* `buildTransducer` demands `(Bounded v, Enum v)`
(`:806-813`), documented (`:801-805`) as reserved for a future completeness check.
Resolution: dropped (see Decision Log).

*Defect 5 — silent duplicate slot names.* `HasIndexN` resolution in
`src/Keiki/Internal/Slots.hs:107-120` uses an OVERLAPPING head-match instance and an
OVERLAPPABLE recursive instance, so for a slot list `'[ '("dup", Int), '("dup",
Bool)]` every lookup of `"dup"` silently resolves to the first occurrence — violating
the module's own stated invariant that slot names are pairwise distinct
(`src/Keiki/Internal/Slots.hs:6-7`) and making the second slot unreachable.

**What "eager" means here.** keiki is pure and lazy; no validation can run before
*anything* is demanded. The contract this plan establishes: forcing the
`SymTransducer` returned by `buildTransducer` to weak head normal form (WHNF — the
outermost constructor; what `Control.Exception.evaluate`, a `case`, or any field
access does) runs the **complete** validation over **every** vertex and edge, and
raises the full diagnostic list if any edge is malformed. Since every real use
(`delta`, `step`, `validateTransducer`, `edgesOut`) forces the record, a malformed
transducer can no longer hide behind an undriven vertex. `buildTransducerEither` runs
the same validation when its `Either` result is inspected.

**Toolchain.** GHC 9.12 (`tested-with: GHC >=9.12 && <9.13` in `keiki.cabal`), built
inside `nix develop`. Tests are hspec, enumerated manually in `test/Spec.hs` (no
hspec-discover) and listed under `other-modules` in `keiki.cabal`'s test-suite
stanza — a new spec module must be added in **both** places. Formatting is fourmolu
via `nix fmt -- --no-cache`. All commands below run from the repository root
`/Users/shinzui/Keikaku/bokuno/keiki`.


## Plan of Work

The work is five milestones. M1 restructures validation (defects 1, 3, 4) without
touching any type the user writes. M2 is a prototyping milestone for the type-level
`emit` fix on the smallest fixture. M3 promotes the prototype across the codebase and
closes the `emitWith` hole (defect 2, 2b). M4 adds the slot-distinctness constraint
(defect 5). M5 trues up documentation and records the plan-68 handoff.

### Milestone 1 — Eager, structured, declaration-ordered validation

Scope: `src/Keiki/Builder.hs` internals plus `test/Keiki/BuilderSpec.hs`. At the end,
a malformed edge anywhere in the graph fails when the transducer value is forced;
duplicate `from` blocks merge in declaration order with globally consistent per-vertex
edge indices; `buildTransducerEither` exists; the `Bounded`/`Enum` constraints are
gone. No consumer call site changes.

First, introduce the defect vocabulary near `finalizeEdge`. A *defect* is a
structural problem detected while closing one edge; a *builder error* is a defect
plus its location. Both types are exported (they are the API of
`buildTransducerEither`, and plan 68 extends `BuilderDefect`):

```haskell
-- | One structural problem found while closing a single edge body.
-- Extensible case list: plan 68 adds its missing-emit-intent case here.
data BuilderDefect
  = -- | The body never called 'goto'.
    DefectMissingGoto
  | -- | The body called 'goto' more than once; carries the count.
    DefectMultipleGoto Int
  | -- | An output's 'InCtor' contradicts the one pinned by the enclosing
    -- 'onCmd' (added in M3): expected name and slot names, then actual.
    DefectOutputCtorMismatch String [String] String [String]
  deriving stock (Eq, Show)

-- | A defect located at a specific edge of a specific source vertex.
-- The edge index is assigned after duplicate-'from' merging, so it is
-- the position the edge occupies in @edgesOut@'s result list.
data BuilderError v = BuilderError
  { beVertex :: v,
    beEdgeIndex :: Int,
    beDefect :: BuilderDefect
  }
  deriving stock (Eq, Show)
```

Change `finalizeEdge` to
`finalizeEdge :: PartialEdge rs ci co v w -> Either BuilderDefect (Edge (HsPred rs ci) rs ci co v)`
— it no longer takes the index or source vertex (location is attached later) and no
longer calls `error`. The three existing cases map to `Right edge`,
`Left DefectMissingGoto`, and `Left (DefectMultipleGoto n)`. Keep the case order:
goto-arity is decided first, which is the precedence plan 68 relies on when it nests
its check inside the exactly-one-goto branch.

Thread `Either` through the accumulators: `EdgeListBuilder`'s state becomes
`[Either BuilderDefect (Edge …)]` and `VertexBuilder`'s becomes
`[(v, [Either BuilderDefect (Edge …)])]`. Both types are exported abstract (no
constructors in the export list at `src/Keiki/Builder.hs:143-147`), so this is
invisible outside the module. `onCmd` (`:663-681`) and `onEpsilon` (`:689-706`) drop
their `edgeIx = length acc` computation and their `Show v` constraint (they no longer
format messages); they simply cons `finalizeEdge finalPE` onto the accumulator.
`from` (`:782-790`) keeps reversing the per-block list.

Rewrite the entry points:

```haskell
-- | Validating entry point. Runs the whole 'VertexBuilder', merges
-- duplicate-vertex entries in declaration order, numbers each vertex's
-- edges 0..n-1 in that order, and checks every edge. Returns every
-- defect found, or a transducer whose edges are already fully closed.
buildTransducerEither ::
  forall rs ci co v.
  (Eq v) =>
  v ->
  RegFile rs ->
  (v -> Bool) ->
  VertexBuilder rs ci co v () ->
  Either (NonEmpty (BuilderError v)) (SymTransducer (HsPred rs ci) rs v ci co)

-- | Erroring entry point (the historical surface). Equivalent to
-- 'buildTransducerEither' but renders all defects into one 'error'
-- whose text, for a single defect, is byte-identical to the pre-EP-70
-- messages. The error is raised when the returned transducer is
-- evaluated to WHNF.
buildTransducer ::
  forall rs ci co v.
  (Eq v, Show v) =>
  v ->
  RegFile rs ->
  (v -> Bool) ->
  VertexBuilder rs ci co v () ->
  SymTransducer (HsPred rs ci) rs v ci co
buildTransducer initS initR isF vb =
  case buildTransducerEither initS initR isF vb of
    Left errs -> error (renderBuilderErrors errs)
    Right t -> t
```

Inside `buildTransducerEither`: reverse the raw list from `runVertexBuilder` (undoing
`from`'s prepending) to get declaration order; left-fold-merge entries with the same
vertex (`Eq v` only — no `Ord`), appending later blocks' edges after earlier ones and
keeping first-mention vertex order; zip each merged edge list with `[0..]`; partition
into `[BuilderError v]` (from the `Left`s, with vertex and index attached) and the
merged clean table. If any error, return `Left`; otherwise force the table — each
`Edge` is already WHNF by construction of the `Right`s, but additionally force each
edge's `output` list *spine* with `seq`/`foldr`, because until M3 lands, `emit`'s
"no enclosing onCmd" runtime error (`src/Keiki/Builder.hs:482-486`) still hides in
that spine — and return `Right (SymTransducer { edgesOut = \v -> fromMaybe []
(lookup v merged), … })`. Because `buildTransducer` scrutinizes the `Either` before
producing the record constructor, forcing its result to WHNF runs everything: that is
the eagerness contract. `renderBuilderErrors` reproduces today's exact strings —
for `DefectMissingGoto` at vertex `A`, index 0:

```text
Keiki.Builder: edge #0 from A: goto missing. Each onCmd/onEpsilon body must end with exactly one goto V.
```

and the corresponding "goto called more than once" text for `DefectMultipleGoto`
(copy both literals verbatim from `src/Keiki/Builder.hs:728-744`); multiple errors
join with `"\n"`. Drop `Bounded v`/`Enum v` from `buildTransducer` per the Decision
Log, and update its haddock (`:792-805`): the merge-order sentence becomes true, the
reserved-constraints paragraph is deleted, and a new paragraph states the eagerness
contract in the "What eager means here" terms from Context and Orientation. Export
`buildTransducerEither`, `BuilderDefect (..)`, `BuilderError (..)`, and
`renderBuilderErrors` from the module export list.

Tests, all in `test/Keiki/BuilderSpec.hs` (reuse its toy `Regs`/`ToyVertex`/`ToyCmd`
setup; note `evaluate` is already imported):

- Update cases 7 and 8 (`:216-241`): change the forcing expression from
  `evaluate (head (edgesOut tr A))` to `evaluate tr`; expected strings unchanged.
  This is the headline proof that the diagnostic no longer needs the vertex demanded.
- New: *missing goto on an undriven vertex fires at construction.* Build a transducer
  with a well-formed `from A` edge and a `from B` block whose body omits `goto`;
  assert `evaluate tr` throws `errorCall` with the exact text
  `"Keiki.Builder: edge #0 from B: goto missing. …"`. (Before this milestone that
  transducer evaluates fine and even answers `edgesOut tr A` — the review's latent
  production bug.)
- New: *declaration order across duplicate `from` blocks.* Two `from A` blocks, the
  first adding an edge to `B` (on `inCtorTick`), the second an edge to `A` (on
  `inCtorIdle`, both with `B.noEmit`); assert `edgesOut tr A` has exactly two edges
  with `target e1 == B` and `target e2 == A`. (Mirrors existing case 11, which covers
  two `onCmd`s in *one* block, at `:276-289`.)
- New: *global indices across merged blocks.* Two `from A` blocks where only the
  *second* block's edge omits `goto`; assert the error text says `edge #1`, not
  `edge #0`.
- New: *`buildTransducerEither` surfaces all defects structurally.* A graph with a
  missing-goto edge on `A` and a double-goto edge on `B`; assert the result is
  `Left` and the error list (converted with `Data.List.NonEmpty.toList`) equals
  `[BuilderError A 0 DefectMissingGoto, BuilderError B 0 (DefectMultipleGoto 2)]`;
  and a well-formed graph returns `Right` whose `edgesOut` behaves normally.

Acceptance: `cabal build all` and `cabal test all` green (jitsurei suites included —
they prove the consumer surface is untouched); the new specs pass; grep confirms no
remaining `error` call in `finalizeEdge`.

### Milestone 2 — Prototyping: pin the input schema through `EdgeBuilder`'s types

Scope: prototyping, on `src/Keiki/Builder.hs` plus the two smallest consumers —
`test/Keiki/Fixtures/EmailDelivery.hs` and `jitsurei/src/Jitsurei/EmailDelivery.hs`.
Goal: prove the coercion-free `emit` compiles the real-world pattern unchanged and
rejects the mismatched-schema program, before committing the whole suite to the new
types. This milestone may be committed in a partially-green state (library compiles,
EmailDelivery compiles, other spec modules possibly not yet) — promotion to M3
finishes the sweep.

The design. Give `EdgeBuilder` a new phantom `pin :: Maybe [Slot]` (promoted `Maybe`;
`Slot` re-exported from `Keiki.Core`), recording whether the body sits inside an
`onCmd` and, if so, that command constructor's field schema:

```haskell
newtype EdgeBuilder rs ci co v (pin :: Maybe [Slot]) (w :: [Symbol]) (w' :: [Symbol]) a
  = EdgeBuilder
  { runEdgeBuilder ::
      PartialEdge rs ci co v pin w ->
      (a, PartialEdge rs ci co v pin w')
  }
```

Replace the existential `PeInCtor` (`src/Keiki/Builder.hs:276-277`) with a GADT whose
index *is* the pin, so the schema is never erased:

```haskell
-- | Whether the enclosing entry point pinned an 'InCtor', tracked at the
-- type level. 'PinCtor' carries the constructor at its real schema, so
-- 'emit' recovers it with no coercion (the old 'PeInCtor' existential
-- erased @ifs@ and forced 'reIndexPinnedInCtor = unsafeCoerce').
data Pinned ci (pin :: Maybe [Slot]) where
  PinNone :: Pinned ci 'Nothing
  PinCtor :: InCtor ci ifs -> Pinned ci ('Just ifs)
```

`PartialEdge` gains the `pin` index and its `peInCtor :: Maybe (PeInCtor ci)` field
becomes `pePinned :: Pinned ci pin`. Every pin-indifferent combinator (`(.=)`,
`(=:)`, `goto`, `noEmit`, `requireGuard`/`requireEq`/`requireCmp` and wrappers,
`emitWith`, `pure`, `return`, `(>>=)`, `(>>)`) generalizes with a free `pin` variable
threaded unchanged (the indexed bind keeps `pin` constant across both operands).
`onCmd` pins `'Just ifs` and `onEpsilon` pins `'Nothing`:

```haskell
onCmd ::
  forall ci ifs rs co v w.
  InCtor ci ifs ->
  (PayloadProj rs ci ifs -> EdgeBuilder rs ci co v ('Just ifs) '[] w ()) ->
  EdgeListBuilder rs ci co v ()

onEpsilon ::
  forall rs ci co v w.
  EdgeBuilder rs ci co v 'Nothing '[] w () ->
  EdgeListBuilder rs ci co v ()
```

`emit` then *demands* the pin and identifies its schema with the record's:

```haskell
emit ::
  forall co fs rs ci ifs v w rec.
  (ToOutFields rec rs ci ifs fs) =>
  WireCtor co fs ->
  rec ->
  EdgeBuilder rs ci co v ('Just ifs) w w ()
emit wc rec = EdgeBuilder $ \pe -> case pePinned pe of
  PinCtor ic ->
    ((), pe {peOutput = peOutput pe ++ [pack ic wc (toOutFields rec)]})
```

The GADT match is exhaustive: at `pin ~ 'Just ifs` the `PinNone` case is
unreachable, and matching `PinCtor ic` refines `ic :: InCtor ci ifs` — the *same*
`ifs` the `ToOutFields` fundep pins from the record. Delete `reIndexPinnedInCtor`
(`:493-494`), the `Unsafe.Coerce` import (`:227`), and `emit`'s `Nothing` runtime
error (`:482-486`) — `emit` inside `onEpsilon` is now `Couldn't match 'Nothing with
'Just ifs` at compile time. Why call sites don't change: the TH record
`<Short>TermFields rs ci ifs` already carries `ifs` (see Surprises & Discoveries),
and the `d.field` projections through `PayloadProj rs ci ifs` pin it to the `onCmd`
schema, which is exactly what the new `emit` requires; the operator form
`B.emit wc (d.x *: oNil)` pins the same way; a literal-only `OutFields` (previously
an ambiguous-`ifs` inference hazard) now gets `ifs` *from* the pin — strictly better
inference.

Steps and observations:

1. Make the changes above; get `cabal build keiki` compiling (library only; if other
   in-repo spec modules fail at this point, that is M3's sweep, not a prototype
   failure — but expect none, since the survey found no incompatible idiom).
2. Confirm both EmailDelivery modules compile **without any edit**:
   `cabal build jitsurei` and the fixture via `cabal build keiki-test` (or `cabal
   test keiki-test`).
3. Capture the repro. In a scratch module (e.g.
   `/private/tmp/…/scratchpad/EmitMismatchRepro.hs` compiled with `cabal repl
   keiki-test`, or a temporary in-tree file deleted before commit), inside
   `B.onCmd inCtorTick`, emit an `OutFields` built from a *different* constructor's
   projection — with BuilderSpec's toy types: `B.emit wireTicked (OFCons
   (inpTwo #x) OFNil)` where `inpTwo` projects `TwoCmd`'s schema, or any TH-derived
   `inp<OtherCtor>` whose schema differs from `Tick`'s. Verify it **compiles on
   `master`** (the coercion accepts it) and **fails to compile** on the prototype
   with a schema-mismatch type error. Paste both transcripts (the silent acceptance
   and the new error) into Surprises & Discoveries.

Promotion criteria: all three observations hold → proceed to M3 on these types.
Contingency: if GHC 9.12 rejects the pin threading somewhere structural (e.g. the
`QualifiedDo` bind fails to infer a constant `pin` through real bodies), discard the
phantom, keep `PeInCtor`, and instead implement the review's degraded mode — replace
the coerce with a runtime structural comparison (constructor name via `icName` plus
slot names via `slotNamesOf`, raised as a `BuilderDefect` through M1's pass) — and
record the failure evidence and the downgrade in the Decision Log. The rest of the
plan is unchanged either way.

### Milestone 3 — Promote the pin, close the `emitWith` hole, add regressions

Scope: finish defect 2/2b across the repo. At the end, `cabal test all` is green on
the new types, the guard/output constructor mismatch is an eager build error, and
both type-level fixes have executable regressions.

Work:

1. Sweep the repo: `cabal build all && cabal test all`. Expect zero source changes in
   `jitsurei/`, `test/Keiki/Fixtures/`, and the spec modules (BuilderSpec cases 1-14
   and BuilderSpike all use pinned-schema records or projections). If any call site
   does fail, record it in Surprises & Discoveries and list the exact edit here —
   the keiro-facing rule is that `B.emit wireCtorX XTermFields{..}` inside `onCmd`
   must compile unchanged, and any deviation from that must be escalated in the
   master plan's consumer ledger (integration point 6).
2. Export `slotNamesOf :: InCtor ci ifs -> [String]` from `Keiki.Core` (it exists at
   `src/Keiki/Core.hs:1524-1525` but is not in the export list — additive change).
3. In `finalizeEdge`, add the `emitWith` consistency check. `finalizeEdge` now takes
   the pin-indexed `PartialEdge`; when `pePinned` is `PinCtor pinnedIc`, walk
   `peOutput` (each element an `OPack ic wc ofs` — `OutTerm (..)` is exported from
   `Keiki.Core`) and for the first output whose `icName ic /= icName pinnedIc` or
   whose `slotNamesOf ic /= slotNamesOf pinnedIc`, produce
   `Left (DefectOutputCtorMismatch (icName pinnedIc) (slotNamesOf pinnedIc)
   (icName ic) (slotNamesOf ic))`. Keep it *after* the goto-arity cases (same
   precedence rationale as plan 68). When the pin is `PinNone` (`onEpsilon`), no
   check. Render it in `renderBuilderErrors` in the house style, e.g.:

   ```text
   Keiki.Builder: edge #0 from A: emitWith InCtor "Two" (slots [x,y]) contradicts the enclosing onCmd's InCtor "Tick" (slots [count]). An onCmd edge's outputs must pack the command constructor the edge matches on, or replay will invert the event to a different command.
   ```

   (Fix the exact literal when writing the code and mirror it byte-for-byte in the
   spec.)
4. Update haddocks in `src/Keiki/Builder.hs`: `emit` (drop the coercion justification
   block at `:465-486` and the `emitWith`-for-onEpsilon runtime-error sentence — now
   "a compile error directs you to `emitWith`"), `emitWith` (`:499-510` — the
   override affordance is gone; inside `onCmd` the supplied `InCtor` must agree with
   the pinned one, checked eagerly), `PartialEdge`/`Pinned`, and the module-header
   worked example if any wording references the runtime error.
5. Tests:
   - New BuilderSpec case: *`emitWith` contradicting the pin fires eagerly.* Inside
     `B.onCmd inCtorTick`, call `B.emitWith inCtorTwo wireTwoEv TwoEvTermFields{…}`
     (schemas differ), then `B.goto B`; assert `evaluate tr` throws with the exact
     mismatch text. Also assert the existing agreeing case 14 (`:333-354`) still
     passes.
   - New module `test/Keiki/BuilderTypeErrorsSpec.hs` with
     `{-# OPTIONS_GHC -fdefer-type-errors -Wno-deferred-type-errors #-}`: a tiny,
     self-contained module (own toy types; keep it minimal — deferral hides *all*
     type errors in the module) containing (a) the M2 mismatched-schema `emit` repro
     and, after M4, (b) the duplicate-slot-name `buildTransducer`. Each `it` forces
     the offending value with `evaluate` and asserts `shouldThrow` with a predicate
     accepting `Control.Exception.TypeError` (deferred type errors raise that
     exception at the offending expression). Wire the module into `test/Spec.hs`
     (import + `describe`) and `keiki.cabal`'s test-suite `other-modules` — both are
     manual lists (see Context). If the deferred-error technique proves flaky under
     GHC 9.12, fall back to the file's case-3 precedent
     (`test/Keiki/BuilderSpec.hs:153-161`): document the worked compile error in a
     comment and let the suite's own compilation stand as the positive proof; record
     the fallback in the Decision Log.

Acceptance: `cabal test all` green; `grep -rn unsafeCoerce src/Keiki/Builder.hs`
returns nothing; the mismatch spec and the deferred-type-error spec pass; jitsurei
diff is empty.

### Milestone 4 — Reject duplicate slot names at the builder boundary

Scope: `src/Keiki/Internal/Slots.hs`, the two builder entry points, and the
regression module. At the end, `buildTransducer` over a register file with a repeated
slot name does not compile, with an error naming the slot.

In `src/Keiki/Internal/Slots.hs`, next to `Disjoint` (`:61-80`), add and export a
distinctness family over one list, with its own message (do not reuse `NotMember`,
whose `TypeError` text speaks about `combine`):

```haskell
-- | Pairwise distinctness of a slot-name list. The register-file
-- invariant (see the module header) as a Constraint: fires a TypeError
-- naming the first duplicated name. Checked at the 'buildTransducer'
-- boundary; 'HasIndexN' itself still resolves a duplicated name to its
-- first occurrence, so entry points that bypass the builder bypass this
-- check too.
type family DistinctNames (xs :: [Symbol]) :: Constraint where
  DistinctNames '[] = ()
  DistinctNames (x ': xs) = (NotElemSlot x xs, DistinctNames xs)

type family NotElemSlot (x :: Symbol) (ys :: [Symbol]) :: Constraint where
  NotElemSlot _ '[] = ()
  NotElemSlot x (y ': ys) = (NotElemSlotCmp (CmpSymbol x y) x, NotElemSlot x ys)

type family NotElemSlotCmp (o :: Ordering) (x :: Symbol) :: Constraint where
  NotElemSlotCmp 'LT _ = ()
  NotElemSlotCmp 'GT _ = ()
  NotElemSlotCmp 'EQ x =
    TypeError
      ( 'Text "Keiki: register file declares slot \""
          ':<>: 'Text x
          ':<>: 'Text "\" more than once. "
          ':$$: 'Text "Slot names in a register file must be pairwise distinct; "
          ':$$: 'Text "a duplicated name silently shadows the later slot."
      )
```

Add `DistinctNames (Names rs)` to the contexts of both `buildTransducer` and
`buildTransducerEither` in `src/Keiki/Builder.hs` (import `DistinctNames` and `Names`
from `Keiki.Internal.Slots`; `Names` projects the name list out of `rs`, defined at
`src/Keiki/Internal/Slots.hs:86-88`). The module already opens with
`{-# OPTIONS_GHC -Wno-redundant-constraints #-}` (`:1-2`) precisely because
check-only constraints look redundant to GHC — no new warning suppression needed.
Correct the Slots module header (`:6-20`) and the `HasIndexN` instances' haddock
(`:98-120`): state explicitly that resolution takes the first occurrence and that
the invariant is *enforced* for builder users via `DistinctNames` at
`buildTransducer`. Optionally re-export `DistinctNames` from `Keiki.Core` beside the
existing `Disjoint`/`Names` re-exports (`src/Keiki/Core.hs` export list, "Slot-name
machinery" group) for symmetry.

Test: add part (b) to `test/Keiki/BuilderTypeErrorsSpec.hs` — a
`type DupRegs = '[ '("dup", Int), '("dup", Bool)]` transducer built with
`buildTransducer`; under `-fdefer-type-errors`, `evaluate tr` throws the deferred
`TypeError`; assert the same way as part (a). Every existing consumer compiles
unchanged (all real register files have distinct names — that is the positive proof,
same as the `Disjoint` machinery's).

Acceptance: `cabal build all` green (the constraint solves invisibly everywhere);
the new spec part passes; temporarily adding a duplicate slot to the toy `Regs` in a
scratch build shows the new message (do not commit that).

### Milestone 5 — Documentation truth, changelog, and the plan-68 handoff

Scope: prose only, plus final formatting. Work:

1. `src/Keiki/Builder.hs` module haddock, "Misuse diagnostics" section (`:111-121`):
   rewrite the missing-goto/multiple-goto bullets to state the *eager* contract
   (raised when the transducer returned by `buildTransducer` is first evaluated, for
   any vertex's edges, all defects reported together; structured via
   `buildTransducerEither`), and add bullets for the `emitWith` mismatch defect and
   the compile-time diagnostics (mismatched-schema `emit`, `emit`-in-`onEpsilon`,
   duplicate slot names). Verify no other stale wording survives:
   `grep -n "finalize" src/Keiki/Builder.hs`.
2. `docs/research/edge-builder-dsl-shape.md`: locate the finalize-timing and
   goto-termination discussion (`grep -n "finalize\|goto" docs/research/edge-builder-dsl-shape.md`)
   and update it to the eager mechanism; add a dated design note summarizing this
   plan's Decision Log entries (eager Either pass, pin phantom, emitWith tightening,
   DistinctNames, constraint drop).
3. `CHANGELOG.md`, under `## [Unreleased]`: `### Changed` — eager validation
   (behavioral: malformed edges now fail at construction; latent bugs, not valid
   programs), declaration-order duplicate-`from` merging, `emitWith` mismatch
   rejection, `emit`-in-`onEpsilon` now a compile error, `(Bounded v, Enum v)`
   dropped from `buildTransducer`, `DistinctNames` constraint added; `### Added` —
   `buildTransducerEither`, `BuilderDefect`, `BuilderError`, `renderBuilderErrors`,
   `DistinctNames`, exported `slotNamesOf`; `### Removed` — the `unsafeCoerce` in
   `Keiki.Builder`. Note the keiro impact line per master-plan integration point 6:
   authoring surface source-compatible; `B.emit wireCtorX XTermFields{..}` unchanged.
4. Handoff to plan 68: append a dated note to the Decision Log of
   `docs/plans/68-require-explicit-emit-noemit-intent-on-every-builder-edge.md`
   stating that EP-70 landed the eager defect pass, so 68's M1 steps 4 (the
   `finalizeEdge` error) and its test-forcing expressions change shape: add a
   `DefectMissingOutputIntent` constructor to `BuilderDefect`, return it from
   `finalizeEdge`'s exactly-one-goto branch when `peOutputDecided` is false (arity
   precedence preserved by case order), render 68's exact message text in
   `renderBuilderErrors`, and force with `evaluate tr` instead of
   `evaluate (head (edgesOut tr A))`.
5. Update the master plan registry row for EP-70 and its Progress bullets in
   `docs/masterplans/16-…md`. Run `nix fmt -- --no-cache`; confirm a clean diff
   afterwards; final `cabal test all`.

Acceptance: a reader of the Builder haddock, the research doc, or the changelog gets
a description that matches the shipped behavior exactly; plan 68 can be executed
against the new mechanism without rediscovering this plan.


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki`, inside the dev shell:

```bash
nix develop
```

Baseline before any edit (should be green):

```bash
cabal build all && cabal test all
```

Reproduce defect 1 (optional but instructive, in `cabal repl keiki-test`): build a
transducer whose `from B` body omits `goto`, then evaluate `delta tr A …` — it
succeeds; only `edgesOut tr B` explodes. After M1 the same `evaluate tr` throws
immediately.

Per milestone:

```bash
# M1, M3, M4 — full verification loop
cabal build all
cabal test all

# M2 — prototype loop
cabal build keiki                 # library with the pin phantom
cabal build jitsurei              # EmailDelivery et al. unchanged
cabal test keiki-test             # fixture + BuilderSpec compile & pass

# formatting before every commit
nix fmt -- --no-cache
```

Expected test-run shape after M1 (excerpt; names indicative):

```text
Keiki.Builder (EP-15 M6)
  case 7: missing goto fires the expected runtime error
  case 8: multiple goto fires the expected runtime error
  EP-70: missing goto on an undriven vertex fails at construction
  EP-70: duplicate `from` blocks merge in declaration order
  EP-70: merged blocks report globally consistent edge indices
  EP-70: buildTransducerEither returns every defect structurally
```

Expected compile failure for the M2 repro (shape, not literal):

```text
error: [GHC-83865]
    • Couldn't match type: '[ '("x", Int), '("y", Int)]
                     with: '[ '("count", Int)]
      Expected: Term Regs ToyCmd '[ '("count", Int)] Int
        Actual: Term Regs ToyCmd '[ '("x", Int), '("y", Int)] Int
```

Commit once per milestone, Conventional Commits, each carrying the trailer
`ExecPlan: docs/plans/70-builder-correctness-hardening-eager-finalize-validation-closing-the-emit-unsafecoerce-schema-hole-and-declaration-order-edge-merging.md`.
Suggested subjects: M1
`feat(builder)!: validate all edges eagerly at buildTransducer; add buildTransducerEither`,
M2 `feat(builder): prototype schema-pinned EdgeBuilder to eliminate the emit coercion`,
M3 `feat(builder)!: remove emit unsafeCoerce; reject emitWith InCtor mismatch eagerly`,
M4 `feat(builder)!: reject duplicate register slot names at the buildTransducer boundary`,
M5 `docs(builder): true up haddocks, changelog, and the plan-68 eager-pass handoff`.
The `!` marks behavioral tightenings (all reject only previously-latent bugs).


## Validation and Acceptance

Acceptance is behavioral, per defect:

1. **Eagerness.** A transducer with a malformed edge on a vertex that no other code
   touches: `Control.Exception.evaluate tr` throws the exact legacy-format message
   naming that vertex and the edge index. Asserted by the new BuilderSpec specs,
   which force *only* the transducer value — `edgesOut` is never called in any
   failure-path assertion. Cases 7/8 keep their exact strings, proving message
   compatibility.
2. **The coercion is gone and the hole is closed.** `unsafeCoerce` no longer appears
   in `src/Keiki/Builder.hs`; the mismatched-schema `emit` program that compiles on
   the pre-plan tree fails to compile (transcript in Surprises & Discoveries;
   ongoing regression via the deferred-type-errors spec). The standard consumer
   pattern `B.emit wireCtorX XTermFields{..}` compiles with zero call-site changes —
   demonstrated by `jitsurei/src/Jitsurei/EmailDelivery.hs` (and every other
   jitsurei aggregate) building unmodified and `cabal test all` staying green.
3. **`emitWith` cannot contradict the guard.** The mismatch spec throws the new
   defect message at `evaluate tr`; the agreeing `emitWith` (case 14) still passes.
4. **Declaration order and indices.** The duplicate-`from` spec observes targets in
   authoring order; the index spec observes `edge #1` for the second block's edge.
5. **Duplicate slot names rejected.** The deferred-type-error spec throws on the
   `DupRegs` transducer; all real register files compile unchanged.

Whole-suite gate after every milestone: `cabal build all && cabal test all` green for
`keiki-test` and the jitsurei suite, and `nix fmt -- --no-cache` produces no diff.


## Idempotence and Recovery

Every step is safe to repeat: the edits are local to `src/Keiki/Builder.hs`,
`src/Keiki/Internal/Slots.hs`, one additive export in `src/Keiki/Core.hs`, tests,
and prose; `cabal build`/`cabal test`/`nix fmt` are idempotent; there are no
migrations or generated artifacts. Each milestone is one commit, so rollback is
`git revert` of that commit.

Known failure modes and retries: if an existing spec fails after M1 *only* on message
text, the `renderBuilderErrors` literal drifted from `src/Keiki/Builder.hs:728-744`'s
original strings — reconcile byte-for-byte, do not weaken assertions. If the M2
prototype cannot be made to compile, take the documented contingency (runtime
structural comparison as a `BuilderDefect`) and record it; M1/M4/M5 are unaffected.
If `-fdefer-type-errors` interacts badly with TH or the GADTs in the regression
module, fall back to the case-3 documentation precedent and record it. If a
duplicate-`from` consumer surfaces that depended on the old *reversed* order (none is
known; guard order affects nondeterministic-overlap resolution), that is a genuine
behavior change already covered by the changelog's `!` entry — do not preserve the
bug.


## Interfaces and Dependencies

No new external libraries; `Data.List.NonEmpty` is in `base` (`^>=4.21`). All work is
in the `keiki` package plus tests and docs; `jitsurei` is exercised, not edited.
GHC 9.12 features in use are already enabled in the module (DataKinds, GADTs,
TypeFamilies via imports, QualifiedDo).

End-state signatures (module `Keiki.Builder` unless noted):

```haskell
buildTransducer ::
  (DistinctNames (Names rs), Eq v, Show v) =>
  v -> RegFile rs -> (v -> Bool) ->
  VertexBuilder rs ci co v () ->
  SymTransducer (HsPred rs ci) rs v ci co

buildTransducerEither ::
  (DistinctNames (Names rs), Eq v) =>
  v -> RegFile rs -> (v -> Bool) ->
  VertexBuilder rs ci co v () ->
  Either (NonEmpty (BuilderError v)) (SymTransducer (HsPred rs ci) rs v ci co)

data BuilderDefect
  = DefectMissingGoto
  | DefectMultipleGoto Int
  | DefectOutputCtorMismatch String [String] String [String]

data BuilderError v = BuilderError
  { beVertex :: v, beEdgeIndex :: Int, beDefect :: BuilderDefect }

renderBuilderErrors :: (Show v) => NonEmpty (BuilderError v) -> String

newtype EdgeBuilder rs ci co v (pin :: Maybe [Slot]) (w :: [Symbol]) (w' :: [Symbol]) a

onCmd ::
  InCtor ci ifs ->
  (PayloadProj rs ci ifs -> EdgeBuilder rs ci co v ('Just ifs) '[] w ()) ->
  EdgeListBuilder rs ci co v ()

onEpsilon :: EdgeBuilder rs ci co v 'Nothing '[] w () -> EdgeListBuilder rs ci co v ()

emit ::
  (ToOutFields rec rs ci ifs fs) =>
  WireCtor co fs -> rec -> EdgeBuilder rs ci co v ('Just ifs) w w ()

emitWith ::
  (ToOutFields rec rs ci ifs fs) =>
  InCtor ci ifs -> WireCtor co fs -> rec -> EdgeBuilder rs ci co v pin w w ()

-- Keiki.Internal.Slots
type family DistinctNames (xs :: [Symbol]) :: Constraint

-- Keiki.Core (newly exported; pre-existing definition at src/Keiki/Core.hs:1524)
slotNamesOf :: InCtor ci ifs -> [String]
```

All other pin-indifferent combinators (`(.=)`, `(=:)`, `slot`, `reg`, `goto`,
`noEmit`, the `require*` family, `(>>=)`, `(>>)`, `pure`, `return`) keep their shapes
with `pin` as an additional free variable. `finalizeEdge`, `PartialEdge`, `Pinned`,
and the accumulator representations of `VertexBuilder`/`EdgeListBuilder` are
module-internal. Downstream contract (keiro, per the 2026-07 survey and master-plan
integration point 6): the authoring surface listed in Context and Orientation stays
source-compatible; the only new compile errors hit programs that were latently
unsound; the only new runtime errors fire earlier (at construction) on programs that
were already erroring later.
