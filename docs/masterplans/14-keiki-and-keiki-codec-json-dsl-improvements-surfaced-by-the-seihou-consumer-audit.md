---
id: 14
slug: keiki-and-keiki-codec-json-dsl-improvements-surfaced-by-the-seihou-consumer-audit
title: "Keiki and keiki-codec-json DSL improvements surfaced by the Seihou consumer audit"
kind: master-plan
created_at: 2026-06-06T14:40:56Z
intention: "intention_01ktensqv9ecmv5cd5jrbcfej7"
---

# Keiki and keiki-codec-json DSL improvements surfaced by the Seihou consumer audit

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

Seihou — the disaster-response runtime at `../keiro-runtime-jitsurei` (Incident Command and
Hospital Capacity services) — is the second substantial consumer to drive keiki hard in
anger, after Rei (MasterPlan 13). Its team wrote up the sharp edges it hit while building
service-owned event-sourced aggregate transducers in
`../keiro-runtime-jitsurei/docs/keiki-dsl-feature-requirements.md` (eight requirements). Each
was evaluated against keiki's foundational invariant — that keiki never lets the user
hand-write the event→state replay function `apply`; it *derives* it by inverting each edge's
output term (`solveOutput` in `src/Keiki/Core.hs`), and certifies at build time that the
event uniquely determines the command (`checkHiddenInputs`). A change is faithful only if it
preserves that guarantee and keeps the symbolic-register GSM formalism analyzable
(decidable per-edge analyses, single-valuedness, static output arity).

This MasterPlan addresses the seven requirements that land in keiki itself or its JSON sibling
package. After it is complete:

- A command processor or test can call `stepEither` and learn *why* a command was rejected —
  no outgoing edges, no matching edge, or ambiguous (overlapping) edges — instead of the
  single opaque `Nothing` that `step` returns today (Req 3). Ambiguity, which today silently
  rejects a command, becomes visible.
- A project can call one pure `validateTransducer` entry point in a unit test (no solver) and
  assert it returns `[]`, getting structured warnings for hidden replay inputs, overlapping
  guards (non-determinism), and unreachable (possibly-dead) edges — the Hospital
  `TransferReservationCreated` hidden-input class and the FieldResource dead self-loop the
  audit found are exactly what this surfaces (Reqs 1 and 2).
- An author who abbreviates a single command-helper name (Seihou's `DeclareIncident` →
  `Declare`) can use an all-derived TH splice with a per-constructor override instead of
  hand-listing every constructor, with duplicate/unknown names failing at compile time
  (Req 5).
- A project using `lens`/`generic-lens` can resolve the `(.>)` operator clash through a
  qualified `Keiki.Operators` import and a documented recipe, without giving up structural
  predicates (Req 7).
- A service can derive a `kind`-discriminated JSON codec *skeleton* for an event sum type
  from its constructors — with per-field override hooks and **no silent generic fallback** —
  eliminating the ~10–20 lines of hand-written aeson per event and the drift risk between the
  keiki payload shape and the stored JSON. This lives entirely in the `keiki-codec-json`
  sibling package; keiki core stays aeson-free (Req 6).
- Collection-bearing aggregates (Seihou's whole-list-in-command slots `activeResourceIds`,
  `pendingReservationIds`, `availableServiceLines`) gain a path to first-class keyed-collection
  registers with a structural AST vocabulary — *behind a design-ratification gate*, because it
  is the one change that touches the core formalism (Req 4).

**Explicitly out of scope:**

- **Req 8 — `validateEventStream` / `mkEventStream`.** This is a keiro-side smart-constructor
  that runs `validateTransducer` at the `EventStream` boundary. `EventStream` is defined in the
  keiro repo (`../keiro/keiro-core/src/Keiro/EventStream.hs`), not in keiki. It is being
  authored as a standalone ExecPlan inside the keiro repo, with a documented cross-repo soft
  dependency on this MasterPlan's Req 1 (`validateTransducer`, EP-56). See the Decision Log.
- Any change that would add an `aeson` dependency to keiki core (load-bearing constraint from
  EP-36 §3 R8 / MasterPlan 11). All JSON work is confined to `keiki-codec-json`.


## Decomposition Strategy

