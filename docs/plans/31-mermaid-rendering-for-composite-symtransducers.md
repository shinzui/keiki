---
id: 31
slug: mermaid-rendering-for-composite-symtransducers
title: "Mermaid rendering for Composite SymTransducers"
kind: exec-plan
created_at: 2026-05-03T04:05:37Z
intention: "intention_01kqnh7tc1epwvtrf6fnt8jt3t"
master_plan: "docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md"
---

# Mermaid rendering for Composite SymTransducers

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this plan ships, the Mermaid renderer in `Keiki.Render.Mermaid` (added by
the sibling plan
`docs/plans/30-mermaid-renderer-for-single-symtransducer-canonical-example-diagrams.md`)
also handles **composite** transducers — the result of `Keiki.Composition.compose`
(`src/Keiki/Composition.hs`) over two `SymTransducer` values. A composite's
vertex type is `Composite s1 s2` (a strict pair newtype defined in the same
file), and its full edge set is the cross-product of the two underlying edge
sets specialised by the substitution algorithm. Naïvely rendering this with the
same `[minBound..maxBound]` enumeration the single-transducer renderer uses
produces a flat diagram of `|s1| * |s2|` vertices with `Composite a b` strings
as labels — readable for tiny pipelines (the test fixture `AlertSource ⨾
EmailDelivery` has only `2 * 2 = 4` composite vertices) but illegible for
realistic compositions (a `UserRegistration ⨾ EmailDelivery` would have
`5 * 2 = 10` vertices arranged in no particular layout).

This plan ships a second renderer that produces a **nested** Mermaid block
using `stateDiagram-v2`'s `state ... { ... }` subgraph syntax. The outer level
shows the `s1` (left-side) topology; each `s1` vertex contains a nested state
diagram showing the `s2` (right-side) topology that exists "inside" that
composite vertex. The result reads as "outer t state machine; for each outer
state, inner t state machine," which matches how a designer thinks about
composition.

Concretely, after this plan a contributor can:

