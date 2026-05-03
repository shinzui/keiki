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

Two child ExecPlans:

1. **EP A (single-transducer Mermaid renderer + first
   diagrams).** Ships `Keiki.Render.Mermaid.toMermaid` for the
   single-transducer case, the supporting helpers
   (`vertexLabel`, `edgeLabel`), the `(Enum, Bounded, Show)`
   constraint discipline, and four canonical diagrams (one per
   shipped Examples module). Acceptance: Mermaid output renders
   in a Markdown preview and matches a checked-in expected
   value in `test/Keiki/Render/MermaidSpec.hs`.
2. **EP B (composite-topology rendering for `Composite s1 s2`).**
   Picks an approach (nested subgraphs vs. cross-product
   enumeration) and ships rendering for the
   `compose`-produced `Composite s1 s2` shape. Acceptance: a
   composite diagram for the existing
   `AlertSource ⨾ EmailDelivery` test fixture in
   `test/Keiki/CompositionSpec.hs` renders to a Mermaid block
   that round-trips through GitHub's renderer.

Two EPs is at the small end of MASTERPLAN.md's "two to seven"
guidance and matches the genuine concern boundary: EP A
delivers a usable single-transducer renderer with no shape
choices left to revisit; EP B picks the composite shape, which
has a real choice (subgraphs vs. cross-product) that benefits
from being its own decision context.

**Why a MasterPlan and not a single ExecPlan:** EP B's
composite-shape choice is consequential (subgraphs require
Mermaid 8.7+; cross-product blows up vertex count for non-trivial
composites) and benefits from being settled with EP A's
single-transducer code already in hand — implementers can see
the subgraph syntax actually rendering before committing to it.
A single ExecPlan would force EP B's choice to be made before
EP A's output is observable, increasing rework risk.

**Alternatives considered:**

- *Single ExecPlan covering both single and composite
  rendering.* Rejected for the reason above: the composite
  choice benefits from EP A's output existing first.
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
| 2 | Mermaid rendering for Composite SymTransducers | docs/plans/31-mermaid-rendering-for-composite-symtransducers.md | EP-30 | EP-4 (external) | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
"EP-4 (external)" is MP-4's child plan
`docs/plans/4-composition-combinators-on-symtransducer.md`,
which delivered the existing `compose` and the `Composite s1
s2` newtype EP-31 here renders.


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
                 │  Composite   │
                 │  Mermaid     │
                 └──────────────┘
                        ▲
                        │ (soft)
                        │
              ┌─────────┴─────────┐
              │ EP-4 (external)   │
              │ existing compose  │
              │ + Composite       │
              └───────────────────┘
```

EP-31 hard-depends on EP-30 because the single-transducer
renderer's helpers (vertex labelling, edge labelling, state
markers) are reused by the composite version. EP-31's soft
dependency on EP-4 is structural — EP-4 already shipped the
`Composite s1 s2` newtype and the `compose` operator that
produces the composites EP-31 renders, so EP-31 can land
whenever after EP-30 (no need to wait on MP-8's new
combinators; their composites are added to EP-31's coverage
when MP-8's children land, via a follow-up revision rather
than a hard dep).


## Integration Points

### IP-1: `Keiki.Render.Mermaid` module

**Plans involved:** EP-30 (creates), EP-31 (extends).

**Owner:** EP-30. The module's surface — exported names,
constraint discipline on the `s` parameter — is decided in
EP-30 and named here once the EP lands. EP-31 extends the
same module with composite-aware variants.

### IP-2: Edge label format

**Plans involved:** EP-30 (defines).

**Owner:** EP-30. The v1 format is `<input ctor> / <output
ctor>` (or `/ ε` for ε-edges). The input constructor name
comes from the `InCtor`'s `icName :: Text` field carried inside
`HsPred`'s `PInCtor` atom (see `Keiki.Core`); the output
constructor name comes from the `OPack`'s `WireCtor`'s `wcName ::
Text` field. EP-30 names the exact extraction code path.

**Coordination rule:** EP-31's composite rendering uses the
same edge-label format; only the *vertex* labelling differs
(composite vertices nest into subgraphs).

### IP-3: Example diagrams under `docs/guide/`

**Plans involved:** EP-30 (single-transducer diagrams);
optionally EP-31 (composite diagram for `AlertSource ⨾
EmailDelivery`).

**Owner:** EP-30 picks the location: either a new
`docs/guide/diagrams/` folder with one `.md` per aggregate, or
inline blocks in the existing topic guides
(`docs/guide/user-guide.md`, `composition.md`, etc.). The
guide's existing structure is the deciding factor; EP-30
records the choice in its Outcomes section.

**Coordination rule:** all rendered diagrams are checked in as
literal Mermaid source in Markdown — not as pre-rendered SVG /
PNG — so GitHub renders them inline and the source stays
diff-friendly.

### IP-4: Regression test in `test/Keiki/Render/MermaidSpec.hs`

**Plans involved:** EP-30 (creates), EP-31 (extends).

**Owner:** EP-30. The test pins canonical Mermaid output for
at least one example aggregate (`UserRegistration` is the
default candidate — most coverage in existing tests). EP-31
adds an analogous expected-output assertion for the composite
shape.

**Coordination rule:** the expected-output strings are stored
inline in the test (not in external fixture files), so a
formatting change requires touching the same file as the
producer change — surfacing intentional vs. accidental shifts
in code review.


## Progress

Track milestone-level progress across all child plans.

- [x] EP-30: Verify prerequisites — Keiki.Core / Keiki.Examples build, all tests pass; record GHC version (M0)
- [x] EP-30: Choose constraint discipline on `s`; pick text representation library (`text` already a dep) (M1+M2 — M1 rolled into M2)
- [x] EP-30: Implement `toMermaid` for the single-transducer case; cover initial / final / ε edges (M2)
- [x] EP-30: Render diagrams for the four Examples modules; check in to docs/guide/ (M3)
- [x] EP-30: Add regression test pinning Mermaid output for UserRegistration (M4)
- [ ] EP-31: Pick composite rendering approach (subgraphs vs. cross-product); document trade-off (M1)
- [ ] EP-31: Implement composite rendering on `Composite s1 s2` (M2)
- [ ] EP-31: Render diagram for `AlertSource ⨾ EmailDelivery` composite; check in (M3)
- [ ] EP-31: Add regression test for composite Mermaid output (M4)


## Surprises & Discoveries

(None yet.)


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


## Outcomes & Retrospective

(To be filled during and after implementation.)
