---
id: 33
slug: shape-aware-mermaid-renderers-for-alternative-and-feedback1-composites
title: "Shape-aware Mermaid renderers for alternative and feedback1 composites"
kind: exec-plan
created_at: 2026-05-03T15:59:16Z
intention: "intention_01kqnh7tc1epwvtrf6fnt8jt3t"
master_plan: "docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md"
---

# Shape-aware Mermaid renderers for alternative and feedback1 composites

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this plan ships, the Mermaid renderer in `Keiki.Render.Mermaid`
gains two new entry points whose layouts match the *visual semantics*
of the two composition combinators they target:

- `toMermaidAlternative t1 t2` — for composites built with
  `Keiki.Composition.alternative`. Renders the two arms as
  side-by-side parallel state machines (each in its own `state … {
  … }` block), reflecting the parallel-arm semantics where each
  Either-tagged input advances exactly one arm and leaves the other
  untouched.
- `toMermaidFeedback1 t f` — for composites built with
  `Keiki.Composition.feedback1`. Renders the resulting `Composite s1
  (Composite s2 s1)`-vertexed transducer as a 3-deep flat
  cross-product diagram (vertex labels `<show s1>_<show s2>_<show s1>`),
  generalising EP-31's flat-cross-product approach to three
  components.

The user-visible benefit: a designer reading the diagram of an
`alternative emailDelivery pinger` composition sees two independent
state machines side by side — exactly what the combinator's
documentation says happens at runtime — rather than the cross-product
of their vertex spaces. A designer reading a `feedback1 toggleAgg
togglePolicy` cascade sees the three-deep vertex space laid out flat,
with edges showing how a single external command advances all three
components in one step.

EP-31 explicitly defers this work in its Outcomes & Retrospective:
"Composite-renderer variants for `alternative` and `feedback1` shapes
(both produce `Composite s1 s2` but the sequential-composition mental
model doesn't apply)." The MasterPlan
`docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md`
also calls these out as deferred follow-ups.

Concretely, after this plan a contributor can:

1. In `ghci`, render the `alternative emailDelivery pinger` test
   fixture (defined in `test/Keiki/CompositionAlternativeSpec.hs`):

       cabal repl keiki-test --repl-no-load
       ghci> :load Keiki.CompositionAlternativeSpec
       ghci> import Keiki.Render.Mermaid (toMermaidAlternative)
       ghci> import Keiki.Examples.EmailDelivery (emailDelivery)
       ghci> import qualified Data.Text.IO as TIO
       ghci> TIO.putStrLn (toMermaidAlternative emailDelivery Keiki.CompositionAlternativeSpec.pinger)

   The exact emitted block is pinned in M6's regression test.

2. In `ghci`, render the `feedback1 toggleAgg togglePolicy` cascade
   (`test/Keiki/CompositionFeedback1Spec.hs`):

       cabal repl keiki-test --repl-no-load
       ghci> :load Keiki.CompositionFeedback1Spec
       ghci> import Keiki.Render.Mermaid (toMermaidFeedback1)
       ghci> import qualified Data.Text.IO as TIO
       ghci> TIO.putStrLn (toMermaidFeedback1 Keiki.CompositionFeedback1Spec.toggleAgg
                                              Keiki.CompositionFeedback1Spec.togglePolicy)

3. Open `docs/guide/diagrams/composite-email-pinger-alternative.md`
   and `docs/guide/diagrams/composite-toggle-feedback1.md` in any
   Mermaid-aware previewer and see the topologies rendered
   appropriately for their shapes.

4. Run `cabal test` and watch two new regression tests pass alongside
   the existing tests from EP-30 / EP-31.

The MasterPlan's Outcomes section (the "Shipped (2026-05-03)" entry)
records that the renderer module already factored
`renderTopology :: (Enum s, Bounded s) => (s -> Text) -> SymTransducer
… -> Text` as a private helper during EP-31. The new functions in
this plan will reuse it for `toMermaidFeedback1` (whose layout is
just a flat 3-deep cross-product, parametrised over a 3-tuple label
function); `toMermaidAlternative` does NOT reuse it because its
layout is fundamentally different — independent rendering of t1 and
t2 with parallel-arm wrapping.


## Progress

- [ ] M0 — Verify prerequisites: EP-30, EP-31, and the underlying
      `alternative` and `feedback1` combinators (EP-25, EP-26 under
      MP-8) are all complete; `cabal build all` and `cabal test`
      pass; baseline test count recorded (expected: 198 from EP-31's
      Outcomes; or 199 if EP-32 has already shipped).
- [ ] M1 — Design `toMermaidAlternative`'s layout: pick a layout
      strategy (parallel arms inside `state Arm1 { … } / state Arm2
      { … }` blocks) and document the trade-off vs. cross-product
      flat layout. Hand-write a small Mermaid sample reflecting the
      chosen layout and verify it renders in at least one
      Mermaid-aware previewer; if the implementer is an LLM agent
      and cannot perform visual verification, document and pause as
      EP-31 / EP-32 do.
- [ ] M2 — Design `toMermaidFeedback1`'s layout: confirm the flat
      3-deep cross-product approach (labels
      `<show s1>_<show s2>_<show s1>`) and document any departure
      from EP-31's 2-deep precedent.
- [ ] M3 — Implement `toMermaidAlternative` in
      `src/Keiki/Render/Mermaid.hs`; export it; verify in `ghci`
      against `siblings` (the existing alternative test fixture).
- [ ] M4 — Implement `toMermaidFeedback1` in
      `src/Keiki/Render/Mermaid.hs`; export it; verify in `ghci`
      against `loop` (the existing feedback1 test fixture).
- [ ] M5 — Render diagrams under `docs/guide/diagrams/` for both
      fixtures (`composite-email-pinger-alternative.md`,
      `composite-toggle-feedback1.md`).
- [ ] M6 — Add regression tests in `test/Keiki/Render/MermaidSpec.hs`
      pinning canonical output for both renderers; `cabal test`
      passes (expected count: 200 if EP-32 hasn't shipped, 201 if
      it has).


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights
discovered during implementation. Provide concise evidence (test
output, ghci transcripts, etc.).

(None yet.)


## Decision Log

- Decision: Two separate rendering functions (`toMermaidAlternative`,
  `toMermaidFeedback1`) rather than one shape-detecting wrapper.
  Rationale: The composite vertex type alone does not distinguish
  `compose`, `alternative`, and `feedback1` — `compose` and
  `alternative` both produce `Composite s1 s2`-vertexed
  transducers; `feedback1` produces `Composite s1 (Composite s2 s1)`,
  which is the same shape any 3-stage `compose` chain produces. Even
  if we tagged composites at construction, runtime shape detection
  would mean the renderer's behaviour depends on metadata that's
  not reflected in the type. Letting the user pick the renderer
  matches the user's mental model of the composition they wrote
  and keeps the renderer code straightforward.
  Date: 2026-05-03

- Decision: `toMermaidAlternative` takes the two component
  transducers (`t1`, `t2`) rather than the composite produced by
  `alternative t1 t2`.
  Rationale: The parallel-arms layout requires walking each arm's
  topology independently — initial state, edges, finals all
  rendered per arm and then wrapped in their respective state
  blocks. Reconstructing per-arm topology from the composite's
  edge set would require partitioning edges by which arm they
  belong to, which is not derivable from the composite alone
  (the lifters in `Keiki.Composition` preserve `icName` /
  `wcName`, so a renderer cannot tell `Left`-arm edges from
  `Right`-arm edges by name). Taking the two components directly
  keeps the renderer total and matches the user's call site —
  if they wrote `alternative t1 t2`, they pass the same two
  arguments to the renderer.
  Date: 2026-05-03

- Decision: `toMermaidFeedback1` takes the two component transducers
  (`t`, `f`) rather than the composite, for API symmetry with
  `toMermaidAlternative` and the user's call-site convention.
  Rationale: The function constructs the composite internally
  (`feedback1 t f`) and renders it. Keeps the surface uniform across
  the three composite-renderer variants.
  Date: 2026-05-03

- Decision: `toMermaidFeedback1` uses **flat 3-deep cross-product**
  layout (labels `<show s1>_<show s2>_<show s1>`), generalising
  EP-31's 2-deep approach.
  Rationale: For the existing test fixture (`loop = feedback1
  toggleAgg togglePolicy`), the 3-deep cross-product is `2 * 1 * 2
  = 4` vertices — small enough to read flat. Larger cascades would
  benefit from grouping (the equivalent of EP-32's Shape B for
  3-deep), but that's out of scope for this plan; the plan's
  Outcomes will note it as a candidate follow-up if the larger-cascade
  use case emerges. Sticking to flat 3-deep keeps the implementation
  trivially layered on EP-31's `renderTopology` (just substitute a
  3-tuple label function).
  Date: 2026-05-03