The work was decomposed by functional concern, not by file, so each work stream produces an
independently verifiable behavior, following the same principles MasterPlan 13 used. Six child
plans emerged, in three dependency waves.

- **EP-55 (explainable execution)** is the runtime-diagnostics stream: `stepEither` +
  `StepFailure` in `src/Keiki/Core.hs`. It is small and self-contained, and it deliberately
  goes first because it defines the canonical "edge locator / edge summary" record type that
  the build-time diagnostics stream (EP-56) reuses, so the two diagnostics surfaces speak the
  same vocabulary.
- **EP-56 (build-time validation and diagnostics)** bundles Req 1 (`validateTransducer`
  umbrella + structured warnings) and Req 2 (determinism + dead-edge checks) into one stream
  because `validateTransducer` is precisely the umbrella that runs the determinism and
  dead-edge checks — splitting them would couple a façade to its contents across a plan
  boundary. It builds the determinism check on the existing `isSingleValuedSym`
  (`src/Keiki/Symbolic.hs`) rather than reinventing the pairing logic, and keeps the default
  path pure (no z3) per Req 1's "cheap and pure" requirement.
- **EP-57 (TH ergonomics)** adds `deriveAggregateCtorsWith` / `deriveWireCtorsWith` with
  per-constructor suffix overrides and excludes in `src/Keiki/Generics/TH.hs`. It is a
  self-contained Template Haskell change touching one module and its export list.
- **EP-58 (operator-conflict resolution)** adds a new `src/Keiki/Operators.hs` for qualified
  import plus a user-guide recipe. It only re-exports existing operators and adds docs, so it
  cannot conflict with any other stream. Lowest stakes.
- **EP-59 (event codec skeleton)** lives entirely in the `keiki-codec-json` sibling package
  (new module under `keiki-codec-json/src/Keiki/Codec/JSON/`). It is independent of every
  keiki-core plan; it only consumes keiki's read-only reflection helpers.
- **EP-60 (collection registers, design-gated)** is the theoretically substantive keystone and
  the only stream that touches the core ASTs (`Term`/`Update`/`HsPred`) and the symbolic
  layer. Like EP-47 in MasterPlan 13, it opens with a ratification milestone (prototype +
  analysis) and STOPS for a maintainer go/no-go before any core edit. It implements the
  existing design note `docs/research/collection-registers-design.md` rather than the audit's
  naive flat-list proposal (which would erode the invertibility and symbolic guarantees).

Principles applied: each stream is independently verifiable by its own test or doc check;
cross-plan coupling is minimal (only EP-55↔EP-56 share a record type, and EP-56↔EP-60 share the
hidden-input/validation machinery); natural ordering is respected (the edge-summary type and the
validation machinery precede the streams that consume them). The four no-dependency streams
(EP-55, EP-57, EP-58, EP-59) form Phase 1 and parallelize; EP-56 is Phase 2; EP-60 is Phase 3,
behind its own design gate.

Alternatives considered and rejected during decomposition: (1) splitting Req 1 and Req 2 into
separate plans — rejected because `validateTransducer` is the umbrella that runs the Req 2
checks; they are one cohesive surface. (2) Folding `stepEither` (EP-55) into the validation plan
(EP-56) — rejected because one is a runtime execution verb and the other a build-time analysis;
they have independent acceptance and live on different sides of the API. (3) Implementing Req 4
(collections) as the audit literally proposed (`tCons`/`tMember`/… flat-list term ops) in a
normal plan — rejected on faithfulness grounds: as opaque `TApp` sugar those ops would defeat
`checkHiddenInputs`, `solveOutput` invertibility, and the symbolic checker; the keyed-collection
design note already specifies the sound shape, and the risk warrants a ratification gate.


## Exec-Plan Registry