1. In `ghci`, render the test fixture `AlertSource ⨾ EmailDelivery` (defined
   in `test/Keiki/CompositionSpec.hs` — the spec file is the source of truth
   for the fixture's shape):

       ghci> import Keiki.Render.Mermaid (toMermaidComposite)
       ghci> import qualified Data.Text.IO as TIO
       ghci> -- ... build the composite (see test/Keiki/CompositionSpec.hs:pipeline)
       ghci> TIO.putStrLn (toMermaidComposite pipeline)
       stateDiagram-v2
           [*] --> AlertQuiescent.EmailPending
           state AlertQuiescent {
               EmailPending --> EmailSentVertex : SendEmail / EmailSent
           }
           ...

   The exact emitted block is pinned in M3's regression test.

2. Open `docs/guide/diagrams/composite-alert-email.md` in a Markdown
   previewer and see the composite's two-level topology rendered.

3. Run `cabal test` and watch the new
   `Keiki.Render.Mermaid -> toMermaidComposite (composite SymTransducer)`
   regression test pass alongside the single-transducer test from EP-30.

The MasterPlan
`docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md` motivates
this: composite topologies are the harder rendering case (nested vs. cross-
product trade-off), and the MasterPlan splits them into a separate ExecPlan
specifically so the choice can be made with the single-transducer renderer
already shipped and observable.


## Progress

- [x] M0 — Verify EP-30 is complete: `Keiki.Render.Mermaid` exists and
      exports `toMermaid`/`vertexLabel`/`edgeInputName`/`edgeOutputName`/
      `edgeLabel`; `cabal test` passes; record the canonical
      `userReg` block from EP-30 in Surprises as a reference.
      *(2026-05-03: GHC 9.12.3, z3 4.16.0; `cabal build all` Up to date;
      `cabal test` 197 examples, 0 failures including the EP-30
      `Keiki.Render.Mermaid -> toMermaid (single SymTransducer)`
      describe block. EP-30 plan's Progress is fully checked. The
      canonical `userReg` block is mirrored in
      `test/Keiki/Render/MermaidSpec.hs:userRegCanonical` and
      `docs/guide/diagrams/user-registration.md`; both pin the same
      eight-line stateDiagram-v2 block.)*
- [x] M1 — Decide the composite rendering shape (nested subgraphs vs. flat
      cross-product); document the trade-off in Decision Log; if subgraphs,
      verify the chosen Mermaid block renders in GitHub's Markdown viewer
      with a hand-written sample before any code changes.
      *(2026-05-03: chose Shape A (flat cross-product) — see Decision
      Log entry of 2026-05-03 below for the trade-off analysis. The
      verification step the plan envisioned (push a Shape B sample to a
      gist and visually confirm) was not performable by the
      implementing agent; combined with the fixture having zero
      same-outer edges (which neutralises Shape B's claimed benefit),
      Shape A is the safer ship.)*
- [x] M2 — Implement `toMermaidComposite` (and the supporting helpers for
      the chosen shape) in `src/Keiki/Render/Mermaid.hs`; add to module
      export list; verify in `ghci` against the test pipeline.
      *(2026-05-03: shipped Shape A. Refactored the rendering core into
      a private `renderTopology :: (s -> Text) -> SymTransducer ... ->
      Text` helper that takes the vertex-label function as a
      parameter; `toMermaid = renderTopology vertexLabel` and
      `toMermaidComposite = renderTopology compositeLabel` share the
      walk, header, init / final / edge emission, and `edgeLabel`
      logic. Added `compositeLabel :: (Show s1, Show s2) =>
      Composite s1 s2 -> Text` (joins the component shows with `_`)
      to the module's exports alongside `toMermaidComposite`. ghci
      transcript on `Keiki.CompositionSpec.pipeline`:
      stateDiagram-v2
          [\*] --> AlertQuiescent_EmailPending
          AlertQuiescent_EmailPending --> AlertEmitted_EmailSentVertex : TriggerAlert / EmailSent
          AlertEmitted_EmailSentVertex --> [\*]
      .)*
- [ ] M3 — Render the composite diagram for `AlertSource ⨾ EmailDelivery`
      and check in to `docs/guide/diagrams/composite-alert-email.md`.
- [ ] M4 — Add a regression test in
      `test/Keiki/Render/MermaidSpec.hs` (the spec file from EP-30, now
      extended) pinning the canonical composite output for the
      `AlertSource ⨾ EmailDelivery` pipeline; `cabal test` passes.


## Surprises & Discoveries

- 2026-05-03 — M0 baseline. GHC 9.12.3, z3 4.16.0. `cabal build all`
  is "Up to date"; `cabal test` reports `197 examples, 0 failures`
  in 0.32 s. EP-30's `Keiki.Render.Mermaid` exports
  `toMermaid`/`vertexLabel`/`edgeInputName`/`edgeOutputName`/`edgeLabel`
  (verified by `grep`); EP-30's plan file shows all four milestones
  checked. Safe to add `toMermaidComposite` on top.

- 2026-05-03 — Refactor decision (M2 implementation): the plan's
  Shape A sketch duplicates ~10 lines of `toMermaid`'s body verbatim,
  swapping only the vertex-label function. Extracted the shared core
  into a private `renderTopology label t = …` helper that takes the
  label function as a parameter; `toMermaid = renderTopology
  vertexLabel`, `toMermaidComposite = renderTopology compositeLabel`.
  Result: zero duplication; both public entry points stay the same
  signature; `edgeLabel` still has exactly one call site
  (`renderTopology`). Trade-off: the module gains one private helper.
  Cheap, local, reversible.

- 2026-05-03 — ghci validation of `toMermaidComposite` against
  `Keiki.CompositionSpec.pipeline` produced:

      stateDiagram-v2
          [*] --> AlertQuiescent_EmailPending
          AlertQuiescent_EmailPending --> AlertEmitted_EmailSentVertex : TriggerAlert / EmailSent
          AlertEmitted_EmailSentVertex --> [*]

  Three lines (init / one edge / final), matching the M0 manual
  edge-set analysis: of the 4 composite vertices, only
  `Composite AlertQuiescent EmailPending` has an outgoing edge, and
  only `Composite AlertEmitted EmailSentVertex` is final; the other
  two vertices have no edges and aren't final, so they don't appear
  in the diagram (consistent with `toMermaid`'s behaviour for
  unreachable / dead-end vertices).

- 2026-05-03 — Confirmed the test fixture's edge count. `AlertVertex`
  has one outgoing edge from `AlertQuiescent` (on `TriggerAlert`,
  emitting `SendEmailEvent`); `EmailVertex` has one outgoing edge
  from `EmailPending` (on `SendEmail`, emitting `EmailSent`). The
  composite cross-product produces exactly **one** non-ε edge from
  `Composite AlertQuiescent EmailPending` to
  `Composite AlertEmitted EmailSentVertex` on
  `TriggerAlert / EmailSent`. The other three composite vertices
  have zero outgoing edges. The composite is final at
  `Composite AlertEmitted EmailSentVertex` (both component
  `isFinal` predicates fire). Empirical edge enumeration via ghci
  is deferred to M2's validation step (the renderer itself is the
  most direct way to inspect `edgesOut pipeline`).


## Decision Log

- Decision: This plan hard-depends on EP-30
  (`docs/plans/30-mermaid-renderer-for-single-symtransducer-canonical-example-diagrams.md`)
  being complete before any work begins.
  Rationale: EP-30 owns the `Keiki.Render.Mermaid` module surface, the
  `(Enum, Bounded, Show)` constraint discipline on `s`, and the helper
  functions (`vertexLabel`, `edgeInputName`, `edgeOutputName`, `edgeLabel`)
  this plan extends. Trying to design EP-31 in isolation would either
  duplicate that work or produce an incoherent module shape.
  Date: 2026-05-03

- Decision: The composite shape choice (nested subgraphs vs. flat cross-
  product) is deferred to M1, not made up front.
  Rationale: the MasterPlan deliberately splits the composite EP off from the
  single-transducer EP so this choice can be made with EP-30's renderer
  output already observable. M1 spends a hand-written-Mermaid-sample step
  validating that GitHub's Markdown renderer actually handles nested
  subgraphs (Mermaid 8.7+ feature) before committing implementation to it.
  Date: 2026-05-03

- Decision: M1 picks **Shape A (flat cross-product)** — composite
  vertex labels are `<show s1>_<show s2>`; the renderer body is a
  near-mirror of EP-30's `toMermaid` with a custom label function.
  Rationale: three reasons stack.
  (1) The verification step the plan envisaged for Shape B (push a
  hand-written nested-subgraph sample to a GitHub gist and visually
  confirm GitHub renders the Mermaid 8.7+ `Outer.Inner` dotted syntax
  for cross-outer transitions) cannot be performed by the
  implementing agent — and proceeding without empirical confirmation
  is the failure mode the plan's verification step exists to prevent.
  (2) The chosen test fixture (`AlertSource ⨾ EmailDelivery`) has
  exactly one composite edge, and that edge is cross-outer (it
  changes both `AlertVertex` and `EmailVertex`). Zero same-outer
  edges means both Shape B outer blocks would be empty
  (`state AlertQuiescent { }`, `state AlertEmitted { }`); the diagram
  reduces to top-level dotted transitions between inner-state
  references inside empty outer blocks, which is exactly the
  rendering edge case Shape B's verification step was designed to
  catch.
  (3) Shape A is structurally identical to `toMermaid` (same vertex
  walk, same edge / final / initial emission); only the label
  function differs (`<show a>_<show b>` instead of `show . id`).
  Cognitive load for future maintainers is minimal, the
  reuse-of-known-good-code reduces bug surface, and the
  flat layout reads cleanly for the fixture's 1-edge graph.
  Trade-off accepted: Shape A scales poorly for compositions over
  larger sub-aggregates (e.g. `UserRegistration ⨾ EmailDelivery`
  would give 10 flat vertices). The plan's "Out of scope" section
  already excludes those compositions from this EP; a follow-up plan
  can introduce Shape B once larger composites are in scope and
  someone can perform the Mermaid-rendering verification.
  Date: 2026-05-03


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

This plan extends the work delivered in
`docs/plans/30-mermaid-renderer-for-single-symtransducer-canonical-example-diagrams.md`.
That plan must be complete (its Outcomes & Retrospective filled, its Progress
fully checked) before this plan begins.

**`Composite`.** Defined in `src/Keiki/Composition.hs`:

    data Composite s1 s2 = Composite !s1 !s2
      deriving (Eq, Show)

`(Enum, Bounded)` instances are defined in the same file (column-major
enumeration of the cross-product). So
`(Enum (Composite s1 s2), Bounded (Composite s1 s2), Show (Composite s1 s2))`
holds whenever `(Enum s1, Bounded s1, Show s1, Enum s2, Bounded s2, Show s2)`.

**`compose`.** Same file. Signature (simplified for the plan):

    compose
      :: SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 mid
      -> SymTransducer (HsPred rs2 mid) rs2 s2 mid co
      -> SymTransducer (HsPred (Append rs1 rs2) ci1)
                       (Append rs1 rs2)
                       (Composite s1 s2)
                       ci1
                       co

The composite's edge set is the cross-product (per the case analysis at
`src/Keiki/Composition.hs:687`) modulo substitution: for each non-ε edge of
t1 from `s1`, paired with each edge of t2 from `s2`, one composite edge whose
guard / update / output are t2's substituted against t1's edge output and
conjoined with t1's lifted guard. ε-edges of t1 produce one composite edge
per `s2` that advances `s1` and leaves `s2` unchanged.