- Decision: This plan does NOT introduce specialised renderers for
  arbitrary nested `Composite (Composite a b) c` or `Composite a
  (Composite b (Composite c d))` shapes that future user code
  might author by stacking `compose`. Only the specific shapes
  produced by the two named combinators are in scope.
  Rationale: User-authored multi-stage compositions can use
  `toMermaidComposite` (flat 2-deep) on the top-level composite —
  the inner composite's `Show` instance produces `"Composite a
  b"` which `compositeLabel` then joins to
  `"<outerShow>_Composite a b"`, with spaces. That's broken — but
  it's broken at the `Show` level, not at the renderer level,
  and "fix arbitrary-depth nesting" is a different problem from
  "render the named combinators." A future EP can address the
  general case if demand emerges.
  Date: 2026-05-03


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or
at completion.

(To be filled during and after implementation.)


## Context and Orientation

This section names every file, type, and combinator a novice needs
before implementing the plan.

**Repository layout.** Haskell library under `cabal`. Sources in
`src/`, tests in `test/`. Build / test from the repo root:

    cabal build all
    cabal test

GHC 9.12.x. The Nix flake provides z3, but pure rendering does not
need it.

**`SymTransducer phi rs s ci co`.** Defined in `src/Keiki/Core.hs`.
The renderer needs `edgesOut`, `initial`, `isFinal`. (Reference EP-30
for the full anatomy if needed.)

**`Edge`, `HsPred`, `InCtor`, `WireCtor`, `OutTerm`.** All defined
in `src/Keiki/Core.hs`. The renderer's existing `edgeInputName` /
`edgeOutputName` / `edgeLabel` helpers walk these to produce the
`<input ctor> / <output ctor>` edge label format. EP-30's plan
documents the AST walk in detail.

**`Composite s1 s2`.** `src/Keiki/Composition.hs:87`:

    data Composite s1 s2 = Composite !s1 !s2
      deriving (Eq, Show)

`Bounded` and `Enum` instances follow at lines 91–112. Nested
composite types like `Composite s1 (Composite s2 s1)` use the same
instances recursively.

**`compose`.** `src/Keiki/Composition.hs:687`. Sequential
composition; produces `Composite s1 s2`-vertexed transducers. EP-31
is the renderer for these. **Not** the target of this plan but
referenced by `feedback1`'s implementation.

**`alternative`.** `src/Keiki/Composition.hs:810`. Signature
(simplified):

    alternative
      :: ( WeakenR rs1, Disjoint (Names rs1) (Names rs2) )
      => SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 co1
      -> SymTransducer (HsPred rs2 ci2) rs2 s2 ci2 co2
      -> SymTransducer (HsPred (Append rs1 rs2) (Either ci1 ci2))
                       (Append rs1 rs2)
                       (Composite s1 s2)
                       (Either ci1 ci2)
                       (Either co1 co2)

Edge semantics from `src/Keiki/Composition.hs:822–872` (the
`altEdges` / `liftEdgeL` / `liftEdgeR` functions):

- At composite vertex `Composite s1 s2`, the outgoing edges are the
  union of:
  - **t1's edges from s1**, with guards / updates / outputs lifted
    via `liftLPredAlt` / `liftLUpdateAlt` / `liftLOutAlt` (so they
    fire only on `Left _` inputs and emit `Left _` outputs).
    Target: `Composite (target e1) s2` — **changes only s1**, leaves
    s2 fixed.
  - **t2's edges from s2**, with guards / updates / outputs lifted
    via `liftRPredAlt` / `liftRUpdateAlt` / `liftROutAlt` (fire only
    on `Right _`, emit `Right _`). Target: `Composite s1 (target e2)`
    — **changes only s2**.