| #  | Title | Path | Hard Deps | Soft Deps | Status |
|----|-------|------|-----------|-----------|--------|
| 55 | Explainable step result: stepEither and StepFailure | docs/plans/55-explainable-step-result-stepeither-and-stepfailure.md | None | None | Complete |
| 56 | Build-time validation and diagnostics: validateTransducer, determinism, and dead-edge analysis | docs/plans/56-build-time-validation-and-diagnostics-validatetransducer-determinism-and-dead-edge-analysis.md | None | EP-55 | Complete |
| 57 | Aggregate ctor derivation with per-constructor suffix overrides and excludes | docs/plans/57-aggregate-ctor-derivation-with-per-constructor-suffix-overrides-and-excludes.md | None | None | Complete |
| 58 | Namespaced predicate operators (Keiki.Operators) and lens-conflict guidance | docs/plans/58-namespaced-predicate-operators-keiki-operators-and-lens-conflict-guidance.md | None | None | Complete |
| 59 | Event codec skeleton derivation in keiki-codec-json | docs/plans/59-event-codec-skeleton-derivation-in-keiki-codec-json.md | None | None | Complete |
| 60 | First-class collection registers (design-gated) | docs/plans/60-first-class-collection-registers-design-gated.md | None | EP-56 | Complete (NO-GO at gate) |
| 67 | Collection-slot opaque-mutation signpost: validateTransducer warning and guidance | docs/plans/67-collection-slot-opaque-mutation-signpost-validatetransducer-warning-and-guidance.md | None | EP-56 | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-55).


## Dependency Graph

There are no hard dependencies: every plan compiles and is verifiable on its own. Ordering is
governed by two soft dependencies plus one design gate.

EP-56 soft-depends on EP-55. EP-55 introduces the canonical edge-identification record (working
name `EdgeRef`, carrying the source vertex and the edge's positional index) and the
rejected/matched-edge summaries that `stepEither` returns. EP-56's determinism and dead-edge
warnings need to identify edges the same way. Doing EP-55 first means EP-56 reuses one shared
vocabulary instead of defining a parallel one. If EP-56 is taken first, it must define a minimal
`EdgeRef` and EP-55 must then converge on it.

EP-60 soft-depends on EP-56. The collection feature's invariant INV3 (from
`docs/research/collection-registers-design.md`) requires `checkHiddenInputs` /
`validateTransducer` to *understand* collection `Update` constructors — a silent collection
mutation whose element data is not on the wire must be flagged. EP-56 builds the structured
validation machinery; EP-60 extends it with collection arms. EP-56 should therefore leave its
warning machinery in an extensible shape. If EP-56 is not done when EP-60 reaches that point,
EP-60 extends `checkHiddenInputs` directly.

EP-57, EP-58, and EP-59 are fully independent and can be done at any time, in parallel with
everything else. EP-59 lives in a different package (`keiki-codec-json`) and shares no code with
the core plans.

Recommended waves: **Phase 1** — EP-55, EP-57, EP-58, EP-59 in parallel. **Phase 2** — EP-56
(after EP-55). **Phase 3** — EP-60, which opens with a hard ratification gate.

EP-60's M1 is a ratification gate, not an ordinary first milestone (mirroring EP-47 in
MasterPlan 13): it produces a prototype plus a written FR6 (symbolic-translation) analysis and a
reconciliation with the now-committed Seihou consumer cases, then STOPS for an explicit
maintainer go/no-go before any `src/Keiki/` core change. A no-go is legitimate — collections
then stay opaque-`TApp`-only and the consumer uses the design note's §8 fallbacks. So Phase 3
does not auto-proceed from design to implementation.


## Integration Points

- **The edge-identification / edge-summary record(s) in `src/Keiki/Core.hs`.** Involved: EP-55
  (defines), EP-56 (consumes). The shared artifact is the `EdgeRef`/`RejectedEdgeSummary`/
  `MatchedEdgeSummary` family that locates an edge by source vertex (via `Show s`) and
  positional index in `edgesOut`. EP-55 owns these and exports them; EP-56's
  `NondeterministicPair` / `PossiblyDeadEdge` warnings reuse the same locator rather than
  inventing a parallel one. Both must keep the locator's meaning identical: the index is the
  position of the edge in `edgesOut t s`, matching how `checkHiddenInputs` (`Core.hs` ~1209)
  already `zip [0..]`-numbers edges.

- **`checkHiddenInputs` / `validateTransducer` and the collection `Update` arms.** Involved:
  EP-56 (defines the structured warning machinery and the `validateTransducer` umbrella),
  EP-60 (extends it for collection updates per INV3). The shared symbols are `checkHiddenInputs`
  (`src/Keiki/Core.hs` ~1209), its helpers `gatherInpEntries`/`stepOne` (~1156), and the new
  `TransducerValidationWarning` type EP-56 introduces. EP-56 is responsible for making the
  warning union and the per-edge walk extensible so EP-60 can add collection-update coverage
  additively. EP-60 owns the collection arms and their tests.

