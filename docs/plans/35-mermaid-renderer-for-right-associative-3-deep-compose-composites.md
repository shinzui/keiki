---
id: 35
slug: mermaid-renderer-for-right-associative-3-deep-compose-composites
title: "Mermaid renderer for right-associative 3-deep compose composites"
kind: exec-plan
created_at: 2026-05-04T03:39:43Z
intention: "intention_01kqnh7tc1epwvtrf6fnt8jt3t"
master_plan: "docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md"
---

# Mermaid renderer for right-associative 3-deep compose composites

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change `Keiki.Render.Mermaid` exports two new renderers
that target the **right-associative 3-deep `compose`** shape —
i.e. transducers whose vertex type is

    Composite s1 (Composite s2 s3)

with three *distinct* `s1`, `s2`, `s3`. This is the shape produced
by `t1 \`compose\` (t2 \`compose\` t3)`, the natural form for an
"upstream aggregate ⨾ middle process ⨾ downstream aggregate"
pipeline modelled on the microtan production pattern. The
shipped renderers are:

1. `toMermaidCompose3` — flat 3-deep cross-product. Each vertex
   renders as a single Mermaid identifier
   `<show s1>_<show s2>_<show s3>`. Mirrors `toMermaidComposite`
   (EP-31) and `toMermaidFeedback1` (EP-33) in style; this is the
   minimum needed to produce a syntactically valid `stateDiagram-v2`
   block for any 3-deep compose.