The Either-arm-tagging is the key to the parallel-arms semantics.
The composite has many same-outer edges (any t2-arm edge keeps s1
fixed; any t1-arm edge keeps s2 fixed) — this is exactly the visual
case where the cross-product layout becomes hard to read and
parallel-arms grouping shines.

**Edge labels under `alternative`.** The lifters (`leftInCtor`,
`rightInCtor`, `leftWireCtor`, `rightWireCtor`) all preserve the
underlying constructor names: `icName`, `wcName` are unchanged.
So `edgeInputName` and `edgeOutputName` recover the same names
they would have for the unlifted edges. The renderer doesn't need
to handle the Either tagging specially — the label format
`<input ctor> / <output ctor>` (e.g. `"SendEmail / EmailSent"` for
the EmailDelivery arm; `"Ping / Pong"` for the Pinger arm) reads
naturally even though the actual runtime input is `Left
sampleSendEmail` and output is `Left sampleEmailEvent`.

**`feedback1`.** `src/Keiki/Composition.hs:935`. Signature:

    feedback1
      :: ( WeakenR rs1, WeakenR rs2
         , Disjoint (Names rs2) (Names rs1)
         , Disjoint (Names rs1) (Names (Append rs2 rs1))
         )
      => SymTransducer (HsPred rs1 ci) rs1 s1 ci co
      -> SymTransducer (HsPred rs2 co) rs2 s2 co ci
      -> SymTransducer (HsPred (Append rs1 (Append rs2 rs1)) ci)
                       (Append rs1 (Append rs2 rs1))
                       (Composite s1 (Composite s2 s1))
                       ci
                       co

Implementation (`src/Keiki/Composition.hs:949`): `feedback1 t f =
compose t (compose f t)`. The composite vertex is `Composite s1
(Composite s2 s1)`:

- Outer s1: the **outer** copy of t's vertex — receives the
  external command first.
- Inner outer s2: the policy (f) vertex — observes t's emitted
  event.
- Inner inner s1: the **inner** copy of t's vertex — consumes the
  policy's emitted command.

Even though the inner s1 has the same Haskell type as the outer s1,
the type system treats them as distinct dimensions of the composite
vertex tuple: `isSingleValuedSym`'s per-vertex enumeration walks all
`|s1| * |s2| * |s1|` combinations independently. So a vertex like
`Composite Off (Composite Pol Off)` reads as "outer toggle is Off,
policy is Pol, inner toggle is Off."

The `feedback1` constraint `Disjoint (Names rs1) (Names (Append rs2
rs1))` is only satisfiable when `rs1 = '[]` — t must be **stateless**
(register-file-empty). The fixture for this plan obeys: both
`toggleAgg` and `togglePolicy` have `'[]` register files.

**Test fixtures this plan targets.**

For `alternative`, the canonical fixture is `siblings = alternative
emailDelivery pinger` defined in
`test/Keiki/CompositionAlternativeSpec.hs:144`. Components:

- `emailDelivery` — shipped library aggregate from
  `Keiki.Examples.EmailDelivery`. `EmailVertex = EmailPending |
  EmailSentVertex` (2 vertices). One edge from `EmailPending` on
  `SendEmail` emitting `EmailSent`. `EmailSentVertex` is final.
- `pinger` — defined inline in the spec file (lines 93–123 of
  `CompositionAlternativeSpec.hs`). `PingVertex = PingIdle |
  PingDone` (2 vertices). One edge from `PingIdle` on `Ping`
  emitting `Pong`. `PingDone` is final.

The alternative composite has `2 * 2 = 4` vertices, with 2 same-arm
edges (each arm contributes one edge that keeps the other arm
fixed): `Composite EmailPending PingIdle → Composite EmailSentVertex
PingIdle` (Email arm) and `Composite EmailPending PingIdle →
Composite EmailPending PingDone` (Ping arm). The composite is final
at `Composite EmailSentVertex PingDone`.

**The alternative spec module currently exports only `spec`.** Per
EP-31's M4 decision pattern, this plan exports the relevant fixture
values (`pinger`, `PingVertex (..)`) from
`Keiki.CompositionAlternativeSpec` so the renderer's regression test
can import them without duplicating fixtures.

For `feedback1`, the canonical fixture is `loop = feedback1
toggleAgg togglePolicy` defined in
`test/Keiki/CompositionFeedback1Spec.hs:200`. Components:

- `toggleAgg` — defined inline (lines 96–130 of that file).
  `ToggleVertex = Off | On` (2 vertices). Each vertex has one
  outgoing `TgFlip` edge that toggles to the other; both vertices
  are final (`isFinal = const True`).
- `togglePolicy` — defined inline (lines 160–183 of that file).
  `PolicyVertex = Pol` (single vertex). One self-edge from `Pol`
  on `TgFlipped` emitting `TgFlip`. The vertex is final.

The feedback1 composite has `2 * 1 * 2 = 4` vertices. The fixture's
spec module currently exports only `spec`; this plan exports
`toggleAgg`, `togglePolicy`, `ToggleVertex (..)`, `PolicyVertex (..)`
following the same pattern.

**`Keiki.Render.Mermaid` (the existing module).** File:
`src/Keiki/Render/Mermaid.hs`. After EP-30 / EP-31, exports
`toMermaid`, `toMermaidComposite`, `vertexLabel`, `compositeLabel`,
`edgeInputName`, `edgeOutputName`, `edgeLabel`. Internal
`renderTopology :: (Enum s, Bounded s) => (s -> Text) ->
SymTransducer (HsPred rs ci) rs s ci co -> Text` is the shared
rendering core (header / init / edges / finals emission); `toMermaid
= renderTopology vertexLabel`, `toMermaidComposite = renderTopology
compositeLabel`.

**Mermaid `stateDiagram-v2` syntax cheatsheet.** What this plan
emits:

For `toMermaidAlternative` (parallel-arms layout):

    stateDiagram-v2
        [*] --> EmailPending
        [*] --> PingIdle
        state LeftArm {
            EmailPending --> EmailSentVertex : SendEmail / EmailSent
        }
        state RightArm {
            PingIdle --> PingDone : Ping / Pong
        }
        EmailSentVertex --> [*]
        PingDone --> [*]

The arm names default to `LeftArm` / `RightArm` (Mermaid
identifiers, not free text). A `…With` variant lets callers
override; see M3 for the full signatures.