- **The single-valuedness analysis in `src/Keiki/Symbolic.hs`.** Involved: EP-56 (consumes),
  EP-55 (mirrors at runtime). The shared symbol is `isSingleValuedSym` (`Symbolic.hs` ~620) and
  its per-vertex edge-pairing structure. EP-56's `checkTransitionDeterminism` reuses that exact
  pairing but emits a warning per overlapping pair instead of a Bool, and offers a
  z3-backed variant via `withSymPred` (`Symbolic.hs` ~643). EP-55's runtime `AmbiguousEdges`
  failure is the dynamic witness of the same property EP-56 proves statically; the two must
  agree on what "overlap at a vertex" means.

- **The keiki-core / `keiki-codec-json` package boundary (aeson-free core).** Involved: EP-59
  only (among this MasterPlan's plans), listed because it is a load-bearing constraint every
  contributor must respect. All JSON code — including the new `deriveEventCodecSkeleton` — lives
  in `keiki-codec-json`; no plan in this MasterPlan may add `aeson` to `keiki.cabal`. EP-59
  consumes keiki's read-only reflection helpers (`RegFieldsOf`, `KnownSlotNames`, the wire-ctor
  TH) but does not modify core.


## Progress

Track milestone-level progress across all child plans. Each entry names the child plan and the
milestone. Milestones are seeded top-down here for coordination; each child plan owns the
authoritative, detailed version.

- [x] EP-55 M1: `StepFailure`/`EdgeRef`/summary types + `stepEither` in `src/Keiki/Core.hs`, `step` unchanged, success payload byte-identical to `step`. (2026-06-06)
- [x] EP-55 M2: `test/Keiki/StepEitherSpec.hs` (finite-enumeration) covering no-outgoing / no-match / ambiguous / accepting cases; registered in `keiki.cabal` + `test/Spec.hs`. (2026-06-06)
- [x] EP-56 M1: `validateTransducer` umbrella + `ValidationOptions`/`defaultValidationOptions` + structured `TransducerValidationWarning` (enriched hidden-input warnings). (2026-06-06)
- [x] EP-56 M2: `checkTransitionDeterminism` on the `isSingleValuedSym` pairing (pure default + sym variant via `withSymPred`). (2026-06-06)
- [x] EP-56 M3: `checkDeadEdges` (structural reachability, "possibly dead" labeling) + optional `checkDeadEdgesSym`; tests including the FieldResource motivation. (2026-06-06)
- [x] EP-57 M1: command-side `deriveAggregateCtorsWith` + `DeriveCtorOptions` + duplicate/unknown compile-time validation. (2026-06-06)
- [x] EP-57 M2: event-side `deriveWireCtorsWith` + tests; shared codegen helpers (`genAggregateCtors`/`genWireCtors`) and sum-type-agnostic `resolveCtorSpecs` validator extracted; negative-case error text verified verbatim. (2026-06-06)
- [x] EP-58 M1: `src/Keiki/Operators.hs` (qualified-import re-export; fixities **not** restated — see Discoveries) + cabal + qualified-path spec (`Keiki.OperatorsQualifiedSpec`, 4 examples; 304 total, 0 failures). (2026-06-06)
- [x] EP-58 M2: user-guide recipe (§6: `hiding ((.>))` / qualified `Keiki.Operators` / builder verbs; `requireGt` vs `requireGuard (x .> y)` guidance); cross-linked from `user-guide.md`. (2026-06-06)
- [x] EP-59 M1: event-sum reflection + `kind`-discriminated encode/decode skeleton with per-field override hooks in new `Keiki.Codec.JSON.Event` (`keiki-codec-json`). (2026-06-06)
- [x] EP-59 M2: no-silent-fallback safety mechanism (`FailAtCompileTime` Q-fail or `EmitTodoBindings` named `_todo_*` bindings) + `<prefix>EventTypes :: [Text]` / `<prefix>KindMap` for Keiro `eventTypes`. (2026-06-06)
- [x] EP-59 M3: round-trip + override-used + error-path + EventTypes/KindMap tests in `keiki-codec-json-test` (50 examples, 0 failures); both negative cases verified by hand; README worked example; haddock clean. In-repo demonstration only (the jitsurei dogfood is in a sibling repo, out of scope here). (2026-06-06)
- [x] EP-60 M1 (ratification gate): prototype (`test/Keiki/CollectionSpike.hs`, 18 hspec examples in the 322-example run) + FR6 analysis (recommend **Option B**) + Seihou-consumer reconciliation (flat-list ergonomics, not the symbolic story; only in-keiki guard is whole-list emptiness, already structural) + INV1–INV6 satisfiability argument. **STOPPED for maintainer GO/NO-GO** (see EP-60 "M1 Ratification Analysis" + Decision Log). (2026-06-06)
- [~] EP-60 M2–M5: **NOT pursued** — NO-GO at the M1 gate (signpost-first chosen). Deferred until a real keyed-collection consumer appears.
- [ ] EP-67 M1: opt-in `OpaqueGuard` `validateTransducer` warning (new `TransducerValidationWarning` arm + `warnOpaqueGuards` option, default off) + walkers + `ValidationSpec` cases.
- [ ] EP-67 M2: user-guide recipe (structural storage is fine; opaque guards silently degrade; the three options; EP-60 deferral pointer) + cross-link.


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments, or unexpected interactions
between child plans. Provide concise evidence.