**Test fixture.** `test/Keiki/CompositionSpec.hs` defines the canonical
composite test fixture: `pipeline = compose alertSource emailDelivery`.
`AlertVertex = AlertQuiescent | AlertEmitted` and
`EmailVertex = EmailPending | EmailSentVertex` are both `(Eq, Show, Enum,
Bounded)`. The composite has `2 * 2 = 4` vertices.

The fixture's edge set (from a manual case analysis of `composeEdge` over
the two underlying edge sets):

- `AlertQuiescent` has one outgoing edge (on `TriggerAlert`) producing a
  non-ε output (`SendEmailEvent`); `AlertEmitted` has none.
- `EmailPending` has one outgoing edge (on `SendEmail`) producing a non-ε
  output (`EmailSentEvent`); `EmailSentVertex` has none.
- Composite from `Composite AlertQuiescent EmailPending`: one edge
  (cross-product of t1's `AlertQuiescent → AlertEmitted` with t2's
  `EmailPending → EmailSentVertex`) advancing to
  `Composite AlertEmitted EmailSentVertex`.
- Composite from `Composite AlertQuiescent EmailSentVertex`: zero
  outgoing edges (t2 has no outgoing edges from `EmailSentVertex`, so the
  cross-product is empty; t1's edge is non-ε so no ε-fallback applies).
- Composite from `Composite AlertEmitted *`: zero outgoing edges (t1 has
  none).

So the composite has exactly **one** edge from one composite vertex
(`Composite AlertQuiescent EmailPending` →
`Composite AlertEmitted EmailSentVertex` on `TriggerAlert / EmailSent`).
The other three composite vertices have zero outgoing edges. The composite
is final at `Composite AlertEmitted EmailSentVertex` (both component
`isFinal` predicates are satisfied).

This is the small fixture EP-31 renders. The implementer must verify the
edge-count claim by stepping through `composeEdge` in `ghci` (or by
inspecting the edge list directly via `length . edgesOut pipeline`) before
pinning M4's regression test.

**Mermaid `stateDiagram-v2` nested-state syntax.** Mermaid 8.7+ supports
nested states via:

    stateDiagram-v2
        state OuterA {
            InnerA1 --> InnerA2 : edge
        }
        state OuterB {
            InnerB1 --> InnerB2 : edge
        }
        OuterA --> OuterB : transition between outer states

Identifiers inside a nested block are scoped: two outer blocks may both
contain a state called `Foo` and Mermaid keeps them distinct. Transitions
between *outer* states are written at the top level using the outer state
names. Transitions that cross between an inner state of one outer and an
inner state of another outer are written using the dotted path syntax
`OuterA.InnerA1 --> OuterB.InnerB1`.

GitHub's Markdown viewer renders Mermaid via a server-side library that
tracks Mermaid's stable releases; nested states have been stable since
Mermaid 8.7 (2020), so GitHub renders them. M1 verifies this with a
hand-written sample before committing to the syntax.

**Naming policy for composite vertex labels.** Mermaid identifiers must
match `[A-Za-z_][A-Za-z0-9_]*`. `show (Composite a b)` produces
`"Composite AlertQuiescent EmailPending"` — the spaces are not legal
Mermaid identifiers. The composite renderer must therefore avoid
`show . id` for composite labels:

- Shape A (flat cross-product): emit identifiers as
  `<show s1>_<show s2>` (underscore-joined, e.g.
  `AlertQuiescent_EmailPending`).
- Shape B (nested subgraphs): outer label is `<show s1>` and inner label
  is `<show s2>` (no joining); cross-cutting transitions use Mermaid's
  dotted syntax.


## Plan of Work

### M0 — Verify EP-30 is complete

Inspect the working tree to confirm EP-30 is fully landed:

- `src/Keiki/Render/Mermaid.hs` exists and exports `toMermaid`,
  `vertexLabel`, `edgeInputName`, `edgeOutputName`, `edgeLabel`.
- `cabal test` passes; the
  `Keiki.Render.Mermaid -> toMermaid (single SymTransducer)` describe
  block is present and green.
- `docs/plans/30-...md`'s Progress shows all four milestones checked and
  the Outcomes & Retrospective is filled.

If EP-30 is incomplete, stop and report which milestones are unchecked;
EP-31 cannot proceed.

Acceptance: a console session confirms all four conditions above.

### M1 — Pick the composite rendering shape

Two candidate shapes:

**Shape A — flat cross-product.** Reuse the single-transducer renderer:
identifiers are `<show s1>_<show s2>`; one transition per composite edge.
Pros: trivial implementation (a one-line variant of `toMermaid` with a
custom label function). Cons: scales poorly — `|s1| * |s2|` vertices in a
flat layout produce visually unstructured diagrams for any composite over
non-trivial sub-aggregates.

**Shape B — nested subgraphs.** Outer level shows `s1` topology with one
`state X { ... }` block per `s1` vertex; inner blocks show `s2` topology
"local to" that outer vertex. Cross-cutting transitions (composite edges
that change both `s1` and `s2`) use Mermaid's `OuterA.InnerA --> OuterB.InnerB`
dotted syntax. Pros: matches the mental model of composition; scales to
larger compositions. Cons: the inner topology is the *same* `s2` machine
in every outer block (the substitution affects guards, not topology), so
the diagram is partly redundant; nested-state syntax is Mermaid 8.7+ —
verify GitHub renders it.

This plan picks **Shape B (nested subgraphs)** with the following
caveats, but only after the verification step below.

Verification step (do this first, before any code edits):

1. Hand-write a small Mermaid sample in a scratch Markdown file
   (`/tmp/mermaid-test.md` or any throwaway location):

       ```mermaid
       stateDiagram-v2
           [*] --> Outer1
           state Outer1 {
               [*] --> InnerA
               InnerA --> InnerB : evt
           }
           state Outer2 {
               InnerC --> InnerD : evt2
           }
           Outer1.InnerB --> Outer2.InnerC : cross
       ```

2. Push the file to a GitHub gist or open it in a Mermaid-capable
   previewer. Confirm the nested boxes render with the cross-cutting
   transition shown as a labelled arrow between the inner states of the
   two outer boxes.

3. If GitHub renders Shape B correctly, proceed with Shape B. Record the
   verification outcome in Surprises & Discoveries with the URL or
   screenshot.

4. If GitHub does *not* render Shape B (for example, the cross-cutting
   transition is dropped or rendered as a bare line), fall back to
   Shape A (flat cross-product) and update the Decision Log + this
   milestone's plan to record the change before continuing.

Acceptance: the chosen shape is recorded in the Decision Log with
verification evidence; the verification scratch file is removed (it is
not part of the deliverable).

### M2 — Implement `toMermaidComposite`

The exact implementation depends on M1's chosen shape. Two
implementations:

**If Shape A (flat cross-product):**

Add to `src/Keiki/Render/Mermaid.hs`:

    toMermaidComposite
      :: ( Enum s1, Bounded s1, Show s1
         , Enum s2, Bounded s2, Show s2
         )
      => SymTransducer (HsPred rs ci) rs (Composite s1 s2) ci co
      -> Text
    toMermaidComposite t =
      let label (Composite a b) = T.pack (show a) <> T.pack "_" <> T.pack (show b)
          vertices = [minBound .. maxBound]
          header   = T.pack "stateDiagram-v2"
          ind      = T.pack "    "
          initLine = ind <> T.pack "[*] --> " <> label (initial t)
          edgeLines =
            [ ind <> label s <> T.pack " --> "
                  <> label (target e) <> T.pack " : " <> edgeLabel e
            | s <- vertices
            , e <- edgesOut t s
            ]
          finalLines =
            [ ind <> label s <> T.pack " --> [*]"
            | s <- vertices, isFinal t s
            ]
      in T.intercalate (T.pack "\n")
           (header : initLine : edgeLines ++ finalLines)

This is structurally identical to `toMermaid` but with a custom
`Composite`-aware label function. Add `Composite (..)` to the imports from
`Keiki.Composition`. Add `toMermaidComposite` to the module export list.

**If Shape B (nested subgraphs):**

Sketch:

    toMermaidComposite
      :: ( Enum s1, Bounded s1, Show s1
         , Enum s2, Bounded s2, Show s2
         )
      => SymTransducer (HsPred rs ci) rs (Composite s1 s2) ci co
      -> Text

The body partitions every composite edge by whether it stays inside one
outer vertex (`o' == o`) or crosses outer vertices (`o' /= o`). Edges
inside an outer vertex `o` go inside the corresponding
`state <show o> { ... }` block, written as
`<show i> --> <show i'> : <edgeLabel e>`. Cross-outer edges go at the top
level with dotted syntax: `<show o>.<show i> --> <show o'>.<show i'> :
<edgeLabel e>`.

Implementer notes for Shape B:

- The walk is `[ (o, i, e) | s@(Composite o i) <- [minBound..maxBound],
  e <- edgesOut t s ]`. Pattern-match `target e` to extract `(o', i')`
  and decide same-outer vs cross-outer.
- Outer vertices that have *no* outgoing edges still need an empty
  `state <o> { }` block — without it, the cross-outer arrow's
  `<o>.<i>` reference resolves against an undeclared state, which
  Mermaid renders as a stray top-level node. The fixture has three
  outer-vertex pairs with no outgoing edges; they all need empty
  blocks.
- The `isFinal` markers go at the top level using dotted syntax
  (`<o>.<i> --> [*]`), because Mermaid's `[*]` is at the outer level.
- The `initial` marker also goes at the top level using dotted syntax
  (`[*] --> <o>.<i>`).

In either shape, run the same in-`ghci` validation pipeline as EP-30's
M2 (start `cabal repl`, build the test pipeline value by hand, call
`toMermaidComposite`, observe output). Pin the rendered output as the
canonical block for M3 and M4.

Acceptance: `cabal build all` succeeds; the ghci transcript shows a
parseable Mermaid block whose structure matches the chosen shape.

### M3 — Render the composite diagram

Create `docs/guide/diagrams/composite-alert-email.md` containing:

    # AlertSource ⨾ EmailDelivery composite topology

    Rendered by `Keiki.Render.Mermaid.toMermaidComposite` over the
    `pipeline` value defined in `test/Keiki/CompositionSpec.hs`. Refresh
    by running:

        cabal repl  # then build the pipeline value and call toMermaidComposite

    ```mermaid
    stateDiagram-v2
        ...
    ```

The exact rendered block is M2's output. The `pipeline` value is in the
test file rather than the library, so the regeneration recipe must
either (a) point readers at the test file and ask them to copy the
fixture into ghci, or (b) lift the fixture into a small example module
under `src/Keiki/Examples/`. Option (a) is simpler and matches v1 scope.

Acceptance: the file exists and renders correctly in a Mermaid
previewer.

### M4 — Regression test for the composite

Extend `test/Keiki/Render/MermaidSpec.hs` (the file added by EP-30) with
a second describe block:

    describe "toMermaidComposite (composite SymTransducer)" $ do
      it "renders the AlertSource ⨾ EmailDelivery pipeline" $
        toMermaidComposite (compose alertSource emailDelivery)
          `shouldBe` ...

The fixture (`alertSource`) lives in `test/Keiki/CompositionSpec.hs` and
is currently un-exported from that module. Two options:

**Option 1 — re-import the fixture from the spec module.** Mark
`alertSource` as exported from `Keiki.CompositionSpec`. Drawback:
pollutes the spec module's API.

**Option 2 — duplicate the fixture in a dedicated test fixture module.**
Cleanest for test isolation; the fixture is small (~20 lines) and the
spec already imports `Keiki.Examples.EmailDelivery` for `emailDelivery`.
Drawback: duplication, but the duplication is in tests only.

This plan picks **Option 2** for test isolation. Add the `alertSource`
fixture (the `AlertVertex` type, `AlertCmd`, the TH splices, and the
`alertSource` value) to a new helper module
`test/Keiki/Render/MermaidCompositeFixture.hs` so the duplication is
quarantined to a fixture module, then import it from `MermaidSpec.hs`.

Wire the new module into `keiki.cabal`'s
`test-suite keiki-test.other-modules` and run `cabal test`. The describe
block must appear and pass.

Acceptance: `cabal test` exits 0 and the new describe block is green.


## Concrete Steps

All commands run from the repo root.

M0:

    cabal build all
    cabal test
    grep -c "toMermaid" src/Keiki/Render/Mermaid.hs
    head -100 docs/plans/30-mermaid-renderer-for-single-symtransducer-canonical-example-diagrams.md

M1:

    # Hand-write a Mermaid sample, push to GitHub gist, observe rendering.
    # Update Decision Log with the chosen shape.

M2:

    # Edit src/Keiki/Render/Mermaid.hs to add toMermaidComposite.
    cabal build all
    cabal repl
    ghci> -- ... build the pipeline by hand from CompositionSpec's fixtures
    ghci> import qualified Data.Text.IO as TIO
    ghci> TIO.putStrLn (toMermaidComposite pipeline)

M3:

    # Edit docs/guide/diagrams/composite-alert-email.md (new file).

M4:

    # Edit test/Keiki/Render/MermaidCompositeFixture.hs (new file)
    # Edit test/Keiki/Render/MermaidSpec.hs to add the composite describe block.
    # Edit keiki.cabal to register the new fixture module.
    cabal test


## Validation and Acceptance

The plan succeeds when all of the following hold:

1. `cabal build all` produces no warnings.
2. `cabal test` passes; the new describe block
   `Keiki.Render.Mermaid -> toMermaidComposite (composite SymTransducer)`
   is present and green.
3. `Keiki.Render.Mermaid` exports `toMermaidComposite`.
4. `docs/guide/diagrams/composite-alert-email.md` exists and renders
   correctly in a Mermaid-capable previewer.
5. The rendered output for the test pipeline matches the canonical block
   pinned in M4.


## Idempotence and Recovery

All steps are idempotent. If M2's chosen shape proves problematic during
implementation (e.g. nested syntax doesn't render the cross-cutting
transition correctly in GitHub), fall back to Shape A by swapping
`toMermaidComposite`'s body, updating the Decision Log, and re-running
M3 + M4 with the flat output.

If M4's fixture module duplicates code from `Keiki.CompositionSpec` and
the two drift, treat the spec's `alertSource` definition as the source of
truth and re-sync the fixture module.

There are no destructive operations.


## Interfaces and Dependencies

**Module surface change:** `src/Keiki/Render/Mermaid.hs` gains:

    toMermaidComposite
      :: ( Enum s1, Bounded s1, Show s1
         , Enum s2, Bounded s2, Show s2
         )
      => SymTransducer (HsPred rs ci) rs (Composite s1 s2) ci co
      -> Text

Plus any internal helpers that fall out of M1's chosen shape (e.g.
`partitionEdges`, `renderOuter`).