For `toMermaidFeedback1` (flat 3-deep cross-product):

    stateDiagram-v2
        [*] --> Off_Pol_Off
        Off_Pol_Off --> On_Pol_On : TgFlip / TgFlipped
        On_Pol_On --> Off_Pol_Off : TgFlip / TgFlipped
        Off_Pol_Off --> [*]
        On_Pol_On --> [*]

(The `loop` fixture has both toggle vertices final and the policy
vertex final, so the conjunction `isFinal` fires at exactly the
two reachable composite vertices `Off_Pol_Off` and `On_Pol_On`.
The other two — `Off_Pol_On`, `On_Pol_Off` — are unreachable / not
final, so the renderer omits them per the established convention.)

**Existing test wiring.** `test/Spec.hs` registers spec modules
under hspec `describe` blocks. The renderer's spec
(`Keiki.Render.MermaidSpec`) is already present at line 46. EP-33
extends the existing spec module with two new describe blocks; no
new spec module file is needed.

**Edge label format for ε-edges.** The shipped fixture for
`alternative` (`siblings`) has no ε-edges. The shipped fixture for
`feedback1` (`loop`) has no ε-edges either. So the ε-handling code
path in `edgeLabel` (which substitutes the Greek letter ε for a
missing output) is not exercised by either canonical regression
test. The path is already covered by EP-30's `userReg` test; no
new ε coverage is needed here.


## Plan of Work

Seven milestones (M0..M6). Each leaves the codebase in a buildable,
testable state.

### M0 — Verify prerequisites

Confirm the following are complete:

- EP-30 (`docs/plans/30-mermaid-renderer-for-single-symtransducer-canonical-example-diagrams.md`)
  — Progress all checked, Outcomes filled.
- EP-31 (`docs/plans/31-mermaid-rendering-for-composite-symtransducers.md`)
  — same.
- EP-25 (`docs/plans/25-alternative-composition-combinator-on-symtransducer.md`)
  and EP-26 (`docs/plans/26-single-step-feedback-combinator-on-symtransducer.md`)
  — both already shipped (the `alternative` and `feedback1`
  combinators are exported from `Keiki.Composition` and tested by
  `Keiki.CompositionAlternativeSpec` / `Keiki.CompositionFeedback1Spec`).

Note: EP-32
(`docs/plans/32-shape-b-nested-subgraph-mermaid-rendering-for-larger-composites.md`)
is a sibling EP under MP-10. EP-33 has **no dependency on EP-32** —
the two can land in either order or in parallel. If EP-32 ships
first, the test count baseline is 199; if EP-33 ships first, it is
198. Record the actual baseline in Surprises.

Run `cabal build all` and `cabal test`. Both must exit 0. Record
GHC and z3 versions plus the test count baseline in Surprises &
Discoveries.

Acceptance: all five referenced plans complete; both commands exit 0;
baseline recorded.

### M1 — Design `toMermaidAlternative`'s layout; verify Mermaid syntax

Pick the layout strategy. The plan recommends parallel-arms inside
named `state … { … }` blocks. The trade-off vs. cross-product flat
layout:

- Cross-product flat (Shape A from EP-31): `Composite s1 s2`
  vertices in a single line, `<show s1>_<show s2>` identifiers.
  Same-outer edges visually crisscross because two arms fire
  independently. Hard to read for >4 vertices.
- Parallel-arms (this plan's choice): two independent state
  machines side by side, each in its own `state ArmName { … }`
  block. The composite's vertex space (which is the cross-product)
  is implicit — the reader infers "the system's actual state is the
  combination of both arms' current states." Edges read naturally
  from each arm's perspective.

Hand-write a Mermaid sample reflecting the parallel-arms layout
(the example in the Context cheatsheet works) and verify it
renders correctly in at least one Mermaid-aware previewer:

- Mermaid Live Editor at https://mermaid.live;
- VS Code's Markdown Preview with Mermaid extension;
- `mmdc` CLI if installed.

Specifically check:

- Both arms render as visually distinct boxes.
- Each `[*] --> InitialOfArm` arrow lands inside its arm's box
  (or close enough that the parallel-start semantics is clear).
- Each `FinalOfArm --> [*]` arrow originates from inside its arm's
  box.
- Edges inside an arm block render entirely inside that block's
  box.

If the implementer is an LLM agent and cannot perform visual
verification, document the constraint in Surprises & Discoveries
explicitly and pause for a human verifier (the same protocol as
EP-32's M1 and EP-31's earlier-discovered constraint).

If verification fails (Mermaid renders the layout in a way that
obscures the parallel semantics — e.g., the two `[*]` arrows
collapse into one), record the failure and re-evaluate. Possible
alternatives: drop the per-arm `[*]` arrows in favour of a single
`[*] --> EmailPending; [*] --> PingIdle` pair at the top level
(Mermaid permits multiple top-level initial arrows), or use
`note` annotations to clarify the parallel-start.

Acceptance: a screenshot, URL, or SVG snippet recorded in
Surprises confirming the parallel-arms syntax renders correctly.

### M2 — Design `toMermaidFeedback1`'s layout

Confirm the **flat 3-deep cross-product** approach. The label
function maps a `Composite s1 (Composite s2 s1)` value to
`<show s1>_<show s2>_<show s1>` (joined with single underscores
on both sides). Implementation is a one-line generalisation of
EP-31's `compositeLabel` for 3-deep:

    feedback1Label :: (Show s1, Show s2)
                   => Composite s1 (Composite s2 s1) -> Text
    feedback1Label (Composite a (Composite b c)) =
      T.pack (show a) <> T.pack "_"
        <> T.pack (show b) <> T.pack "_"
        <> T.pack (show c)

Hand-verify on the `loop` fixture's vertex space:

    Composite Off  (Composite Pol Off)  →  "Off_Pol_Off"
    Composite Off  (Composite Pol On)   →  "Off_Pol_On"
    Composite On   (Composite Pol Off)  →  "On_Pol_Off"
    Composite On   (Composite Pol On)   →  "On_Pol_On"

All four are valid Mermaid identifiers
(`[A-Za-z_][A-Za-z0-9_]*`). No verification step needed beyond the
label function — the body of `toMermaidFeedback1` reuses
EP-31's `renderTopology` core (with `feedback1Label` as the label
function), which has been exercised since EP-31 shipped.