- `Keiki.Operators` does not exist yet (verified 2026-06-06: no `src/Keiki/Operators.hs`), so
  EP-58 creates it. A `Keiki.OperatorsSpec` test module already exists from EP-45 (it tests the
  operators that live in `Keiki.Core`), so EP-58's new test is named `Keiki.OperatorsQualifiedSpec`
  to avoid a module-name clash in `test/Spec.hs`.
- **EP-58: restating operator fixities in a re-export module is a hard error on GHC 9.12 /
  GHC2024.** The EP-58 plan assumed it was "harmless" to replicate `infix` declarations in
  `Keiki.Operators`; in fact `cabal build` failed with `GHC-44432: The fixity signature for ‘.<’
  lacks an accompanying binding` — a fixity signature requires a binding *in the same module*,
  and a re-export module only re-exports the names. The fix is to omit the fixity block entirely:
  a re-exported operator carries its fixity from the defining module, so qualified users
  (`x K..> y`) still get `infix 4` from `Keiki.Core`. Any future re-export-only module (or EP-60
  if it adds a focused operator surface) must not restate fixities. (2026-06-06)
- The `keiki-codec-json` package today (verified 2026-06-06) exposes only `deriveRegFileCodec`/
  `deriveRegFileCodecAs`, which handle a *single-constructor record* (a snapshot / register file)
  and explicitly *reject* sum types. Event-sum codecs — exactly what Req 6 needs — are genuinely
  new TH; EP-59 is not extending an existing event codec but writing the first one.
- The `Edge.update` field's write-set `w` is existentially quantified, so the `update` record
  selector cannot be used as a function (GHC-55876, a fact already recorded in MasterPlan 13).
  Any plan here that walks an edge's update (EP-56's analyses, EP-60's collection updates) must
  pattern-match the `Edge`, never use the selector. The child plans note this.
- **EdgeRef convergence resolved in EP-55's favor.** EP-55 landed before EP-56, so the shared
  edge-locator is EP-55's typed `EdgeRef s = EdgeRef { edgeSource :: s, edgeIndex :: Int }`
  (carries the real vertex, not `show s`). EP-56 adopted it and parameterized *all* its warning
  types over `s` (`TransducerValidationWarning s`, `DeterminismWarning s`, `DeadEdgeWarning s`).
  The MasterPlan's "locate an edge by source vertex (via `Show s`)" wording in Integration
  Points is now slightly stale: the locator carries `s` directly and `Show s` is only used by
  the *display* layer (detail strings). Any later plan (EP-60) that emits validation warnings
  must use the same typed `EdgeRef s` and parameterize over `s`.