2. `toMermaidCompose3Nested` — one-level nested subgraph. Each
   outer @s1@ vertex hosts a `state <s1> { … }` block listing every
   `<s1>_<s2>_<s3>` identifier under that outer; cross-cutting
   transitions remain at the top level using the same flat
   identifiers, so the renderer never relies on Mermaid's
   `Outer.Inner` dotted cross-block syntax (EP-32's lesson). For
   composites where the inner `(s2, s3)` cross-product is large
   enough that a single flat list scans poorly, this form groups
   by outer aggregate.

Both renderers return `Data.Text.Text` containing a
`stateDiagram-v2` block, suitable for pasting into a Markdown file
or rendering inline by GitHub / Notion / `mmdc`.

The first concrete consumer is **`Jitsurei.LoanWorkflow.loanWorkflow`**
— the 3-deep composite
`loanApplication \`compose\` (coreBankingSync \`compose\` loan)`,
vertex type `Composite LoanAppVertex (Composite SyncVertex LoanVertex)`.
Today the workflow has *no* checked-in Mermaid diagram because
`compositeLabel` calls plain `show` on each component, and `show`
on the inner `Composite SyncVertex LoanVertex` produces
`"Composite SyncIdle LoanInitial"` with whitespace (an invalid
Mermaid identifier — Mermaid identifiers must match
`[A-Za-z_][A-Za-z0-9_]*`). EP-34's M6 documented the gap and
deferred the fix; this plan closes it.

After implementation:

- `cabal build all` and `cabal test all --test-show-details=direct`
  remain green.
- `Keiki.Render.MermaidSpec` contains regression tests pinning
  the two new renderers' output for a small synthetic
  three-aggregate fixture.
- `Jitsurei.Render.MermaidLoanSpec` pins
  `toMermaidCompose3 loanWorkflow` and
  `toMermaidCompose3Nested loanWorkflow` against goldens.
- `docs/guide/diagrams/loan-workflow.mmd` and
  `docs/guide/diagrams/loan-workflow-nested.mmd` exist with the
  rendered blocks; both render cleanly in GitHub's Mermaid
  preview.
- `docs/guide/loan-application-tutorial.md` §10 ("Wiring it
  together with `compose`") embeds the rendered composite
  alongside the existing prose, replacing the current "no full
  diagram" caveat.
- EP-34's `docs/plans/34-…md` M6 Progress note and Outcomes →
  Follow-ups subsection are updated to record completion of the
  deferred renderer.
- MP-10's registry gains an EP-35 row marked Complete.

Observable acceptance: from the repository root,

    cabal test all --test-show-details=direct

prints two new green test groups (one each in
`keiki-test:Keiki.Render.MermaidSpec` and
`jitsurei-test:Jitsurei.Render.MermaidLoanSpec`); pasting the
contents of `docs/guide/diagrams/loan-workflow.mmd` into a
Markdown file rendered by GitHub produces a clean
`stateDiagram-v2` with 54 labelled vertices and the cross-context
transitions visible.


## Progress

Use a checklist to summarize granular steps. Every stopping point
must be documented here, even if it requires splitting a partially
completed task into two ("done" vs. "remaining").

- [x] M1 — `toMermaidCompose3` (flat 3-deep) + label helper +
      regression test in `keiki-test`. (2026-05-04)
  - [x] Add `compose3Label :: (Show s1, Show s2, Show s3) =>
        Composite s1 (Composite s2 s3) -> Text` to
        `src/Keiki/Render/Mermaid.hs`.
  - [x] Add `toMermaidCompose3 :: …` exported from the same
        module, defined as `renderTopology compose3Label`.
  - [x] Append both names to `Keiki.Render.Mermaid`'s export
        list.
  - [x] Extend `test/Keiki/Render/MermaidSpec.hs` with an
        `it` block pinning the flat 3-deep block for a small
        synthetic fixture (compose three two-vertex toys —
        2 × 2 × 2 = 8 composite vertices, fits on a screen).
  - [x] `cabal build all` and `cabal test keiki-test` green
        (146 examples, 0 failures).
- [x] M2 — `toMermaidCompose3Nested` (one-level nested) +
      label reuse + regression test in `keiki-test`. (2026-05-04)
  - [x] Add `toMermaidCompose3Nested :: …` exported from
        `src/Keiki/Render/Mermaid.hs`. Reuses `compose3Label`
        for inner identifiers and `vertexLabel` for outer
        `state … { … }` block names.
  - [x] Append the name to the module's export list.
  - [x] Extend `test/Keiki/Render/MermaidSpec.hs` with an
        `it` block pinning the nested 3-deep block for the
        same synthetic fixture used in M1.
  - [x] `cabal test keiki-test` green.
- [ ] M3 — Pin loan-workflow goldens; update tutorial; update
      EP-34's living document.
  - [ ] Extend `jitsurei/test/Jitsurei/Render/MermaidLoanSpec.hs`
        with two `it` blocks pinning
        `toMermaidCompose3 loanWorkflow` and
        `toMermaidCompose3Nested loanWorkflow` against
        canonical `Text` literals defined in the same module
        (mirroring the existing pattern for the single-aggregate
        renders).
  - [ ] Mirror the canonical blocks as
        `docs/guide/diagrams/loan-workflow.mmd` and
        `docs/guide/diagrams/loan-workflow-nested.mmd`.
  - [ ] Update the module-header comment of
        `MermaidLoanSpec.hs` to drop the "intentionally not
        pinned" caveat and reference EP-35.
  - [ ] Update
        `docs/plans/34-loan-application-worked-example-with-cross-context-process-and-tutorial.md`
        — M6 Progress sub-bullet flips from "intentionally not
        pinned" to "pinned in EP-35"; "Follow-ups" subsection
        in Outcomes & Retrospective marks the renderer item
        complete with a back-pointer to EP-35.
  - [ ] Update
        `docs/guide/loan-application-tutorial.md` §10 to embed
        the rendered nested composite via a fenced
        ```mermaid ``` block (or by referencing the `.mmd`
        file). The single-aggregate diagrams already in §10
        stay; the new composite caps the section.
  - [ ] `cabal test all` green.
- [ ] M4 — Update MP-10 registry; brief outcomes pass.
  - [ ] Append an EP-35 row to MP-10's Exec-Plan Registry table
        (status Complete) at
        `docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md`.
  - [ ] Update MP-10's Decomposition Strategy to mention EP-35
        as a Phase 3 entry (or extend Phase 2 — see Decision
        Log).
  - [ ] Fill in EP-35's Outcomes & Retrospective with the
        result vs. purpose comparison and any
        lessons.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights
discovered during implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Ship two renderers (flat + nested) in a single
  ExecPlan rather than splitting them like EP-31 / EP-32 did
  for the 2-deep case.
  Rationale: EP-31/EP-32 split because Phase 1 had not yet
  developed the "flat identifiers inside `state … { … }`
  blocks, no `Outer.Inner` dotted syntax" pattern; that pattern
  was an EP-32 *discovery*. By EP-35 the pattern is settled
  and the nested-for-readability variant is a routine
  extension of the flat one, no design discovery expected. A
  combined plan keeps the two renderers' regression tests
  next to one another, matches EP-33's bundling of
  `toMermaidAlternative` + `toMermaidFeedback1` under one EP,
  and avoids one round of plan-authoring overhead for what is
  ultimately a small renderer feature.
  Date: 2026-05-04

- Decision: Implement only **one-level** nested subgraphs in
  `toMermaidCompose3Nested` — outer @s1@ wraps a flat list of
  every `<s1>_<s2>_<s3>` identifier. Do not implement the
  two-level nest (`state s1 { state s2 { … } }`).
  Rationale: a two-level nest mirrors `compose`'s structural
  shape more faithfully but adds Mermaid renderer-compat risk
  (some Mermaid backends parse nested `state` blocks
  inconsistently — EP-32's Decision Log records this as the
  reason the flat-id-inside-state-block pattern was chosen
  over Mermaid's dotted-syntax cross-block reference). The
  one-level nest is sufficient for the loanWorkflow use case
  (6 outer × 9 inner — readable as 6 grouped lists). If a
  later use case demonstrates a need for tighter grouping, a
  follow-up EP can add a `toMermaidCompose3DeepNested` variant
  using the two-level form, with an explicit verification step
  against the user's chosen Mermaid backend.
  Date: 2026-05-04

- Decision: Extend (not replace) `feedback1Label`. Add
  `compose3Label` as a sibling rather than reworking
  `feedback1Label` to handle three independent types and
  retiring it.
  Rationale: `feedback1Label`'s type signature
  `(Show s1, Show s2) => Composite s1 (Composite s2 s1) -> Text`
  is a *load-bearing constraint* on the function's caller —
  the inner-inner `s1` matches the outer `s1` precisely
  because `feedback1`'s cascade structure
  (`compose t (compose f t)`) re-introduces the same
  transducer at the inner-inner layer. Generalising
  `feedback1Label` to three types would let callers
  accidentally pass non-feedback composites with no compile-
  time signal. A separate `compose3Label` keeps each renderer's
  type-level intent crisp.
  Date: 2026-05-04

- Decision: Place the synthetic fixture for the
  `keiki-test` regression specs *inline* in
  `test/Keiki/Render/MermaidSpec.hs` rather than under
  `test/Keiki/Render/Fixtures/`.
  Rationale: the existing `MermaidSpec.hs` already inlines a
  synthetic toy for the single-transducer case (per
  EP-34 M1's "synthetic-toy" pattern). Adding more inline
  fixtures keeps `keiki-test` self-contained (no `jitsurei`
  build-dep), matches the file's prevailing structure, and
  costs ~40 lines of trivial transducer definitions that
  doubly serve as documentation of the renderer's expected
  input shape.
  Date: 2026-05-04


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones
or at completion. Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This plan modifies a single library module
(`src/Keiki/Render/Mermaid.hs`), adds tests in two existing
spec files, adds two golden Mermaid files, and updates two prose
documents. A novice picking up this plan should read the files
named below before editing anything.

### What this plan is for

`Keiki.Render.Mermaid` ships per-shape renderers — one per
composition combinator — because each combinator's `Composite`-
vertex shape needs a tailored label-extraction function. The
existing renderers are listed in MP-10's registry at
`docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md`;
collectively they cover single transducers (EP-30), 2-deep
sequential composites in flat form (EP-31), 2-deep sequential
composites in nested-subgraph form (EP-32), and the special
shapes produced by `Keiki.Composition.alternative` and
`Keiki.Composition.feedback1` (EP-33).

EP-34 (`docs/plans/34-loan-application-worked-example-with-cross-context-process-and-tutorial.md`)
introduced the first 3-deep right-associative `compose` in the
repo: `Jitsurei.LoanWorkflow.loanWorkflow`, vertex type
`Composite LoanAppVertex (Composite SyncVertex LoanVertex)`.
EP-34's M6 Progress note records the gap precisely:

> Every shipped renderer (EP-30 `toMermaid`, EP-31
> `toMermaidComposite`, EP-32 `toMermaidCompositeNested`, EP-33
> `toMermaidAlternative` / `toMermaidFeedback1`) targets either a
> single transducer, a 2-deep `Composite s1 s2`, a parallel-arms
> `alternative`, or the feedback-typed 3-deep
> `Composite s1 (Composite s2 s1)`. The loanWorkflow shape
> `Composite LoanAppVertex (Composite SyncVertex LoanVertex)` is
> right-associative 3-deep with three *distinct* types and is
> not covered.

EP-35 closes that gap.

### Key files

- **`src/Keiki/Render/Mermaid.hs`** (~470 lines as of HEAD).
  The renderer module. Already exports five top-level
  renderers and four label helpers. Read the haddock at the top
  of the file once; the design conventions documented there
  (label format, `[*] -->` initial line, per-vertex `--> [*]`
  final lines, the shared `renderTopology` helper) all carry
  through to EP-35.

  Locations to know:

  - `toMermaid` at lines ~69–73 — single transducer, the
    template for "renderer that delegates to `renderTopology`".
  - `toMermaidComposite` at lines ~88–94 — flat 2-deep, also
    delegates to `renderTopology`.
  - `toMermaidCompositeNested` at lines ~127–171 — nested
    2-deep, hand-rolled around `compositeLabel`. The
    `outerBlock` helper at lines ~148–153 is the template
    EP-35's nested form mirrors.
  - `toMermaidAlternative` / `toMermaidAlternativeWith` at
    lines ~204–282 — parallel arms, separate state-block
    rendering. Read for cross-reference; EP-35 does not touch
    this shape.
  - `toMermaidFeedback1` at lines ~303–313 and `feedback1Label`
    at lines ~320–326 — the closest sibling to EP-35's new
    surfaces; `feedback1Label`'s destructuring pattern
    `(Composite a (Composite b c))` is identical to what
    `compose3Label` will use.
  - `renderTopology` at lines ~336–362 — the shared body that
    walks `[minBound .. maxBound]`, emits the `stateDiagram-v2`
    header, the initial-state line, one line per outgoing edge
    of every vertex, and a final-state line for every vertex
    where `isFinal t s`. EP-35's flat form delegates to it
    directly; the nested form pattern-matches `outerBlock` from
    `toMermaidCompositeNested`.
  - `vertexLabel`, `compositeLabel` at lines ~367–379 — the
    label primitives. EP-35's `compose3Label` is a sibling of
    `compositeLabel`.

- **`test/Keiki/Render/MermaidSpec.hs`** — `keiki-test`'s
  renderer regression suite. Already contains synthetic-toy
  tests for the single-transducer case (EP-34 M1 simplified
  this file to remove example-aggregate dependencies). EP-35
  appends two new `it` blocks plus one new synthetic fixture
  (a 3-deep compose of three two-vertex toys).

- **`jitsurei/src/Jitsurei/LoanWorkflow.hs`**. Defines
  `loanWorkflow` at line 117. The vertex type is at line 114;
  the variance caveat in the module haddock (around lines
  100–105) is unaffected by EP-35 — this plan adds visualisation,
  not behaviour.

- **`jitsurei/test/Jitsurei/Render/MermaidLoanSpec.hs`** — pins
  the single-aggregate Mermaid goldens for `loanApplication`,
  `loan`, and `coreBankingSync`. EP-35 extends it with two
  composite-render tests; the file's module-header comment is
  rewritten to drop the "deferred follow-up" caveat.

- **`docs/guide/diagrams/`** — short `.md` and `.mmd` files
  that ship rendered Mermaid blocks for tutorial embedding.
  EP-35 adds two `.mmd` files; the tutorial in
  `docs/guide/loan-application-tutorial.md` already follows the
  fenced-block embedding pattern.

- **`docs/plans/34-…md`** — EP-34's living document. EP-35's M3
  step updates the M6 sub-bullet and the "Follow-ups"
  subsection.

- **`docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md`**
  — the parent MasterPlan. EP-35's M4 step appends a row to its
  Exec-Plan Registry table and updates the Decomposition
  Strategy.

### Terms of art used in this plan

- **Right-associative 3-deep `compose`**. The expression
  `t1 \`compose\` (t2 \`compose\` t3)`. Vertex type
  `Composite s1 (Composite s2 s3)` — `s1` outermost, `(s2, s3)`
  cross-product nested inside. Distinct from the *left*-
  associative form `(t1 \`compose\` t2) \`compose\` t3` whose
  vertex type is `Composite (Composite s1 s2) s3`. EP-35 covers
  the right-associative form because that is the form the
  current codebase produces (`Jitsurei.LoanWorkflow`
  parenthesises right). Left-associative 3-deep is a separate
  shape that would need its own renderer; deferred as a follow-
  up if a use case appears.

- **Flat form**. Every composite vertex becomes a single Mermaid
  identifier produced by joining component shows with
  underscores: `<show s1>_<show s2>_<show s3>`. Edge lines
  reference these identifiers directly. The whole diagram is a
  flat list of transitions. Used by `toMermaidComposite` and
  `toMermaidFeedback1`; mirrored by `toMermaidCompose3`.

- **Nested-subgraph form**. The same flat identifiers (so
  cross-cutting transitions can reference any vertex without
  Mermaid's `Outer.Inner` dotted syntax), but each outer @s1@
  vertex hosts a `state <s1> { … }` block listing every
  identifier under that outer. Used by
  `toMermaidCompositeNested`; mirrored by
  `toMermaidCompose3Nested`.

- **Inner cross-product**. For the right-associative 3-deep
  shape, the `(s2, s3)` pairs whose enumeration walks
  `Composite s2 s3`'s `[minBound .. maxBound]`. Size is
  `|s2| * |s3|`. For loanWorkflow that is 3 × 3 = 9; the full
  composite has 6 × 9 = 54 vertices.

- **`renderTopology`**. The shared rendering helper at
  `src/Keiki/Render/Mermaid.hs:336`. Takes a label function
  `s -> Text` and a `SymTransducer (HsPred rs ci) rs s ci co`
  and returns the canonical `stateDiagram-v2` block (header +
  initial-state line + per-edge lines + per-final-state
  lines). Both EP-30's and EP-31's flat renderers delegate to
  it. EP-35's flat renderer delegates to it too.

### Why a new label function rather than recursing through `compositeLabel`

`compositeLabel (Composite a b) = show a <> "_" <> show b`. For a
3-deep `Composite s1 (Composite s2 s3)`, calling
`compositeLabel` recursively would mean reading the inner as
`b :: Composite s2 s3` and applying `compositeLabel` to it —
but the outer call to `compositeLabel` calls `show b`, not
`compositeLabel b`. Changing `compositeLabel` to detect the
nested-Composite case via `Show` would tie the label to the
default `Show` instance's textual format ("Composite SyncIdle
LoanInitial" with whitespace), which is exactly what the
existing label functions take pains to *avoid* by stripping the
`Composite` wrapper themselves. A dedicated `compose3Label`
that pattern-matches the 3-deep shape and joins three
underscore-separated `show` calls is the cleanest fix; it
parallels `feedback1Label`'s structure precisely.

### MP-10 phasing

MP-10's Decomposition Strategy describes Phase 1 (EP-30, EP-31)
and Phase 2 (EP-32, EP-33). EP-35 introduces a third phase:

- Phase 1 — Foundation (EP-30, EP-31). Single transducer +
  2-deep flat. Shipped 2026-05-03.
- Phase 2 — Coverage extensions (EP-32, EP-33). 2-deep nested
  + alternative/feedback1 special shapes. Shipped 2026-05-03.
- Phase 3 — Deeper composites (EP-35). 3-deep right-associative
  flat + nested. This plan.

The Phase 3 framing matches MP-10's existing phasing rationale:
each phase's choices depend on the previous phase's lessons.
EP-35's design copies the EP-32 lesson (flat IDs inside `state
… { … }` blocks; no dotted-syntax dependency) and the
EP-33 `feedback1Label` destructuring pattern.

### What this plan does *not* do

- It does not generalise `Keiki.Composition.compose` or
  introduce new combinators. The 3-deep shape this plan renders
  already exists in `Jitsurei.LoanWorkflow`; EP-35 only adds
  *visualisation* of that shape.
- It does not cover the *left*-associative 3-deep shape
  `Composite (Composite s1 s2) s3`. No live code in the repo
  produces it; if a future plan does, that plan can extend the
  pattern with a `composeL3Label` / `toMermaidComposeL3`
  variant.
- It does not change the variance caveat documented in
  `Jitsurei.LoanWorkflow`'s haddock: `compose` remains lockstep,
  the cross-context creation flow remains async, and EP-34's
  M5 spec continues to exercise each cross-context jump
  separately. EP-35 only adds a way to *draw* the type-level
  shape; the runtime semantics are unchanged.
- It does not change `Keiki.Composition.Composite`'s `Show`
  instance. The existing instance is used by other code paths
  (debugging, pretty-printing in test failures); reworking it
  to elide the constructor is out of scope and would risk
  breaking unrelated callers.


## Plan of Work

The work is organised as four milestones. M1 and M2 each ship a
new renderer with a `keiki-test` regression test against a small
synthetic fixture; both are independently verifiable and leave
the codebase in a working state. M3 lights up the loanWorkflow
goldens and updates the cross-references in EP-34 and the
tutorial. M4 updates the parent MasterPlan and finalises EP-35's
own retrospective.

### Milestone M1 — `toMermaidCompose3` (flat 3-deep)

Scope: implement the flat-cross-product renderer for the
right-associative 3-deep compose shape. By the end of M1, the
`Keiki.Render.Mermaid` module exports `compose3Label` and
`toMermaidCompose3`, and `keiki-test` contains a regression test
pinning the flat block for a synthetic fixture.

Sub-steps:

1. **Add `compose3Label`.** Place it in
   `src/Keiki/Render/Mermaid.hs` between `compositeLabel` (line
   ~377) and `feedback1Label` (line ~320). Signature:

       compose3Label
         :: (Show s1, Show s2, Show s3)
         => Composite s1 (Composite s2 s3) -> Text
       compose3Label (Composite a (Composite b c)) =
         T.pack (show a) <> T.pack "_"
           <> T.pack (show b) <> T.pack "_"
           <> T.pack (show c)

   Haddock copies `feedback1Label`'s pattern: link to
   Mermaid's identifier regex, note that the underscore join
   sidesteps the default `Composite` `Show` whitespace.

2. **Add `toMermaidCompose3`.** Define just below
   `toMermaidComposite`:

       toMermaidCompose3
         :: forall rs s1 s2 s3 ci co.
            ( Enum s1, Bounded s1, Show s1
            , Enum s2, Bounded s2, Show s2
            , Enum s3, Bounded s3, Show s3
            )
         => SymTransducer (HsPred rs ci) rs
              (Composite s1 (Composite s2 s3)) ci co
         -> Text
       toMermaidCompose3 = renderTopology compose3Label

   Haddock notes: applies to the right-associative 3-deep
   compose shape; cites EP-35; cross-references the
   `toMermaidCompose3Nested` variant added in M2.

3. **Update the module's export list.** Append
   `toMermaidCompose3` and `compose3Label` to
   `Keiki.Render.Mermaid`'s explicit export list. Order them
   to mirror the file order: after `toMermaidFeedback1` /
   `feedback1Label`.

4. **Author a synthetic 3-deep fixture in
   `test/Keiki/Render/MermaidSpec.hs`.** Add three two-vertex
   toy transducers (call them `toy1`, `toy2`, `toy3` with
   vertex types `T1A | T1B`, `T2A | T2B`, `T3A | T3B`) plus
   their `compose` chain `toy3deep = toy1 \`compose\` (toy2
   \`compose\` toy3)`. The fixture should fit on a single
   screen of source code (~30 lines). All three toys can share
   a single command type (e.g. `Tick`) so the `compose` chain
   type-checks without lifters; `compose`'s `mid` constraint
   is satisfied because `toy1`'s output equals `toy2`'s input
   equals `toy3`'s input. Place the fixture inline in
   `MermaidSpec.hs`, not in a separate file (per the Decision
   Log entry on inline fixtures).

5. **Pin the flat 3-deep block.** Add an `it` block to the
   spec: `toMermaidCompose3 toy3deep \`shouldBe\`
   toy3deepFlatCanonical`, with `toy3deepFlatCanonical` defined
   as a `Text` literal in the same file. The expected block
   contains the standard `stateDiagram-v2` header, an
   initial-state line, 8 per-vertex edge lines (each toy has
   one outgoing edge × the cross-product), and one final-state
   line for whichever vertex is final.

6. **Run `cabal build all` and `cabal test keiki-test`.** Both
   should succeed. The new spec block prints `[✔]` against the
   pinned canonical block.

Acceptance for M1: `cabal build all` succeeds; `cabal test
keiki-test --test-show-details=direct` shows the new
`toMermaidCompose3` `it` block green; the synthetic fixture is
checked in; `Keiki.Render.Mermaid` exports the two new names.


### Milestone M2 — `toMermaidCompose3Nested` (one-level nested)

Scope: implement the nested-subgraph renderer. By the end of M2,
`Keiki.Render.Mermaid` exports `toMermaidCompose3Nested`, and
`keiki-test` contains a second regression test pinning the
nested block for the same synthetic fixture from M1.

Sub-steps:

1. **Add `toMermaidCompose3Nested`.** Place it between
   `toMermaidCompositeNested` (line ~134) and
   `toMermaidAlternative` (line ~204). Signature:

       toMermaidCompose3Nested
         :: forall rs s1 s2 s3 ci co.
            ( Enum s1, Bounded s1, Show s1
            , Enum s2, Bounded s2, Show s2
            , Enum s3, Bounded s3, Show s3
            )
         => SymTransducer (HsPred rs ci) rs
              (Composite s1 (Composite s2 s3)) ci co
         -> Text

   Body: hand-rolled, mirroring `toMermaidCompositeNested`'s
   structure. Walk `outers = [minBound .. maxBound] :: [s1]`,
   `inners = [minBound .. maxBound] :: [Composite s2 s3]`,
   `composites = [minBound .. maxBound] :: [Composite s1
   (Composite s2 s3)]`. For each outer @o@, emit a `state
   <vertexLabel o> {` block containing one indented line per
   `Composite o i` with `i ∈ inners`, formatted via
   `compose3Label`. After the outer blocks, emit the cross-
   cutting edges (one line per `s ∈ composites, e ∈ edgesOut t
   s`) and the final-state lines, both using `compose3Label`.

2. **Update the module's export list.** Append
   `toMermaidCompose3Nested` after `toMermaidCompose3`.

3. **Pin the nested block.** Reuse the same synthetic fixture
   from M1. Add a second `it` block:
   `toMermaidCompose3Nested toy3deep \`shouldBe\`
   toy3deepNestedCanonical`. The expected block has the
   `stateDiagram-v2` header, the initial-state line, two
   `state T1A { … }` and `state T1B { … }` blocks each with
   four flat `T1A_T2A_T3A` / `T1A_T2A_T3B` / `T1A_T2B_T3A` /
   `T1A_T2B_T3B` lines, then the cross-cutting edges and
   final-state lines.

4. **Run `cabal test keiki-test`.** Both new specs (M1's flat
   and M2's nested) should be green.

Acceptance for M2: `cabal test keiki-test
--test-show-details=direct` shows both `toMermaidCompose3` and
`toMermaidCompose3Nested` `it` blocks green; the third synthetic
fixture stays untouched between M1 and M2 (one fixture, two
renderers).


### Milestone M3 — Loan-workflow goldens; tutorial; EP-34 cross-references

Scope: pin the loanWorkflow goldens for both renderers, mirror
them as `.mmd` files for the tutorial to embed, update the
tutorial section that currently has no full diagram, and update
EP-34's living document.

Sub-steps:

1. **Pin loanWorkflow goldens in
   `jitsurei/test/Jitsurei/Render/MermaidLoanSpec.hs`.** Add
   two `describe`/`it` blocks at the bottom of the existing
   `spec` definition:

       describe "toMermaidCompose3 loanWorkflow" $
         it "renders the 54-vertex flat block" $
           toMermaidCompose3 loanWorkflow `shouldBe`
             loanWorkflowFlatCanonical

       describe "toMermaidCompose3Nested loanWorkflow" $
         it "renders the 6-outer × 9-inner nested block" $
           toMermaidCompose3Nested loanWorkflow `shouldBe`
             loanWorkflowNestedCanonical

   Define the two `Text` literals at the bottom of the file
   alongside the existing single-aggregate canonicals. Use the
   `unlinesNoTrail` helper that already lives in the file.

   The flat literal contains 1 (header) + 1 (init) + 54
   composite-vertex outgoing-edge lines (some reach back to
   themselves on idempotent commands; the actual count depends
   on `loanWorkflow`'s edge enumeration — generate by running
   the renderer once at the REPL during implementation, then
   pin the result verbatim).

2. **Mirror the literals as `.mmd` files.** Create
   `docs/guide/diagrams/loan-workflow.mmd` (flat) and
   `docs/guide/diagrams/loan-workflow-nested.mmd` (nested) with
   the same content the spec pins. This mirrors the existing
   convention for the single-aggregate diagrams.

3. **Update `MermaidLoanSpec.hs`'s module-header comment.** The
   current haddock says:

       -- The 3-deep composite 'loanWorkflow' is intentionally not pinned:
       -- the keiki renderer's flat 'toMermaidComposite' produces a
       -- 6 × 3 × 3 = 54-vertex diagram whose composite identifiers
       -- contain literal whitespace from the inner 'Composite' Show
       -- instance ("Composite SyncIdle LoanInitial"), which most Mermaid
       -- backends reject. The single-aggregate diagrams are sufficient
       -- for the tutorial's pedagogical aims; a richer renderer for
       -- nested composites is a follow-up.

   Replace with prose noting that EP-35 closed the gap and
   pointing at `Keiki.Render.Mermaid.toMermaidCompose3` /
   `toMermaidCompose3Nested`.

4. **Update EP-34's living document.** In
   `docs/plans/34-loan-application-worked-example-with-cross-context-process-and-tutorial.md`:

   - The M6 sub-bullet that begins
     "`Jitsurei.Render.MermaidLoanSpec` pins single-aggregate
     renders" — append a sentence: "EP-35 (`docs/plans/35-…md`)
     subsequently pinned the composite via
     `toMermaidCompose3` and `toMermaidCompose3Nested`; the
     follow-up tracked in Outcomes & Retrospective is
     complete."
   - The "Follow-ups" subsection in Outcomes & Retrospective
     — strike through (or remove and note the completion of)
     the "3-deep compose renderer" bullet, with a back-pointer
     to EP-35.
   - Append a Revision Note dated today: "EP-35 shipped; M6's
     deferred follow-up is now closed; `loan-workflow.mmd`
     and `loan-workflow-nested.mmd` exist."

5. **Update `docs/guide/loan-application-tutorial.md` §10
   ("Wiring it together with `compose`").** Embed the nested
   composite via a fenced ` ```mermaid ` block (or a
   reference to `loan-workflow-nested.mmd`). The flat form is
   too large for the tutorial's flow — keep it as a `.mmd`
   pointer in the section's "if you want the full unflattened
   diagram, see …" note. Keep the existing prose; the new
   diagram caps the section.

6. **Run `cabal test all`.** Every previously-green spec stays
   green; the four new spec blocks (two in `keiki-test` from
   M1/M2, two in `jitsurei-test` from M3) are green.

Acceptance for M3: `cabal test all` is green; `git status`
shows the two new `.mmd` files as untracked (added to git in
the same commit as the spec change); the EP-34 living document
is updated; the tutorial embeds the rendered nested composite.


### Milestone M4 — Update MP-10 registry; finalise EP-35 retrospective

Scope: append EP-35 to MP-10's registry, document Phase 3 in
MP-10's Decomposition Strategy, and fill in EP-35's own
Outcomes & Retrospective.

Sub-steps:

1. **Append an EP-35 row to MP-10's Exec-Plan Registry.** In
   `docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md`,
   the Registry table lives around line 220. Add:

       | 5 | Mermaid renderer for right-associative 3-deep compose composites | docs/plans/35-mermaid-renderer-for-right-associative-3-deep-compose-composites.md | EP-30, EP-31, EP-32, EP-33 (soft) | EP-34 (motivating use case) | Complete |

   Update the External-dep glossary if needed (EP-30..EP-33 are
   already covered; EP-34 is a fresh entry — add a one-line
   description: "EP-34 is `docs/plans/34-…md`, which surfaced
   the 3-deep compose visualisation gap that motivates EP-35.").

2. **Update MP-10's Decomposition Strategy.** Add a Phase 3
   paragraph after Phase 2:

   > **Phase 3 — Deeper composites (added 2026-05-04 after
   > Phase 2 shipped):**
   >
   > 5. **EP-35 (3-deep right-associative compose renderer).**
   >    Phase 1+2 covered single, 2-deep, alternative, and the
   >    feedback-typed 3-deep shapes. EP-34's `loanWorkflow`
   >    introduced a *right-associative* 3-deep shape with three
   >    distinct types, which none of the existing renderers
   >    fits. EP-35 ships `toMermaidCompose3` (flat) and
   >    `toMermaidCompose3Nested` (one-level nested) plus the
   >    loanWorkflow goldens.

   Update the dependency-graph ASCII art to add an EP-35 node
   at the bottom (depending on EP-32 for the nested-form
   pattern and motivated by EP-34).

3. **Update MP-10's Progress checklist.** Mark the new EP-35
   row complete with today's date.

4. **Fill in EP-35's Outcomes & Retrospective.** Compare the
   final state to the Purpose section: confirm both renderers
   exist and are exported; confirm the loanWorkflow goldens
   are pinned and mirrored; confirm the tutorial embeds the
   nested diagram; confirm `cabal test all` is green; confirm
   EP-34's M6 follow-up is closed. Note any divergences (e.g.
   if the synthetic fixture changed during implementation, or
   if a Surprise was logged).

Acceptance for M4: MP-10's registry shows EP-35 Complete; the
Decomposition Strategy mentions Phase 3; EP-35's Outcomes &
Retrospective is filled in; `cabal test all` continues to pass.


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki/`.

### Build everything

    cabal build all

Expected: both `keiki` and `jitsurei` libraries rebuild
quickly; the only changed file in M1/M2 is
`src/Keiki/Render/Mermaid.hs`, so `keiki:lib` rebuilds and
everything downstream relinks.

### Run all test suites

    cabal test all --test-show-details=direct

Expected after M2: `keiki-test` adds two new green examples
(`toMermaidCompose3` flat, `toMermaidCompose3Nested` nested) for
the synthetic fixture. After M3: `jitsurei-test` adds two new
green examples for the loanWorkflow renders. After M4:
unchanged from M3 (no new test code).

### Generate the loanWorkflow goldens at the REPL

During M3 implementation, before pinning the canonical
`Text` literals, run:

    cabal repl jitsurei

then in GHCi:

    :m + Jitsurei.LoanWorkflow Keiki.Render.Mermaid Data.Text.IO
    Data.Text.IO.putStr (toMermaidCompose3 loanWorkflow)
    Data.Text.IO.putStr (toMermaidCompose3Nested loanWorkflow)

Copy each block verbatim into the canonical `Text` literal and
into the corresponding `.mmd` file.

### Visual verification

After M3, paste the contents of
`docs/guide/diagrams/loan-workflow-nested.mmd` into a Markdown
file and open it on GitHub (or in any Mermaid renderer). The
diagram should show six outer state-blocks
(`Intake`, `CollectingDocuments`, `UnderReview`, `Approved`,
`Declined`, `Withdrawn`) each containing nine inner identifiers,
plus the cross-cutting transitions between them. There should
be no whitespace inside any identifier and no rendering errors
in the Mermaid backend.

### Update EP-34 and the tutorial

Edits via the standard text-edit tooling. Re-read EP-34's
M6 Progress note and Outcomes → Follow-ups subsection after the
edit to confirm the cross-references resolve.


## Validation and Acceptance

Acceptance is a green `cabal test all` plus visual inspection of
the rendered loanWorkflow diagram. Concretely:

1. **Both renderers exist and are exported.** `cabal repl
   keiki` then `:browse Keiki.Render.Mermaid` lists
   `toMermaidCompose3`, `toMermaidCompose3Nested`, and
   `compose3Label` alongside the existing renderers.

2. **Type signatures are precise.** The two renderers compile
   without `-Wmissing-signatures` warnings; their signatures
   read exactly as specified in the Plan of Work.

3. **Synthetic-fixture regression.** `cabal test keiki-test
   --test-options="--match \"toMermaidCompose3\""` matches both
   spec blocks (flat and nested) and prints two green
   examples.

4. **LoanWorkflow goldens.** `cabal test jitsurei-test
   --test-options="--match \"loanWorkflow\""` matches both
   composite-render specs and prints two green examples; the
   pinned `Text` literals match the `.mmd` files byte-for-
   byte.

5. **Mermaid-backend validity.** Pasting either `.mmd` file
   into GitHub's preview produces a valid `stateDiagram-v2`
   render. No whitespace appears inside any vertex
   identifier.

6. **EP-34 living document is current.** The M6 sub-bullet in
   `docs/plans/34-…md` references EP-35; the "Follow-ups"
   subsection records the renderer item as complete; a
   2026-05-04 Revision Note is appended.

7. **Tutorial embeds the diagram.** §10 of
   `docs/guide/loan-application-tutorial.md` shows the
   rendered nested composite (or includes a fenced reference
   to the `.mmd` file) and the surrounding prose no longer
   reads as if no full diagram exists.

8. **MP-10 registry shows EP-35 Complete.** The table in
   `docs/masterplans/10-…md` lists EP-35 with status
   Complete; the Decomposition Strategy mentions Phase 3.

9. **No regression in pre-existing renderers.** `cabal test
   keiki-test --test-options="--match \"toMermaid\""` and
   `cabal test jitsurei-test --test-options="--match
   \"Mermaid\""` are both fully green; no existing canonical
   block has changed.


## Idempotence and Recovery

Every step is additive — new exports, new test blocks, new
golden files, two prose-doc updates. There are no destructive
operations.

If a milestone fails halfway:

- **Compile error in `Keiki.Render.Mermaid`.** Comment out the
  newly-added entry in the export list and re-run `cabal
  build all` to confirm the rest of the module still
  compiles. Restore the entry once the body type-checks.
  Common cause: missing `Show s3` constraint, or the
  `forall rs s1 s2 s3 ci co.` quantifier omitting one type
  variable.

- **Test failure on the synthetic fixture.** Run the spec in
  isolation with `cabal test keiki-test --test-options=
  "--match \"toMermaidCompose3\""`. The hspec output prints
  the expected vs. actual `Text` blocks side by side. Common
  cause: edge enumeration order mismatch (the `[minBound ..
  maxBound]` walk and `edgesOut` order are deterministic, so
  any mismatch points at a typo in the canonical literal).

- **Test failure on the loanWorkflow golden.** Re-generate the
  expected block via the REPL recipe in Concrete Steps and
  copy it verbatim. The renderer is pure and deterministic;
  if regeneration also produces a divergent block, the
  divergence is a real semantic change in `loanWorkflow` or
  in `Keiki.Render.Mermaid` and must be investigated.

- **Mermaid backend rejects the rendered block.** Identify
  the offending line in the rendered text. Most likely cause
  is a vertex identifier that did not get its `Composite`
  wrapper stripped (the Decision Log analysis covers the
  expected failure modes). Inspect the label-function output
  via `cabal repl` to localise.

- **Tutorial cross-reference breaks.** The tutorial embeds
  the nested diagram; if the embed format changes (e.g. via a
  later Markdown-renderer migration), the embed location is
  the only line that needs updating — the underlying `.mmd`
  file and spec golden are unchanged.

The git workflow follows the repository convention
(Conventional Commits, no feature branches by default per
`/Users/shinzui/.claude/CLAUDE.md`). Each milestone's commits
include the trailers:

    ExecPlan: docs/plans/35-mermaid-renderer-for-right-associative-3-deep-compose-composites.md
    Intention: intention_01kqnh7tc1epwvtrf6fnt8jt3t


## Interfaces and Dependencies

This plan adds two new exports to one existing module. No new
external library dependencies. No new packages. No flake
changes.

### After M1

- `src/Keiki/Render/Mermaid.hs` exports
  - `compose3Label :: (Show s1, Show s2, Show s3) =>
    Composite s1 (Composite s2 s3) -> Text`
  - `toMermaidCompose3 :: ( Enum s1, Bounded s1, Show s1
                         , Enum s2, Bounded s2, Show s2
                         , Enum s3, Bounded s3, Show s3
                         )
                      => SymTransducer (HsPred rs ci) rs
                           (Composite s1 (Composite s2 s3))
                           ci co
                      -> Text`
- `test/Keiki/Render/MermaidSpec.hs` defines a synthetic 3-deep
  fixture (three two-vertex toys composed right-associatively)
  and an `it` block pinning `toMermaidCompose3` against a
  canonical `Text`.

### After M2

- `src/Keiki/Render/Mermaid.hs` additionally exports
  - `toMermaidCompose3Nested :: <same signature as
    toMermaidCompose3>` — value differs (nested-subgraph
    layout); type is identical.
- `test/Keiki/Render/MermaidSpec.hs` adds a second `it` block
  pinning `toMermaidCompose3Nested` against a second canonical
  `Text` for the same fixture.

### After M3

- `jitsurei/test/Jitsurei/Render/MermaidLoanSpec.hs` adds two
  `describe`/`it` blocks pinning `toMermaidCompose3
  loanWorkflow` and `toMermaidCompose3Nested loanWorkflow`
  against `loanWorkflowFlatCanonical` and
  `loanWorkflowNestedCanonical` `Text` literals defined in the
  same file.
- `docs/guide/diagrams/loan-workflow.mmd` and
  `docs/guide/diagrams/loan-workflow-nested.mmd` exist and
  contain the same blocks as the canonical literals.
- `docs/plans/34-…md`'s M6 sub-bullet and Outcomes
  → Follow-ups subsection are updated; a 2026-05-04 Revision
  Note is appended.
- `docs/guide/loan-application-tutorial.md` §10 embeds the
  rendered nested composite.

### After M4

- `docs/masterplans/10-…md`'s Exec-Plan Registry has a fifth
  row for EP-35 marked Complete; the Decomposition Strategy
  has a Phase 3 paragraph; the dependency-graph ASCII art
  references EP-35.
- This plan's Outcomes & Retrospective section is filled in.

### External tools

- `cabal-install` ≥ 3.0 and GHC 9.12 (per `keiki.cabal`'s
  `tested-with` field).
- A Mermaid renderer for the visual-verification step (the
  GitHub preview, or `mmdc` from
  `@mermaid-js/mermaid-cli`). Not required for `cabal test
  all` itself.