Acceptance: design recorded in Decision Log; no code change yet.

### M3 — Implement `toMermaidAlternative`

Add to `src/Keiki/Render/Mermaid.hs`. Sketch:

    -- | Render an 'alternative'-shaped composite as parallel
    -- side-by-side state machines. Each component transducer
    -- becomes its own @state \<arm-name\> { \<topology\> }@
    -- block; cross-arm coupling is implicit (the runtime
    -- composite's vertex is the cross-product, but the diagram
    -- presents two independent machines that evolve
    -- independently as Either-tagged inputs arrive).
    --
    -- Default arm names are @LeftArm@ and @RightArm@. Use
    -- 'toMermaidAlternativeWith' to override.
    toMermaidAlternative
      :: ( Enum s1, Bounded s1, Show s1
         , Enum s2, Bounded s2, Show s2
         )
      => SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 co1
      -> SymTransducer (HsPred rs2 ci2) rs2 s2 ci2 co2
      -> Text
    toMermaidAlternative =
      toMermaidAlternativeWith (T.pack "LeftArm") (T.pack "RightArm")

    toMermaidAlternativeWith
      :: ( Enum s1, Bounded s1, Show s1
         , Enum s2, Bounded s2, Show s2
         )
      => Text  -- ^ left arm's state-block name
      -> Text  -- ^ right arm's state-block name
      -> SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 co1
      -> SymTransducer (HsPred rs2 ci2) rs2 s2 ci2 co2
      -> Text
    toMermaidAlternativeWith leftName rightName t1 t2 =
      let ind   = T.pack "    "
          ind2  = T.pack "        "
          arrow = T.pack " --> "
          colon = T.pack " : "

          header = T.pack "stateDiagram-v2"

          initLines =
            [ ind <> T.pack "[*]" <> arrow <> vertexLabel (initial t1)
            , ind <> T.pack "[*]" <> arrow <> vertexLabel (initial t2)
            ]

          armBlock name t =
            T.intercalate (T.pack "\n") $
              [ ind <> T.pack "state " <> name <> T.pack " {" ]
              ++
              [ ind2 <> vertexLabel s <> arrow
                     <> vertexLabel (target e) <> colon <> edgeLabel e
              | s <- [minBound .. maxBound], e <- edgesOut t s
              ]
              ++
              [ ind <> T.pack "}" ]

          finalLines t =
            [ ind <> vertexLabel s <> arrow <> T.pack "[*]"
            | s <- [minBound .. maxBound], isFinal t s
            ]

      in T.intercalate (T.pack "\n") $
           header
           : initLines
           ++ [ armBlock leftName t1
              , armBlock rightName t2
              ]
           ++ finalLines t1
           ++ finalLines t2

Add `toMermaidAlternative` and `toMermaidAlternativeWith` to the
module's export list (alphabetical: after `toMermaid`, before
`toMermaidComposite`).

Edit `test/Keiki/CompositionAlternativeSpec.hs` to widen the
module's export list:

    module Keiki.CompositionAlternativeSpec
      ( spec
        -- Exported for re-use in 'Keiki.Render.MermaidSpec' (EP-33 M6).
        -- See the Decision Log of
        -- @docs/plans/33-shape-aware-mermaid-renderers-for-alternative-and-feedback1-composites.md@
        -- for why we re-export rather than duplicate the fixture.
      , pinger
      , PingVertex (..)
      , siblings
      ) where

Verify in `ghci`:

    cabal repl keiki-test --repl-no-load
    ghci> :load Keiki.CompositionAlternativeSpec
    ghci> import Keiki.Render.Mermaid (toMermaidAlternative)
    ghci> import Keiki.Examples.EmailDelivery (emailDelivery)
    ghci> import qualified Data.Text.IO as TIO
    ghci> TIO.putStrLn (toMermaidAlternative emailDelivery
                          Keiki.CompositionAlternativeSpec.pinger)

Expected output (the canonical block M5/M6 will pin):

    stateDiagram-v2
        [*] --> EmailPending
        [*] --> PingIdle
        state LeftArm {
            EmailPending --> EmailSentVertex : SendEmail / EmailSent
        }
        state RightArm {
            PingIdle --> PingDone : Ping / Pong
        }
        EmailSentVertex --> [*]
        PingDone --> [*]

If the actual output deviates (different ordering of init / arms /
finals; different indentation; different separator placement),
record the deviation in Surprises and update the Purpose section
+ M5/M6 expected strings accordingly. The output emitted is the
source of truth.

Acceptance: `cabal build all` succeeds with no warnings; the ghci
transcript matches.

### M4 — Implement `toMermaidFeedback1`