- **EP-60 M1 gate reached: the committed consumer is not actually blocked.** The ratification
  spike + analysis (2026-06-06) found that all three Seihou collection cases are flat `[a]`
  value-lists stored wholesale via `=:`, and their *only* in-keiki collection guard is
  whole-list emptiness (`reg .== lit []`) — already structural today as a scalar `PEq`. So the
  collection feature is an ergonomics/correctness-surface improvement for Seihou, not a current
  blocker, which both supports the cheaper FR6 **Option B** and gives a NO-GO/deferral a low
  consumer cost. Also corrected a stale design-note claim: current `stepOne` returns `Just []`
  (not `Nothing`) for `TApp` (EP-47 recompute-and-verify), so the real INV2 distinction is
  *visibility* (register-recoverable vs analysis-blind), which `TLookupField` must join on the
  recoverable side. EP-60 M2+ remain gated behind a maintainer GO. (2026-06-06)
- **EP-56 left its warning machinery extensible for EP-60 (INV3).** Adding collection-update
  coverage is additive: a new `TransducerValidationWarning` arm, or a new
  `HiddenInputReason`/clause in the top-level `hiddenInputReasons` walk (`src/Keiki/Core.hs`),
  with no change to `EdgeRef`, `ValidationOptions`, or the `validateTransducer` umbrella shape.
- **EP-59: treefmt mangles `-- |` haddock that embeds `@...@` code blocks; use
  `{- | -}` block comments for module headers.** The `treefmt` pre-commit hook
  (fourmolu) split EP-59's `Keiki.Codec.JSON.Event` line-comment module header into
  a detached comment plus a truncated block, breaking the docs. Rewriting it as a
  single `{- | ... -}` block comment with `>` bird-track code (not `@...@` blocks
  spanning lines) survived the formatter and kept haddock at 100%. Any later
  TH-heavy plan (EP-60) writing module-level haddock should prefer block comments.
  (2026-06-06)
