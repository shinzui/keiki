---
id: 10
slug: mermaid-topology-renderer-for-symtransducer
title: "Mermaid topology renderer for SymTransducer"
kind: master-plan
created_at: 2026-05-02T23:44:05Z
intention: "intention_01kqnh7tc1epwvtrf6fnt8jt3t"
---

# Mermaid topology renderer for SymTransducer

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

The keiki pure core makes a `SymTransducer phi rs s ci co`'s
control topology fully enumerable when `s` is `(Enum, Bounded)`:
walking `[minBound .. maxBound]` and calling `edgesOut t s` for
each vertex yields the complete edge set, with each `Edge`'s
`target`, the constructor name on the input side
(via `InCtor`'s `icName` field — see `Keiki.Core`), and the
constructor name on the output side (via `WireCtor`'s `wcName`
field). That's everything a Mermaid `stateDiagram-v2` block
needs.

`docs/research/architecture-comparison-fst-aggregate-vs-crem.md`
documents Mermaid rendering as a crem-vs-keiki gap (crem ships
`renderStateDiagram` for both per-machine topologies and composed
machine flows; keiki ships nothing). The futures note
`docs/research/future-directions-profunctors-effects-and-composition.md`
§5 sketches the rendering shape for the pre-symbolic
`Transducer` type and lists DOT and Mermaid as separate output
formats.

After this MasterPlan, keiki ships:

- A new module (likely `Keiki.Render.Mermaid`) exporting a
  pure `toMermaid :: ... -> Text` function that takes a
  `SymTransducer phi rs s ci co` (with appropriate
  `Enum`/`Bounded`/`Show` constraints on `s`) and returns a
  Mermaid `stateDiagram-v2` block as `Text`.
- A treatment for composite topologies (`Composite s1 s2` from
  `Keiki.Composition`) — either inline cross-product
  enumeration (which scales poorly) or nested subgraphs that
  render each underlying transducer's topology with the
  composite edges between them. The design milestone picks one.
- A diagram for each of the four shipped example aggregates
  (`UserRegistration`, `OrderCart`, `EmailDelivery`,
  `UserRegistrationV0`), checked into
  `docs/guide/diagrams/` (or rendered inline in the existing
  `docs/guide/*.md` topic guides) so the rendered output is
  visible to readers without running the library.
- A test (`test/Keiki/Render/MermaidSpec.hs`) that asserts
  fixed Mermaid output for at least one canonical aggregate, so
  formatting regressions surface in CI.

User-visible behaviours enabled:

- A keiki user can paste their aggregate's transducer into a
  short Haskell snippet, run `toMermaid t`, and embed the
  result in a Markdown file or Notion page. GitHub renders
  Mermaid `stateDiagram-v2` natively.
- Domain experts and reviewers see the aggregate's lifecycle
  without reading Haskell — addressing the
  "non-engineer communication" gap explicitly named in the
  futures note §5.
- PR reviewers see the diagram diff alongside the source diff,
  surfacing topology changes that pure code review misses.

In scope:

- Mermaid `stateDiagram-v2` rendering for any `SymTransducer
  phi rs s ci co` whose `s` is `(Enum, Bounded, Show)` and whose
  edges have inspectable input/output constructor names.
- Edge labels: `<input ctor> / <output ctor>` (or `<input ctor>
  / ε` for ε-edges where `output e == Nothing`). Guards and
  updates are *not* shown in the v1 label format — they're
  often non-trivial AST values; the design milestone may revisit
  if a "labelled by guard summary" variant is wanted.
- Initial-state marker (`[*] --> InitialVertex`).
- Final-state markers (`Vertex --> [*]` for each `s` where
  `isFinal t s`).
- Composite-topology rendering (the second EP — likely nested
  subgraphs, but the design milestone confirms).
- A small set of diagrams under `docs/guide/diagrams/` (or
  inline) for the existing example aggregates.
- A regression test pinning canonical Mermaid output for at
  least one aggregate.

Out of scope:

- DOT / Graphviz rendering. Listed as a future format in the
  futures note §5 but deferred — Mermaid renders inline in
  GitHub and Notion without a build step; DOT requires
  Graphviz. A follow-up MasterPlan can add DOT once Mermaid
  ships and the abstraction has settled.
- Diff visualisation (`diffTransducers` from futures note §5).
  Useful but a separate concern; defer until v1 has shipped
  and a real authoring need surfaces.
- Predicate / guard / update visualisation. Showing the AST of
  an `HsPred` or an `Update` in a state diagram would clutter
  the topology view; a richer "edge inspector" view is a
  separate concern (probably interactive, not Markdown-static).
- Runtime / interactive diagrams. Pure rendering only; no SVG
  generation, no JavaScript embedding, no clickable nodes.
- A CLI / cabal-run target. The renderer is a pure function in
  the library; users embed it in their own scripts. A
  `keiki-render` executable can come later if there's demand.


## Decomposition Strategy

Four child ExecPlans, in two phases.

**Phase 1 — Foundation (shipped 2026-05-03):**

1. **EP-30 (single-transducer Mermaid renderer + first diagrams).**
   Ships `Keiki.Render.Mermaid.toMermaid` for the single-transducer
   case, the supporting helpers (`vertexLabel`, `edgeLabel`), the
   `(Enum, Bounded, Show)` constraint discipline, and four
   canonical diagrams (one per shipped Examples module).
   Acceptance: Mermaid output renders in a Markdown preview and
   matches a checked-in expected value in
   `test/Keiki/Render/MermaidSpec.hs`.

2. **EP-31 (sequential-composition composite renderer).** Picks
   an approach (nested subgraphs vs. cross-product enumeration)
   and ships rendering for the `compose`-produced `Composite s1
   s2` shape. Acceptance: a composite diagram for the existing
   `AlertSource ⨾ EmailDelivery` test fixture renders to a
   Mermaid block that round-trips through GitHub's renderer.

**Phase 2 — Coverage extensions (added 2026-05-03 after Phase 1
shipped):**

3. **EP-32 (Shape B nested-subgraph rendering for larger
   sequential composites).** EP-31 deliberately picked the **flat
   cross-product** form (Shape A) and deferred Shape B (nested
   subgraphs) to a follow-up — both because LLM-agent
   implementers couldn't perform the GitHub-renderer
   visual-verification step EP-31's plan envisaged, and because
   the chosen test fixture (`AlertSource ⨾ EmailDelivery`) was
   too small to demonstrate Shape B's structural benefit. EP-32
   ships `toMermaidCompositeNested` using a Shape B variant that
   sidesteps the verification concern (flat identifiers claimed
   into `state … { … }` outer blocks, no dependency on
   Mermaid's `Outer.Inner` dotted cross-block syntax).
   Acceptance: a nested-form diagram for the existing fixture
   plus a regression test pinning the canonical block.

4. **EP-33 (shape-aware renderers for `alternative` and
   `feedback1` composites).** Both combinators produce
   `Composite`-vertexed transducers, but the
   sequential-composition mental model EP-31 codifies doesn't
   match their semantics: `alternative` is parallel arms with
   independent state; `feedback1` is a 3-deep cascade. EP-33
   ships `toMermaidAlternative` (parallel-arms layout, two
   `state … { … }` blocks side by side) and `toMermaidFeedback1`
   (flat 3-deep cross-product with `<show s1>_<show s2>_<show s1>`
   labels). Acceptance: per-combinator regression tests against
   the existing `siblings` / `loop` fixtures from MP-8's EP-25 /
   EP-26 specs; per-combinator diagrams under
   `docs/guide/diagrams/`.

Four EPs is comfortably within MASTERPLAN.md's "two to seven"
range and matches the genuine concern boundaries:

- EP-30 settles module surface and edge-label format. No shape
  choices.
- EP-31 picks the flat-cross-product shape for sequential
  composition, deferring Shape B and shape-aware variants.
- EP-32 picks the Shape B variant that doesn't depend on
  agent-unverifiable Mermaid syntax.
- EP-33 picks shape-aware layouts for the non-sequential
  combinators.

**Why phase-split rather than four EPs up front:** Phase 2's
choices depend on Phase 1's lessons. EP-31 discovered the
LLM-agent-verification constraint and developed the Shape A
fallback pattern; EP-32's design copies that pattern (flat
identifiers, no dotted-syntax dependency). EP-31 also discovered
the `renderTopology` factorisation; EP-33's `toMermaidFeedback1`
reuses it directly. Authoring all four EPs up front would have
locked in design choices before the relevant lessons surfaced.

**Why a MasterPlan and not multiple separate plans:** EP-30's
module surface, the edge-label format, the constraint discipline
on `s`, the `renderTopology` core, and the diagram-file
convention are all integration points that Phase 2 plans extend
rather than relitigate. A MasterPlan keeps the integration points
visible across phases.

**Alternatives considered:**

- *Single ExecPlan covering both single and composite rendering
  (the original Phase 1 alternative).* Rejected for the reason
  above: the composite choice benefits from EP-30's output
  existing first.
- *Author EP-32 and EP-33 up front in Phase 1.* Rejected:
  EP-31's Shape A fallback pattern and the `renderTopology`
  factorisation were discoveries that would not have informed
  pre-Phase-1 designs. Phase 2 plans land cleaner with those
  lessons baked in.
- *Bundle DOT and Mermaid into one MasterPlan.* Rejected:
  Mermaid alone covers GitHub / Notion / Markdown; DOT adds
  Graphviz as a runtime dependency for users. Different
  audiences; ship Mermaid alone, evaluate DOT demand later.
- *Render guards and updates inline in state-diagram labels.*
  Rejected: the AST of an `HsPred` or `Update` is often a
  multi-line value; cramming it into a `:` label produces
  unreadable diagrams. A topology-only view is the right
  primitive; a richer per-edge inspector is a separate
  concern.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Mermaid renderer for single SymTransducer + canonical example diagrams | docs/plans/30-mermaid-renderer-for-single-symtransducer-canonical-example-diagrams.md | None | None | Complete |
| 2 | Mermaid rendering for Composite SymTransducers | docs/plans/31-mermaid-rendering-for-composite-symtransducers.md | EP-30 | EP-4 (external) | Complete |
| 3 | Shape B nested-subgraph Mermaid rendering for larger composites | docs/plans/32-shape-b-nested-subgraph-mermaid-rendering-for-larger-composites.md | EP-30, EP-31 | None | Complete |
| 4 | Shape-aware Mermaid renderers for alternative and feedback1 composites | docs/plans/33-shape-aware-mermaid-renderers-for-alternative-and-feedback1-composites.md | EP-30, EP-31, EP-25 (external), EP-26 (external) | EP-32 | In Progress |

Status values: Not Started, In Progress, Complete, Cancelled.

External-dep glossary:

- **EP-4** is MP-4's child plan
  `docs/plans/4-composition-combinators-on-symtransducer.md`,
  which delivered the existing `compose` and the `Composite s1
  s2` newtype EP-31 / EP-32 render.
- **EP-25** is MP-8's child plan
  `docs/plans/25-alternative-composition-combinator-on-symtransducer.md`,
  which delivered the `alternative` combinator EP-33 renders.
- **EP-26** is MP-8's child plan
  `docs/plans/26-single-step-feedback-combinator-on-symtransducer.md`,
  which delivered the `feedback1` combinator EP-33 renders.

All three external deps are already shipped as of MP-10's
authoring date; they appear here for traceability rather than as
gating constraints.


## Dependency Graph

```
                 ┌──────────────┐
                 │   EP-30      │
                 │  Single      │
                 │  Mermaid     │
                 └──────┬───────┘
                        │ (hard)
                        ▼
                 ┌──────────────┐
                 │   EP-31      │
                 │  Sequential  │
                 │  Composite   │
                 │  (Shape A)   │
                 └──────┬───────┘
                        ▲
                        │ (soft)
                        │
              ┌─────────┴─────────┐
              │ EP-4 (external)   │
              │ existing compose  │
              │ + Composite       │
              └───────────────────┘

                 ┌──────────────┐
                 │   EP-31      │
                 └──┬─────────┬─┘
              hard  │         │ hard
                    ▼         ▼
            ┌────────────┐ ┌────────────────┐
            │   EP-32    │ │     EP-33      │
            │  Shape B   │◄┤  alternative + │
            │  (nested   │ │  feedback1     │
            │   compose) │ │  shape-aware   │
            └────────────┘ └────────┬───────┘
                                    │ hard
                              ┌─────┴──────────┐
                              │ EP-25 / EP-26  │
                              │   (external)   │
                              │ alternative +  │
                              │ feedback1 ops  │
                              └────────────────┘
```

**Hard dependencies:**

- EP-31 → EP-30: the single-transducer renderer's helpers
  (vertex labelling, edge labelling, state markers) and the
  `(Enum, Bounded, Show)` constraint discipline are reused by
  the composite renderer.
- EP-32 → EP-30, EP-31: reuses `compositeLabel` (from EP-31),
  `edgeLabel` (from EP-30), and the diagram-file convention.
- EP-33 → EP-30, EP-31, EP-25, EP-26: reuses `vertexLabel`,
  `edgeLabel`, `renderTopology` from EP-30/EP-31, and renders
  the `alternative` and `feedback1` combinators that EP-25 /
  EP-26 ship.

**Soft dependencies:**

- EP-31 → EP-4 (external): structural — EP-4 already shipped the
  `Composite s1 s2` newtype and the `compose` operator that
  produces the composites EP-31 renders.
- EP-33 → EP-32: a sibling Phase 2 plan; EP-33 has no code-level
  dependency on EP-32 but the test count baseline / `Spec.hs`
  describe-block title coordination is simpler if either lands
  before the other rather than concurrently. Either order is
  acceptable.

EP-32 and EP-33 can land in any order relative to each other.
EP-32's M0 baseline test count is 198 if it ships before EP-33,
199 if EP-33 shipped first; EP-33's M0 baseline is the
symmetric equivalent. Each plan's M0 milestone instructs the
implementer to record the actual baseline rather than assume.


## Integration Points

### IP-1: `Keiki.Render.Mermaid` module

**Plans involved:** EP-30 (creates), EP-31 (extends with
`toMermaidComposite` + `compositeLabel` + private
`renderTopology` helper), EP-32 (extends with
`toMermaidCompositeNested`), EP-33 (extends with
`toMermaidAlternative`, `toMermaidAlternativeWith`,
`toMermaidFeedback1`).

**Owner:** EP-30 owns the original surface (exported names,
`(Enum, Bounded, Show)` constraint discipline on `s`,
`renderTopology` skeleton after EP-31's M2 refactor). Phase 2
plans (EP-32, EP-33) **add** functions but **do not** rename or
remove existing exports.

**Coordination rule:** every renderer entry point lives in
`Keiki.Render.Mermaid`; no sibling rendering modules are
introduced. Helpers private to a single renderer (e.g.
`feedback1Label` in EP-33) stay un-exported. If two plans need
the same helper, promote it to a top-level export in the plan
that lands second.

### IP-2: Edge label format

**Plans involved:** EP-30 (defines); EP-31, EP-32, EP-33 (use
unchanged).

**Owner:** EP-30. The v1 format is `<input ctor> / <output
ctor>` (or `<input ctor> / ε` for ε-edges, `?` for missing input
names). The input constructor name comes from the `InCtor`'s
`icName :: Text` field carried inside `HsPred`'s `PInCtor` atom
(see `Keiki.Core`); the output constructor name comes from the
`OPack`'s `WireCtor`'s `wcName :: Text` field.

**Coordination rule:** every composite renderer uses
`edgeLabel` unchanged; only the *vertex* labelling varies by
shape.

For `alternative`-shaped composites (EP-33), the label format
naturally surfaces the underlying constructor names because
`leftInCtor` / `rightInCtor` / `leftWireCtor` / `rightWireCtor`
preserve `icName` / `wcName` (see `Keiki.Composition`). So edge
labels read like `SendEmail / EmailSent` even though the
runtime input is `Left sampleSendEmail`.

### IP-3: Example diagrams under `docs/guide/diagrams/`

**Plans involved:** EP-30 (chooses the directory location, ships
four single-transducer diagrams); EP-31 (adds one composite);
EP-32 (adds nested-form sibling diagram(s)); EP-33 (adds
per-combinator diagrams for `alternative` and `feedback1`).

**Owner:** EP-30 picked the location: a new `docs/guide/diagrams/`
folder with one `.md` per aggregate, each containing a short
prose header, a regeneration recipe, and a fenced ```mermaid
block. EP-31 / EP-32 / EP-33 follow the same convention.

**Coordination rule:** all rendered diagrams are checked in as
literal Mermaid source in Markdown — not as pre-rendered SVG /
PNG — so GitHub renders them inline and the source stays
diff-friendly. Diagram files for fixtures defined in test
modules (`Keiki.CompositionSpec.pipeline`,
`Keiki.CompositionAlternativeSpec.siblings`,
`Keiki.CompositionFeedback1Spec.loop`) include a
`cabal repl keiki-test` regeneration recipe; library-fixture
diagrams use `cabal repl` directly. EP-31 established this
distinction; EP-32 / EP-33 follow it.

### IP-4: Regression test in `test/Keiki/Render/MermaidSpec.hs`

**Plans involved:** EP-30 (creates the spec module with one
describe block); EP-31 (adds a second describe block); EP-32
(adds a third); EP-33 (adds two more — one per shape-specific
renderer).

**Owner:** EP-30. Each subsequent plan adds a top-level describe
block to the same spec file rather than introducing a new spec
module. This keeps the formatting drift surface concentrated:
any rendering change touches the same test file as the
producer change.

**Coordination rule:** the expected-output strings are stored
inline at module scope (not in external fixture files), each
named after the fixture it pins (`userRegCanonical`,
`alertEmailCompositeCanonical`,
`alertEmailCompositeNestedCanonical`,
`emailPingerAltCanonical`, `toggleFeedback1Canonical`).
Anti-validation (a transient mutation that surfaces a clear
diff before commit) is mandatory in each plan's M-final
milestone.

The describe-block wrapper title in `test/Spec.hs` reads
`Keiki.Render.Mermaid (EP-30, …)` and grows as plans land. The
implementer of the most recently landing plan updates the
title; if two Phase 2 plans land in close succession, only the
second needs to update the title.

### IP-5: Test fixture re-export from spec modules

**Plans involved:** EP-31 (established the pattern — exports
`alertSource`, `AlertVertex (..)` from
`Keiki.CompositionSpec`); EP-33 (extends to
`Keiki.CompositionAlternativeSpec` and
`Keiki.CompositionFeedback1Spec`).

**Owner:** EP-31. Per its M4 Decision Log entry of 2026-05-03,
fixtures defined in test modules are re-exported (rather than
duplicated into a helper module) when the renderer's regression
test needs them. EP-33 follows the same pattern for the
`alternative` and `feedback1` fixtures.

**Coordination rule:** the export-list comment in each spec
module points back to the renderer's plan file so future
readers understand why the spec module's API exceeds `spec`.
EP-32 does NOT extend this pattern — its Idempotence section
explains why a Render-namespaced helper module is the right
choice if EP-32's implementer adds a synthetic richer fixture.


## Progress

Track milestone-level progress across all child plans.

Phase 1 (shipped 2026-05-03):

- [x] EP-30: Verify prerequisites — Keiki.Core / Keiki.Examples build, all tests pass; record GHC version (M0)
- [x] EP-30: Choose constraint discipline on `s`; pick text representation library (`text` already a dep) (M1+M2 — M1 rolled into M2)
- [x] EP-30: Implement `toMermaid` for the single-transducer case; cover initial / final / ε edges (M2)
- [x] EP-30: Render diagrams for the four Examples modules; check in to docs/guide/ (M3)
- [x] EP-30: Add regression test pinning Mermaid output for UserRegistration (M4)
- [x] EP-31: Pick composite rendering approach (subgraphs vs. cross-product); document trade-off (M1)
- [x] EP-31: Implement composite rendering on `Composite s1 s2` (M2)
- [x] EP-31: Render diagram for `AlertSource ⨾ EmailDelivery` composite; check in (M3)
- [x] EP-31: Add regression test for composite Mermaid output (M4)

Phase 2 (added 2026-05-03; not started):

- [x] EP-32: Verify prerequisites and record baseline test count (M0)
- [x] EP-32: Verify the chosen Mermaid syntax (flat identifiers in outer state blocks) renders correctly in a Mermaid-aware previewer; pause for human verifier if implementer is an LLM agent (M1)
- [x] EP-32: Implement `toMermaidCompositeNested` (M2)
- [x] EP-32: Render Shape B sibling diagram for the existing fixture (M3)
- [x] EP-32: Add regression test pinning canonical Shape B output (M4)
- [ ] EP-33: Verify prerequisites (EP-30, EP-31, EP-25, EP-26) and record baseline (M0)
- [ ] EP-33: Design `toMermaidAlternative`'s parallel-arms layout; verify Mermaid syntax (M1)
- [ ] EP-33: Design `toMermaidFeedback1`'s flat 3-deep cross-product layout (M2)
- [ ] EP-33: Implement `toMermaidAlternative` + `toMermaidAlternativeWith` (M3)
- [ ] EP-33: Implement `toMermaidFeedback1` (M4)
- [ ] EP-33: Render diagrams for `alternative` and `feedback1` fixtures (M5)
- [ ] EP-33: Add regression tests for both shape-aware renderers (M6)


## Surprises & Discoveries

- 2026-05-03 — EP-31's M1 verification step (visual confirmation of
  GitHub rendering Mermaid 8.7+ nested-state syntax for cross-cutting
  transitions) is not performable by an LLM-agent implementer. The
  plan was authored with a human verifier in mind. EP-31 fell back to
  the explicitly-spec'd Shape A (flat cross-product), which is
  rendering-engine-agnostic. The chosen test fixture
  (`AlertSource ⨾ EmailDelivery`) has zero same-outer composite
  edges, which would have left both Shape B outer subgraphs empty —
  a degenerate case for Shape B. So the agentic-fallback path
  happened to align with the fixture's structure. Future agentic
  implementations of similar plans should expect verification steps
  that require visual judgement to be unperformable and either
  pre-spec a deterministic fallback (as this plan did) or surface
  them to a human.

- 2026-05-03 — EP-31's M4 fixture-strategy decision deviated from the
  plan's prescription: the plan recommended duplicating the
  `alertSource` fixture in a helper module
  (`Keiki.Render.MermaidCompositeFixture`); EP-31 instead exported
  the existing fixture from `Keiki.CompositionSpec`. The fixture
  size (~80 lines of TH-laden code) is ~4× larger than the plan's
  estimate (~20 lines), and the duplication-drift hazard the plan
  itself flagged in its Idempotence section was the dominant
  concern. The "pollutes the spec module's API" cost the plan named
  for the export-based approach is illusory for a test module.
  Future composite-renderer EPs can re-use the same export-based
  pattern; no new fixture-helper-module convention to maintain.

- 2026-05-03 — Implementation-time refactor opportunity: EP-30's
  `toMermaid` and EP-31's `toMermaidComposite` are structurally
  identical except for the vertex-label function. EP-31's M2
  factored the rendering core into a private
  `renderTopology :: (s -> Text) -> SymTransducer ... -> Text`
  helper that both call. Worth keeping in mind for future renderer
  variants (DOT, alternative-shape, etc.): they almost certainly
  share the same skeleton.

- 2026-05-03 — EP-32's `toMermaidCompositeNested` does NOT reuse
  `renderTopology`. Reason: its body inserts `state … { … }`
  blocks between the init line and the edge / final lists, fanning
  the enumeration out across both s1 (outer-block walk) and s2
  (inner-identifier walk) independently of the composite-edge
  walk. `renderTopology`'s skeleton (init → edges → finals,
  parametrised only by a label function) doesn't accommodate this.
  Inlining the rendering body in EP-32 was simpler than
  generalising `renderTopology` to a "blocks-emit" hook. EP-33's
  `toMermaidFeedback1` plan tentatively reuses `renderTopology`
  via a 3-tuple label function (because its layout IS just
  init → edges → finals), but its `toMermaidAlternative` plan
  takes the inline route again because parallel-arms layout
  walks each arm independently. Pattern: reuse `renderTopology`
  when the layout is the same shape; inline when it diverges.

- 2026-05-03 — `[minBound .. maxBound]` enumerations across
  multiple type parameters (e.g. EP-32's outer/inner/composite
  fan-out) need `ScopedTypeVariables` plus explicit `:: [s1]`
  list annotations. EP-30's and EP-31's renderers don't hit this
  because their enumerations are tied to the transducer's `s`
  through the label function `(s -> Text)`. EP-33's
  `toMermaidAlternative` (independent walks over t1's s1 and
  t2's s2) and `toMermaidFeedback1` (3-deep over s1, s2, s1)
  will hit the same pattern. Recorded as a Surprise in EP-32's
  plan so future implementers don't waste a build cycle on it.


## Decision Log

- Decision: Mermaid first; DOT / Graphviz deferred to a
  follow-up MasterPlan.
  Rationale: Mermaid renders inline in GitHub, Notion, and
  every modern Markdown previewer with no extra dependency on
  the reader's side. DOT requires Graphviz as a build-time
  dependency for renderers. Shipping Mermaid alone covers the
  "domain expert / PR review" use cases that motivate
  visualisation in the futures note §5.
  Date: 2026-05-02

- Decision: Topology-only labels in v1 — no guard / update /
  predicate visualisation in the diagram itself.
  Rationale: `HsPred` ASTs and `Update` combinator trees are
  often multi-line; embedding them in `:` labels produces
  unreadable diagrams. Topology-only is the readable,
  reviewable primitive; richer per-edge inspection is a
  separate (probably interactive) concern.
  Date: 2026-05-02

- Decision: Two EPs (single and composite) rather than one
  combined plan.
  Rationale: The composite-rendering choice (subgraphs vs.
  cross-product) benefits from EP-30's single-transducer
  renderer being observable first — implementers can see how
  the subgraph syntax actually renders before committing to
  it. A single EP would force the composite choice early.
  Date: 2026-05-02

- Decision: Use a different Intention ID for this MasterPlan
  (`intention_01kqnh7tc1epwvtrf6fnt8jt3t`) than the other three
  plans created in the same session.
  Rationale: User-directed at plan-creation time. Indicates
  this MasterPlan tracks against a separate intention from
  MP-8 / MP-9 / EP-23 (which share the v1-pure-core-completion
  intention). Visualisation is operational tooling rather than
  pure-core completion.
  Date: 2026-05-02

- Decision: Add Phase 2 — EP-32 (Shape B nested-subgraph
  rendering for sequential composites) and EP-33 (shape-aware
  renderers for `alternative` and `feedback1` composites) — as
  two new child plans rather than reopening EP-31's plan or
  closing them out as never-to-ship deferrals.
  Rationale: Both items were explicitly named in EP-31's
  Outcomes & Retrospective as deferred follow-ups. The
  decomposition argument (separate plan = separate decision
  context for each shape choice) that motivated the original
  EP-30/EP-31 split applies symmetrically to the Phase 2 plans:
  EP-32 picks a Shape B variant that sidesteps the
  agent-unverifiable Mermaid syntax EP-31 ran into; EP-33
  picks per-combinator layouts. Folding either into a sibling
  EP would force decisions that benefit from being made
  independently. Each plan is small (4–6 milestones, ~one
  ghci-validation pass per renderer, no new build deps) and
  self-contained.
  Date: 2026-05-03

- Decision: EP-32 commits to the **flat-identifier-in-outer-block**
  variant of nested rendering, NOT Mermaid's `Outer.Inner`
  dotted cross-block reference syntax.
  Rationale: EP-31's plan documented the dotted-syntax variant
  as one of two candidate Shape B forms but couldn't verify it
  rendered correctly in GitHub. The flat-identifier variant
  (e.g. `state AlertQuiescent { AlertQuiescent_EmailPending; … }`
  with cross-cutting transitions written using the flat
  identifiers at the top level) sidesteps the question
  entirely — it's well-supported standard Mermaid syntax with no
  version-specific concerns. Picking it now closes the door on
  EP-31's open question without re-doing visual verification.
  Date: 2026-05-03

- Decision: EP-33 ships separate `toMermaidAlternative` and
  `toMermaidFeedback1` functions rather than a single
  shape-detecting `toMermaidCompositeAuto` wrapper.
  Rationale: The composite vertex type does not distinguish
  `compose`, `alternative`, and `feedback1` — all three produce
  `Composite`-vertexed transducers, and the differentiation
  lives in the combinator that built them, not in the resulting
  value. Letting users pick the renderer matching their call
  site avoids the "tag composites at construction time" can of
  worms and keeps the renderer code direct.
  Date: 2026-05-03


## Outcomes & Retrospective

**Phase 1 shipped (2026-05-03).** The entries below summarise
EP-30 / EP-31 only; Phase 2 (EP-32 + EP-33) outcomes will be
appended when those plans complete.

**Phase 1 — Shipped:**

- `Keiki.Render.Mermaid` (in `src/Keiki/Render/Mermaid.hs`) is the
  pure Mermaid `stateDiagram-v2` renderer for keiki. Public surface:
  - `toMermaid` — single-transducer renderer
    (`(Enum s, Bounded s, Show s) => SymTransducer (HsPred rs ci) rs s ci co -> Text`).
  - `toMermaidComposite` — composite-transducer renderer
    (`( Enum s1, Bounded s1, Show s1, Enum s2, Bounded s2, Show s2 )
       => SymTransducer (HsPred rs ci) rs (Composite s1 s2) ci co -> Text`),
    flat cross-product shape with `<show s1>_<show s2>` vertex labels.
  - Helpers: `vertexLabel`, `compositeLabel`, `edgeInputName`,
    `edgeOutputName`, `edgeLabel`.
- Five canonical diagrams under `docs/guide/diagrams/`: one per
  shipped Examples module from EP-30 (`UserRegistration`,
  `OrderCart`, `EmailDelivery`, `UserRegistrationV0`) plus the
  composite (`composite-alert-email.md`).
- Two regression tests in `test/Keiki/Render/MermaidSpec.hs` pinning
  the canonical Mermaid blocks for `userReg` and the
  `AlertSource ⨾ EmailDelivery` composite. `cabal test` reports 198
  examples, 0 failures.

**Behaviour now possible:** a keiki user with a `SymTransducer` value
(or a `compose`-produced composite) can call the appropriate
renderer, paste the resulting `Text` into a Markdown file or Notion
page, and see the topology rendered inline in any Mermaid-aware
viewer (GitHub, VS Code preview, Notion). PR reviewers see topology
diffs alongside source diffs; domain experts read the diagram
without opening Haskell. Both gaps named in the futures note §5 and
the crem comparison are closed for the topology-only view.

**What remains:**

Two of the deferred follow-ups originally listed here were
promoted into Phase 2 child plans on 2026-05-03 — see the Decision
Log entry of that date. These are tracked by their own EPs:

- Shape B nested-subgraph rendering for larger composites is now
  EP-32 (`docs/plans/32-shape-b-nested-subgraph-mermaid-rendering-for-larger-composites.md`).
  Closes the open question EP-31 deferred about Mermaid syntax
  verification by committing to the flat-identifier-in-outer-block
  variant.
- Composite-renderer variants for `alternative` and `feedback1`
  are now EP-33
  (`docs/plans/33-shape-aware-mermaid-renderers-for-alternative-and-feedback1-composites.md`).
  Ships `toMermaidAlternative` (parallel-arms layout) and
  `toMermaidFeedback1` (flat 3-deep cross-product).

Still deferred (not promoted to a Phase 2 plan):

- DOT / Graphviz rendering — listed as a future format; deferred
  pending demand. Would be a separate `Keiki.Render.Dot` module
  using the same `renderTopology` skeleton parametrised over a
  syntax-emit function.
- Diff visualisation across two `SymTransducer` values
  (`diffTransducers` from the futures note).
- Per-edge guard / update inspection (the "richer interactive
  edge inspector" the v1 explicitly excluded).
- Specialised renderers for arbitrary nested `Composite` shapes
  authored by stacking `compose` beyond the two combinators EP-33
  covers. EP-33's Decision Log records the rationale.

**Lessons:**

- The MasterPlan's two-EP split (single + composite) was the right
  call: EP-30 settled the module surface and edge-label format
  before EP-31 had to reason about composite-shape choices; EP-31
  reused all of EP-30's helpers (eventually via `renderTopology`)
  rather than relitigating them. A single-EP version would have
  forced both decisions in parallel.
- Verification steps that require visual judgement (M1's
  GitHub-render check) should be either pre-spec'd with a
  deterministic fallback (as EP-31 did with Shape A) or flagged for
  a human reviewer. LLM-agent implementers cannot complete those
  steps as-written.
- The "structurally identical to <existing function>" framing the
  plan used for `toMermaidComposite` is a reliable
  parameterise-the-difference signal during implementation; the
  resulting `renderTopology` helper landed cleanly with zero
  duplication.


## Revision Notes

- 2026-05-03 — Added Phase 2 child plans EP-32 (Shape B
  nested-subgraph rendering for sequential composites) and EP-33
  (shape-aware renderers for `alternative` and `feedback1`
  composites). Both were deferred follow-ups in EP-31's Outcomes &
  Retrospective; promoted to first-class child plans rather than
  remaining open-ended deferrals. Updated sections: Decomposition
  Strategy (introduced Phase 1 / Phase 2 split, replaced the
  "two child ExecPlans" framing with four-EP-in-two-phases),
  Exec-Plan Registry (added EP-32 and EP-33 rows; documented
  EP-25 / EP-26 external deps), Dependency Graph (extended ASCII
  graph to show both new EPs and their hard / soft dep edges),
  Integration Points (extended IP-1 / IP-3 / IP-4 to cover Phase
  2 plans; added IP-5 documenting the test-fixture re-export
  pattern EP-31 established and EP-33 follows), Progress (added
  Phase 2 milestones), Decision Log (added three entries dated
  2026-05-03 for the Phase 2 addition, EP-32's syntax choice, and
  EP-33's two-function API decision), Outcomes & Retrospective
  (re-titled the "Shipped" entry as Phase 1; rewrote the "What
  remains" section to point at the new Phase 2 plans for two of
  the deferred items).