**New imports** in `Keiki.Render.Mermaid`:

    import Keiki.Composition (Composite (..))

**Cabal changes:**

- `library.exposed-modules` — no change (the module is already exposed
  by EP-30; only its API grows).
- `test-suite keiki-test.other-modules` += `Keiki.Render.MermaidCompositeFixture`.
- No new `build-depends`.

**Hard dependency:** EP-30
(`docs/plans/30-mermaid-renderer-for-single-symtransducer-canonical-example-diagrams.md`)
must be complete. The MasterPlan's registry tracks this.

**Soft dependency:** EP-11 under MP-4
(`docs/plans/4-composition-combinators-on-symtransducer.md`) — already
shipped; defines `Composite`, `compose`, and the test fixture this plan
renders.

**Out of scope:**

- Composites built with `alternative` (`Keiki.Composition.alternative`)
  or `feedback1` (`Keiki.Composition.feedback1`). They also produce
  `Composite s1 s2` vertices, so `toMermaidComposite` will *render*
  them, but the visual structure may be misleading (e.g. `alternative`'s
  parallel arms are not the same nested-sequential mental model).
  A follow-up plan can introduce shape-specialised renderers if demand
  emerges.
- Diagrams under `docs/guide/diagrams/` for composites of `userReg`,
  `orderCart`, etc. — only the `AlertSource ⨾ EmailDelivery` test
  fixture is rendered. The single-transducer diagrams from EP-30 cover
  the per-aggregate visualisation need; composites are added on demand.