Add to `src/Keiki/Render/Mermaid.hs`:

    -- | Render a 'feedback1'-shaped composite as a flat 3-deep
    -- cross-product diagram. Vertex labels are
    -- @\<show s1\>_\<show s2\>_\<show s1\>@ — outer-t state, then
    -- policy state, then inner-t state. The two t copies (outer
    -- and inner) share the same Haskell vertex type but occupy
    -- distinct dimensions of the composite's vertex tuple, so
    -- they are labelled independently.
    --
    -- For the cascade structure ('feedback1 t f =
    -- compose t (compose f t)') see 'feedback1's haddock and
    -- the design note at
    -- @docs/research/composition-combinators-design.md@.
    toMermaidFeedback1
      :: ( Enum s1, Bounded s1, Show s1
         , Enum s2, Bounded s2, Show s2
         , WeakenR rs1, WeakenR rs2
         , Disjoint (Names rs2) (Names rs1)
         , Disjoint (Names rs1) (Names (Append rs2 rs1))
         )
      => SymTransducer (HsPred rs1 ci) rs1 s1 ci co
      -> SymTransducer (HsPred rs2 co) rs2 s2 co ci
      -> Text
    toMermaidFeedback1 t f =
      renderTopology feedback1Label (feedback1 t f)

    feedback1Label
      :: (Show s1, Show s2)
      => Composite s1 (Composite s2 s1) -> Text
    feedback1Label (Composite a (Composite b c)) =
      T.pack (show a) <> T.pack "_"
        <> T.pack (show b) <> T.pack "_"
        <> T.pack (show c)

Add the imports for `feedback1`, `WeakenR`, `Disjoint`, `Names`,
`Append` (replacing the existing `import Keiki.Composition (Composite (..))`):

    import Keiki.Composition (Composite (..), feedback1, WeakenR)
    import Keiki.Core (Disjoint, Names)  -- already exists; verify
    import Keiki.Generics (Append)        -- already exists; verify

(Verify the actual module that re-exports `Disjoint` / `Names` /
`Append` by inspecting the existing imports in
`src/Keiki/Composition.hs:77-78` and adjust the new imports to
match. The constraints must be in scope at the use site — the
existing `Composition` module's `compose` signature shows the
correct path.)

Add `toMermaidFeedback1` to the export list (alphabetical: after
`toMermaidCompositeNested` if EP-32 has shipped; otherwise after
`toMermaidComposite`).

Edit `test/Keiki/CompositionFeedback1Spec.hs` to widen its export
list:

    module Keiki.CompositionFeedback1Spec
      ( spec
        -- Exported for re-use in 'Keiki.Render.MermaidSpec' (EP-33 M6).
      , toggleAgg
      , togglePolicy
      , ToggleVertex (..)
      , PolicyVertex (..)
      , loop
      ) where

Verify in `ghci`:

    cabal repl keiki-test --repl-no-load
    ghci> :load Keiki.CompositionFeedback1Spec
    ghci> import Keiki.Render.Mermaid (toMermaidFeedback1)
    ghci> import qualified Data.Text.IO as TIO
    ghci> TIO.putStrLn (toMermaidFeedback1
                          Keiki.CompositionFeedback1Spec.toggleAgg
                          Keiki.CompositionFeedback1Spec.togglePolicy)

Expected output (the canonical block M5/M6 will pin):

    stateDiagram-v2
        [*] --> Off_Pol_Off
        Off_Pol_Off --> On_Pol_On : TgFlip / TgFlipped
        On_Pol_On --> Off_Pol_Off : TgFlip / TgFlipped
        Off_Pol_Off --> [*]
        On_Pol_On --> [*]

(The other two composite vertices — `Off_Pol_On` and `On_Pol_Off` —
are unreachable and not final, so the renderer omits them per the
standard convention.)

Acceptance: `cabal build all` succeeds with no warnings; the ghci
transcript matches.

### M5 — Render diagrams under `docs/guide/diagrams/`

Create two files.

`docs/guide/diagrams/composite-email-pinger-alternative.md`:

    # EmailDelivery + Pinger alternative composite topology

    Rendered by `Keiki.Render.Mermaid.toMermaidAlternative` over
    `emailDelivery` (from `Keiki.Examples.EmailDelivery`) and
    `pinger` (defined in
    `test/Keiki/CompositionAlternativeSpec.hs`). Refresh:

        cabal repl keiki-test --repl-no-load
        ghci> :load Keiki.CompositionAlternativeSpec
        ghci> import Keiki.Render.Mermaid (toMermaidAlternative)
        ghci> import Keiki.Examples.EmailDelivery (emailDelivery)
        ghci> import qualified Data.Text.IO as TIO
        ghci> TIO.putStrLn (toMermaidAlternative emailDelivery
                              Keiki.CompositionAlternativeSpec.pinger)

    ```mermaid
    stateDiagram-v2
        [*] --> EmailPending
        [*] --> PingIdle
        state LeftArm {
            EmailPending --> EmailSentVertex : SendEmail / EmailSent
        }
        state RightArm {
            PingIdle --> PingDone : Ping / Pong
        }
        EmailSentVertex --> [*]
        PingDone --> [*]
    ```

    The composite's underlying vertex space is the cross-product
    `Composite EmailVertex PingVertex` — four states. The diagram
    presents the two arms as independent state machines because
    that is how `alternative` actually behaves at runtime: each
    Either-tagged input advances exactly one arm and leaves the
    other untouched. The two `[*]` arrows mark both arms as
    starting at their respective initial vertices simultaneously.

    For the underlying composite's flat-cross-product variant
    (as `toMermaidComposite` would render it), the layout would be
    a 4-vertex line with same-outer edges visually crisscrossing —
    visually confusing. The arm-separated layout is the readable
    form.

`docs/guide/diagrams/composite-toggle-feedback1.md`:

    # Toggle ↔ Toggle-policy feedback1 cascade topology

    Rendered by `Keiki.Render.Mermaid.toMermaidFeedback1` over
    `toggleAgg` and `togglePolicy` (both defined in
    `test/Keiki/CompositionFeedback1Spec.hs`). Refresh:

        cabal repl keiki-test --repl-no-load
        ghci> :load Keiki.CompositionFeedback1Spec
        ghci> import Keiki.Render.Mermaid (toMermaidFeedback1)
        ghci> import qualified Data.Text.IO as TIO
        ghci> TIO.putStrLn (toMermaidFeedback1
                              Keiki.CompositionFeedback1Spec.toggleAgg
                              Keiki.CompositionFeedback1Spec.togglePolicy)

    ```mermaid
    stateDiagram-v2
        [*] --> Off_Pol_Off
        Off_Pol_Off --> On_Pol_On : TgFlip / TgFlipped
        On_Pol_On --> Off_Pol_Off : TgFlip / TgFlipped
        Off_Pol_Off --> [*]
        On_Pol_On --> [*]
    ```

    The composite vertex is `Composite ToggleVertex (Composite
    PolicyVertex ToggleVertex)` — outer toggle, then (policy,
    inner toggle). The 3-deep flat label
    `<outer>_<policy>_<inner>` makes the cascade visible: each
    edge advances all three components in one atomic step
    (`feedback1 t f = compose t (compose f t)`), so an input of
    `TgFlip` from `Off_Pol_Off` lands at `On_Pol_On` (both
    toggles flipped, policy unchanged because it self-loops).

    The cross-product would have `2 * 1 * 2 = 4` vertices in
    total; only two are reachable / final (the `Off_Pol_*` /
    `On_Pol_*` symmetric pair where inner and outer toggle agree),
    so the other two are omitted.

Verify each file renders in M1's chosen previewer.

Acceptance: both files exist, contain fenced ```mermaid blocks,
and render correctly.

### M6 — Regression tests for both renderers

Extend `test/Keiki/Render/MermaidSpec.hs` with two new describe
blocks. The file's structure already accommodates this (EP-31's M4
established the multiple-describe-blocks pattern).

Update the imports block:

    import Keiki.CompositionAlternativeSpec (pinger)
    import Keiki.CompositionFeedback1Spec (toggleAgg, togglePolicy)
    import Keiki.Examples.EmailDelivery (emailDelivery)
    import Keiki.Render.Mermaid
      ( toMermaid
      , toMermaidAlternative
      , toMermaidComposite
      , toMermaidFeedback1
      )

(Update the existing `Keiki.Render.Mermaid` import to include the
new entry points; add the two fixture-spec imports.)

Add to the body of `spec`:

    describe "toMermaidAlternative (alternative composite)" $
      it "renders alternative emailDelivery pinger" $
        toMermaidAlternative emailDelivery pinger
          `shouldBe` emailPingerAltCanonical

    describe "toMermaidFeedback1 (feedback1 composite)" $
      it "renders feedback1 toggleAgg togglePolicy" $
        toMermaidFeedback1 toggleAgg togglePolicy
          `shouldBe` toggleFeedback1Canonical

Define the canonical strings at module scope alongside
`userRegCanonical` and `alertEmailCompositeCanonical`:

    emailPingerAltCanonical :: Text
    emailPingerAltCanonical = T.intercalate (T.pack "\n")
      [ "stateDiagram-v2"
      , "    [*] --> EmailPending"
      , "    [*] --> PingIdle"
      , "    state LeftArm {"
      , "        EmailPending --> EmailSentVertex : SendEmail / EmailSent"
      , "    }"
      , "    state RightArm {"
      , "        PingIdle --> PingDone : Ping / Pong"
      , "    }"
      , "    EmailSentVertex --> [*]"
      , "    PingDone --> [*]"
      ]

    toggleFeedback1Canonical :: Text
    toggleFeedback1Canonical = T.intercalate (T.pack "\n")
      [ "stateDiagram-v2"
      , "    [*] --> Off_Pol_Off"
      , "    Off_Pol_Off --> On_Pol_On : TgFlip / TgFlipped"
      , "    On_Pol_On --> Off_Pol_Off : TgFlip / TgFlipped"
      , "    Off_Pol_Off --> [*]"
      , "    On_Pol_On --> [*]"
      ]

Run `cabal test`. Expected output (last lines):

    Keiki.Render.Mermaid (EP-30, EP-31, EP-33)
      toMermaid (single SymTransducer)
        renders userReg to the canonical stateDiagram-v2 block
      toMermaidComposite (composite SymTransducer)
        renders the AlertSource ⨾ EmailDelivery pipeline
      toMermaidAlternative (alternative composite)
        renders alternative emailDelivery pinger
      toMermaidFeedback1 (feedback1 composite)
        renders feedback1 toggleAgg togglePolicy

(If EP-32 has also shipped, its describe block appears between
the existing EP-31 block and EP-33's blocks, and the wrapper title
in `test/Spec.hs` becomes `(EP-30, EP-31, EP-32, EP-33)`. Either
revise the title or leave it; the implementer chooses, recording
in Surprises if non-trivial.)

Test count after this plan: 200 (or 201 if EP-32 has shipped).

Anti-validation: temporarily mutate one line of either canonical
string and confirm `cabal test` reports a clear `expected … but
got …` diff in the corresponding describe block. Revert before
commit.

Acceptance: `cabal test` exits 0; both new describe blocks are
green; test count is 200 or 201; anti-validation transient
confirmed.


## Concrete Steps

All commands run from the repo root.

M0:

    cabal build all
    cabal test
    ghc --version
    z3 --version

M1:

    # Hand-write parallel-arms Mermaid sample, render in chosen
    # previewer. Document verification in Surprises & Discoveries.
    # If LLM agent: pause for human verifier.

M2:

    # Design recorded in Decision Log; no code change.

M3:

    # Edit src/Keiki/Render/Mermaid.hs:
    #   - Add toMermaidAlternative + toMermaidAlternativeWith
    #     to exports.
    #   - Implement both function bodies per the M3 sketch.
    # Edit test/Keiki/CompositionAlternativeSpec.hs:
    #   - Widen module export list to include `pinger`,
    #     `PingVertex (..)`, `siblings`.
    cabal build all
    cabal repl keiki-test --repl-no-load
    ghci> :load Keiki.CompositionAlternativeSpec
    ghci> import Keiki.Render.Mermaid (toMermaidAlternative)
    ghci> import Keiki.Examples.EmailDelivery (emailDelivery)
    ghci> import qualified Data.Text.IO as TIO
    ghci> TIO.putStrLn (toMermaidAlternative emailDelivery
                          Keiki.CompositionAlternativeSpec.pinger)

M4:

    # Edit src/Keiki/Render/Mermaid.hs:
    #   - Update import block to bring in `feedback1` (and any
    #     transitive constraint exports) from Keiki.Composition.
    #   - Add toMermaidFeedback1 to exports.
    #   - Implement function body.
    # Edit test/Keiki/CompositionFeedback1Spec.hs:
    #   - Widen module export list to include `toggleAgg`,
    #     `togglePolicy`, `ToggleVertex (..)`, `PolicyVertex (..)`,
    #     `loop`.
    cabal build all
    cabal repl keiki-test --repl-no-load
    ghci> :load Keiki.CompositionFeedback1Spec
    ghci> import Keiki.Render.Mermaid (toMermaidFeedback1)
    ghci> import qualified Data.Text.IO as TIO
    ghci> TIO.putStrLn (toMermaidFeedback1
                          Keiki.CompositionFeedback1Spec.toggleAgg
                          Keiki.CompositionFeedback1Spec.togglePolicy)

M5:

    # Edit docs/guide/diagrams/composite-email-pinger-alternative.md (new).
    # Edit docs/guide/diagrams/composite-toggle-feedback1.md (new).

M6:

    # Edit test/Keiki/Render/MermaidSpec.hs:
    #   - Update Keiki.Render.Mermaid import to include the two new
    #     entry points.
    #   - Add imports for pinger, toggleAgg, togglePolicy,
    #     emailDelivery.
    #   - Add two describe blocks and two canonical strings.
    cabal test


## Validation and Acceptance

The plan succeeds when all of the following hold:

1. `cabal build all` produces no warnings or errors.
2. `cabal test` passes; both new describe blocks
   (`toMermaidAlternative (alternative composite)` and
   `toMermaidFeedback1 (feedback1 composite)`) are present and
   green; test count is 200 or 201.
3. `Keiki.Render.Mermaid` exports the three new entry points:
   `toMermaidAlternative`, `toMermaidAlternativeWith`,
   `toMermaidFeedback1`, plus any internal helpers.
4. `docs/guide/diagrams/composite-email-pinger-alternative.md` and
   `docs/guide/diagrams/composite-toggle-feedback1.md` exist,
   contain fenced ```mermaid blocks, and render correctly in a
   Mermaid-aware previewer.
5. The Mermaid-syntax verification for the parallel-arms layout is
   recorded in Surprises & Discoveries (per M1's protocol; or
   paused for human verifier if the implementer is an LLM agent).

Anti-validation: a transient mutation of either canonical string
produces a clear `expected … but got …` diff; reverted before
commit.


## Idempotence and Recovery

All steps are idempotent. The renderers are pure functions; ghci
pipelines can be repeated at will. The diagram files are
regenerated from `toMermaidAlternative` / `toMermaidFeedback1`
output. The regression tests pin the exact text, so any drift
surfaces in CI and the implementer re-runs the ghci pipeline to
refresh diagram files.

If M1's verification fails (the parallel-arms Mermaid syntax
doesn't render as expected), pause the plan, record the failure
in Surprises, and re-evaluate before proceeding to M3. Possible
fallbacks:

- Drop the per-arm `[*]` arrows in favour of a single top-level
  pair.
- Use plain text annotations (`note left of … : Email arm`)
  instead of `state … { … }` blocks.
- Fall back to flat cross-product (Shape A from EP-31)
  with a comment in the diagram file noting the arm structure.

If a regression test fails after a `Keiki.Composition` change
(e.g., someone reorders edges in `liftEdgeL` / `liftEdgeR` in
`alternative`), the test surfaces the drift; the author re-runs
the ghci pipeline for the affected fixture and updates the
canonical string + diagram file together.

If the export-extending edit to `CompositionAlternativeSpec` /
`CompositionFeedback1Spec` causes a circular import (e.g., if
those spec modules import `Keiki.Render.MermaidSpec` for some
reason — they currently do not), reorganise the imports to break
the cycle. The natural direction is `MermaidSpec` imports the
fixture modules, never the reverse.

There are no destructive operations.


## Interfaces and Dependencies

**Module surface change:** `src/Keiki/Render/Mermaid.hs` gains:

    toMermaidAlternative
      :: ( Enum s1, Bounded s1, Show s1
         , Enum s2, Bounded s2, Show s2
         )
      => SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 co1
      -> SymTransducer (HsPred rs2 ci2) rs2 s2 ci2 co2
      -> Text

    toMermaidAlternativeWith
      :: ( Enum s1, Bounded s1, Show s1
         , Enum s2, Bounded s2, Show s2
         )
      => Text -> Text
      -> SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 co1
      -> SymTransducer (HsPred rs2 ci2) rs2 s2 ci2 co2
      -> Text

    toMermaidFeedback1
      :: ( Enum s1, Bounded s1, Show s1
         , Enum s2, Bounded s2, Show s2
         , WeakenR rs1, WeakenR rs2
         , Disjoint (Names rs2) (Names rs1)
         , Disjoint (Names rs1) (Names (Append rs2 rs1))
         )
      => SymTransducer (HsPred rs1 ci) rs1 s1 ci co
      -> SymTransducer (HsPred rs2 co) rs2 s2 co ci
      -> Text

Plus an internal `feedback1Label` helper (and any private helper
that falls out of `toMermaidAlternative`'s implementation). The
new functions reuse `vertexLabel`, `edgeLabel`, and
`renderTopology` (the latter for `toMermaidFeedback1` only).

**New imports** in `Keiki.Render.Mermaid`:

    import Keiki.Composition (Composite (..), feedback1, WeakenR)

(Plus whichever module re-exports `Disjoint`, `Names`, and `Append`
— verify by inspecting `src/Keiki/Composition.hs`'s import block,
which uses these constraints in `compose`'s signature.)

**Library dependencies:** no change.

**Cabal changes:** none required — `Keiki.Render.Mermaid` is
already exposed; `Keiki.Render.MermaidSpec`,
`Keiki.CompositionAlternativeSpec`, `Keiki.CompositionFeedback1Spec`
are all already registered in the test-suite's `other-modules`.

**Hard dependency:** EP-30
(`docs/plans/30-mermaid-renderer-for-single-symtransducer-canonical-example-diagrams.md`)
and EP-31
(`docs/plans/31-mermaid-rendering-for-composite-symtransducers.md`).
The reuse of `renderTopology` and the established edge-label /
identifier conventions makes EP-31 a hard dep.

**Hard dependency (external):** EP-25
(`docs/plans/25-alternative-composition-combinator-on-symtransducer.md`)
and EP-26
(`docs/plans/26-single-step-feedback-combinator-on-symtransducer.md`)
— both already shipped under MasterPlan 8. Their fixtures
(`siblings`, `loop`) and the `alternative` / `feedback1`
combinators they ship are what EP-33 renders.

**Soft dependency:** EP-32
(`docs/plans/32-shape-b-nested-subgraph-mermaid-rendering-for-larger-composites.md`)
— a sibling EP under MP-10. EP-33 has no dependency on EP-32; the
two can land in either order. If EP-32 ships first, EP-33's M0
test count baseline becomes 199; if EP-33 ships first, EP-32's
M0 baseline becomes 199.

**Out of scope:**

- Specialised renderers for arbitrary nested `Composite (Composite
  a b) c` or deeper composites authored by stacking `compose`. Only
  the specific shapes produced by `alternative` and `feedback1` are
  in scope.
- Diff visualisation across two transducers (`diffTransducers`
  from the futures note). MasterPlan-level deferral.
- DOT / Graphviz output. MasterPlan-level deferral.
- A `keiki-render` CLI executable. Library-only as before.
- Per-edge guard / update inspection. v1 deferral.
- Multi-round (`feedbackN`) rendering. The combinator itself is
  a future extension; no rendering EP can be authored before the
  combinator exists.