- **EP-59: TH quotation keeps generated code's import surface at zero.** Building
  the generated `[Dec]` with `[| ... |]` quotation resolves every referenced name
  (aeson functions, the runtime helpers, the sum's constructors/selectors) to its
  origin hygienically, so a consumer module needs only `TemplateHaskell` + the
  splice — it imports neither `aeson` nor the codec module's helpers. This makes
  the aeson-free-core boundary structural, not conventional. (2026-06-06)
- **EP-57: `keiki-test` did not transitively expose `containers` to spec modules.**
  Importing `Data.Map.Strict`/`Data.Set` in `test/Keiki/Generics/THSpec.hs` failed until
  `containers >=0.6 && <0.9` was added to the `test-suite keiki-test` `build-depends`
  (it was only in the *library* stanza). Any later plan whose tests import `containers`
  (e.g. EP-60's collection-register specs) no longer needs that cabal edit — it is now
  in place. (verified 2026-06-06)
- `RegFile` has **no** `Eq`/`Show` instance, not even for the empty slot list `'[]` (verified
  while implementing EP-55: `grep -rn "instance .*(Eq|Show) (RegFile" src/Keiki/*.hs` is empty;
  `CoreSpec` only ever inspects step results by pattern match, never `shouldBe` on a whole
  `RegFile`). Any plan whose tests want to `shouldBe`-compare a value that *contains* a
  `RegFile` (e.g. EP-56 asserting a full step/validation result, or EP-60 asserting register
  contents) cannot do so directly — either pattern-match and compare the inspectable parts
  (EP-55's approach) or add an `Eq`/`Show (RegFile rs)` instance as a deliberate, separately
  scoped core change. EP-55 chose the former to stay additive.


## Decision Log

- Decision: Scope this MasterPlan to the seven keiki / keiki-codec-json requirements (Reqs 1–7),
  and exclude Req 8 (`validateEventStream`).
  Rationale: Req 8 targets keiro's `EventStream` type, defined in the keiro repo
  (`../keiro/keiro-core/src/Keiro/EventStream.hs`), not keiki. It is a thin smart-constructor
  applying Req 1's `validateTransducer` at the runtime boundary, so it belongs in keiro and
  soft-depends on EP-56.
  Date: 2026-06-06

- Decision: Author Req 8 as a standalone ExecPlan inside the keiro repo (not under a keiro
  MasterPlan), with a documented cross-repo soft dependency on EP-56.
  Rationale: it is a single, self-contained runtime feature; a MasterPlan would be overhead
  unless more keiro-side work were expected to follow. (Chosen by the user.)
  Date: 2026-06-06

- Decision: Decompose into six child plans in three phases (Phase 1: EP-55/57/58/59 parallel;
  Phase 2: EP-56; Phase 3: EP-60 gated).
  Rationale: by functional concern, minimal coupling, EP-60 isolated as the only formalism-
  touching change behind a ratification gate.
  Date: 2026-06-06

- Decision: Merge Req 1 (`validateTransducer`) and Req 2 (determinism + dead-edge) into one plan
  (EP-56).
  Rationale: `validateTransducer` is the umbrella that runs the Req 2 checks; they form one
  cohesive build-time validation surface and share the warning machinery.
  Date: 2026-06-06

- Decision: Accept Req 3 (`stepEither`) as its own plan (EP-55) and have it own the shared
  edge-summary record type EP-56 consumes; keep `step` unchanged.
  Rationale: `step`'s collapse of no-match and ambiguity into `Nothing` hides a latent single-
  valuedness violation; surfacing it is the core value. Keeping `step` minimal preserves the
  existing API. Both diagnostics surfaces (runtime EP-55, build-time EP-56) should speak one
  vocabulary, so the locator type is defined once.
  Date: 2026-06-06

- Decision: Accept Req 4 (collections) as a *design-gated* plan (EP-60) that implements
  `docs/research/collection-registers-design.md`, NOT the audit's literal flat-list term ops.
  Rationale: as opaque `TApp` sugar, flat list/set ops would defeat `checkHiddenInputs`,
  `solveOutput` invertibility, and the symbolic checker. The keyed-collection design note already
  specifies the sound shape (structural updates, `TLookupField` for output invertibility, FR6
  Option B graceful-and-queryable degradation, static output arity). Because it is the only
  change to the core formalism, it opens with a ratification gate like EP-47, with a legitimate
  no-go outcome (the §8 fallbacks). The Seihou consumer revives the design's motivation — the
  note's "no committed consumer as of 2026-05-20" is now stale.
  Date: 2026-06-06

- Decision: Accept Req 5 (TH overrides), Req 6 (event codec skeleton), Req 7 (operators) as
  EP-57, EP-59, EP-58.
  Rationale: Req 5 and Req 7 are additive ergonomics with no formalism impact (compile-time
  validation for the TH; re-export-only module + docs for the operators). Req 6 is confined to
  the `keiki-codec-json` sibling package to preserve the aeson-free-core constraint; its key
  property is no silent generic codec fallback (compile failure or named TODO bindings), which
  is the anti-drift guarantee the requester asked for.
  Date: 2026-06-06


- Decision: At the EP-60 M1 ratification gate, record **NO-GO** on first-class collection
  registers and adopt the **signpost-first** alternative, scoped as a new child plan EP-67
  (`docs/plans/67-collection-slot-opaque-mutation-signpost-validatetransducer-warning-and-guidance.md`).
  Rationale: M1's prototype + analysis showed the committed consumer (Seihou) is not blocked
  (its only in-keiki collection guard is whole-list emptiness, already structural), and that
  what future consumers actually trip over is the *silent* degradation when an opaque `TApp`
  guard branches on collection contents — a discoverability problem. Building the full core
  formalism change speculatively (zero consumers exercising the keyed path) risks a wrong,
  irreversible AST cut and could entrench a boundary anti-pattern (the §8 sub-entity-as-aggregate
  split is often the better design). The cheap, reversible guardrail — an opt-in
  `validateTransducer` warning for opaque guards plus a doc recipe — prevents the tripping
  without committing the formalism. EP-60's M2–M5 are deferred, not rejected; revisit if a real
  keyed-collection consumer appears. (Chosen by the user.)
  Date: 2026-06-06

- Decision: Add EP-67 as a child plan; its warning targets opaque **guards** (not opaque
  *updates*).
  Rationale: an opaque update replays forward soundly and is never inverted, so it surrenders
  nothing; the silent degradation lives in guards, where an opaque `TApp` becomes a free SBV
  Boolean the determinism/dead-edge analyses cannot see. Flagging opaque guards is the precise,
  honest signpost. EP-67 soft-depends on EP-56 (it extends the `validateTransducer` machinery
  additively) and reuses the typed `EdgeRef s` locator. The new check defaults **off** to
  preserve the meaning of `defaultValidationOptions` for existing consumers.
  Date: 2026-06-06


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion. Compare the
result against the original vision.

(To be filled during and after implementation.)
