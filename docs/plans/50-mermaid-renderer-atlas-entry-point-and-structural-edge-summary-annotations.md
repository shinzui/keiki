---
id: 50
slug: mermaid-renderer-atlas-entry-point-and-structural-edge-summary-annotations
title: "Mermaid renderer: atlas entry point and structural edge-summary annotations"
kind: exec-plan
created_at: 2026-05-21T22:59:23Z
intention: "intention_01ks6ber3jedc8ff6zzma2jr53"
master_plan: "docs/masterplans/13-keiki-api-improvements-surfaced-by-the-rei-migration.md"
---

# Mermaid renderer: atlas entry point and structural edge-summary annotations

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This plan makes two small, additive improvements to keiki's Mermaid diagram
renderer. "Mermaid" is a text-based diagram language; a block of Mermaid text
beginning with the line `stateDiagram-v2` renders as a state-machine drawing in
GitHub, Notion, VS Code, and most Markdown previewers. The renderer lives at
`src/Keiki/Render/Mermaid.hs`; it turns a keiki transducer (the data structure
that models an aggregate's lifecycle — defined as `SymTransducer` in
`src/Keiki/Core.hs`) into such a block.

After this change, two new abilities exist:

First, a keiki user can render many diagrams into a single document with one
call. Today the only entry points (`toMermaid`, `toMermaidComposite`, and
relatives) each render exactly one transducer to one `stateDiagram-v2` block. A
consumer who wanted a single "atlas" page covering twenty aggregates had to
write their own loop that calls the renderer per aggregate, wraps each result in
a heading, and concatenates — Rei (the downstream consumer that motivated this
MasterPlan) wrote roughly eighty lines of such glue. The new
`toMermaidAtlas :: [(Text, Text)] -> Text` takes a list of
`(label, already-rendered-diagram)` pairs and assembles one labelled document.
You can see it working by feeding it two `toMermaid` outputs with names and
observing one document that contains both diagrams under their headings.

Second, a reviewer reading a diagram can optionally see *why* an edge fires and
*what it changes*, not just the command and event names. Today an edge label
reads `<input command> / <output event>` — for example
`StartRegistration / RegistrationStarted; ConfirmationEmailSent`. That tells you
the trigger and the emission, but not the guard condition that must hold for the
edge to fire, nor which registers (the aggregate's stored fields) the edge
writes. The new opt-in summary appends a compact structural suffix, e.g.
`StartRegistration / RegistrationStarted; ConfirmationEmailSent [w: email; confirmCode; registeredAt]`,
or for a guarded edge `ConfirmAccount / AccountConfirmed [w: confirmedAt; g: PEq]`.
You can see it working by rendering the same transducer with the summary turned
on and observing the bracketed suffix appear.

Crucially, the suffix is **opt-in**, and the existing no-options entry point
`toMermaid` produces **byte-identical** output to today. This is not a stylistic
preference — it is load-bearing. The guide
`docs/guide/deriving-lifecycle-transitions.md` teaches a bug-spotting technique
that depends on the default label format *deliberately omitting the guard*: two
edges that differ only by an unshown guard look identical in the default
diagram, which makes a *missing* second edge visually obvious. If the default
ever started showing guards, that pedagogy would break. So this plan keeps the
default guard-free and proves it with a byte-for-byte regression test.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M1 (2026-05-21): Added `toMermaidAtlas :: [(Text, Text)] -> Text` to
      `src/Keiki/Render/Mermaid.hs`, exported, assembling labelled already-rendered
      diagrams into one Markdown document (`## ` heading + fenced ```mermaid block
      per section, sections joined by a blank line). `cabal build keiki` clean.
- [x] M2 (2026-05-21): Added the opt-in structural edge summary — a `MermaidOptions`
      record (`showWrittenSlots`/`showGuardSummary`), `defaultMermaidOptions`,
      `toMermaidWith`, the private `renderTopologyWith`/`edgeLabelWith`/`writtenSlots`/
      `guardSummary`, and the new `import Keiki.Internal.Slots (indexNName)`. `toMermaid`
      and `renderTopology` re-point at the options cores with the default. `cabal build
      keiki` clean. Note: `edgeLabelWith` must *pattern-match* the `Edge` to read
      `update` (the record selector can't be used due to the existential write-set) —
      see Surprises.
- [x] M3 (2026-05-21): Added three goldens to `test/Keiki/Render/MermaidSpec.hs`
      (default-identity, annotated variant, atlas) — captured from the renderer, not
      hand-typed; the pre-existing `userRegCanonical` golden passes unchanged
      (byte-identical proof, actively verified by transiently flipping a default).
      Authored `docs/guide/mermaid-rendering.md` (atlas, opt-in summary, why it is
      structural-not-AST, the deliberate guard-free default with a pointer to
      `deriving-lifecycle-transitions.md`) and cross-linked it from that guide.
      `cabal test all` green (keiki-test 253/0).


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **The `update` record selector cannot be used as a function (2026-05-21).** The plan's
  Plan-of-Work note claimed "pattern-matching `update e` and `guard e` on an `Edge` is fine
  despite the existential `w`". That is half-right: `guard e` (a non-existential field) works
  as a selector, but `update e` does **not** — GHC rejects it with
  `error: [GHC-55876] Cannot use record selector 'update' as a function due to escaped type
  variables`, because `Edge`'s `update :: Update rs w ci` existentially quantifies `w`. The fix
  is to **pattern-match** the edge: `edgeLabelWith opts e@Edge { update = u, guard = g } = …`,
  which binds `u` locally so `w` does not escape, while `e` remains in scope for `edgeLabel e`.
  `guardSummary`/`writtenSlots` are parametric in `w` and return `[Text]`, so `w` never leaks.
- **The captured annotated golden differs from the plan's illustrative one (2026-05-21).** The
  plan's illustrative golden guessed `[w: email; confirmCode; registeredAt; g: PAnd PInCtor PTop]`.
  The *actual* captured output is `[w: registeredAt; confirmCode; email; g: PInCtor]` for the
  `StartRegistration` edge: (a) the written-slot order is the `UCombine` nesting order
  (`registeredAt; confirmCode; email`), not source order; and (b) `onCmd` with no extra guard
  produces a **bare `PInCtor`**, not `PAnd PInCtor PTop` — only `ConfirmAccount` (which adds a
  `requireEq`) yields `PAnd PInCtor PEq`. The plan was explicit that the *captured* output is
  the source of truth, so the golden pins the captured bytes. No `g: PTop` appears anywhere.


## Decision Log

Record every decision made while working on the plan.

- Decision: The edge summary is a **structural summary**, not a full
  pretty-printed dump of the guard / update / output abstract syntax trees
  (ASTs). An AST is the in-memory tree shape of an expression; here the relevant
  trees are `HsPred` (the guard predicate, defined in `src/Keiki/Core.hs`),
  `Term` (expressions over registers and input), and `Update` (the
  register-write language). The summary lists only what can be faithfully and
  totally rendered: the written-slot names of an edge's update, the input
  constructor name, and the constructor / comparison tags of the guard.
  Rationale: keiki ships **no** pretty-printer for `HsPred`, `Term`, or
  `Update`, and these ASTs carry **unprintable Haskell functions** — `Term`'s
  `TApp1`/`TApp2` hold opaque closures `(a -> r)` / `(a -> b -> r)`; `InCtor`
  (inside `PInCtor` and `OPack`) holds `icMatch :: ci -> Maybe (RegFile ifs)`
  and `icBuild :: RegFile ifs -> ci`; `WireCtor` (inside `OPack`) holds
  `wcMatch` / `wcBuild`. None of these functions can be turned back into text.
  A full AST render would therefore be impossible for the function-bearing
  cases and unreadable even where possible. MasterPlan-10
  (`docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md`)
  already rejected rendering full guard / update AST in labels as clutter — see
  its Decision Log entry of 2026-05-02 ("Topology-only labels in v1 — no guard /
  update / predicate visualisation in the diagram itself") and its Vision &
  Scope "Out of scope" bullet on "Predicate / guard / update visualisation".
  That same scope text left the door open for a future variant ("the design
  milestone may revisit if a 'labelled by guard summary' variant is wanted").
  This plan walks through that door with a **summary**, not the rejected full
  AST.
  Date: 2026-05-21

- Decision: The summary is **opt-in**; the no-options `toMermaid` default stays
  **byte-identical** to today's output.
  Rationale: `docs/guide/deriving-lifecycle-transitions.md` (§1) teaches a
  bug-spotting technique that relies on `Keiki.Render.Mermaid` "deliberately
  omitting the guard": two edges out of the same vertex that differ only by an
  unshown guard render to identical-looking lines, so a *missing* second edge
  (the "one-way door" demote bug) is glaring as a topology. If the default label
  began showing the guard, the two edges would look different and the technique
  would lose its force. Keeping the summary behind an explicit
  `MermaidOptions` flag preserves the guide's correctness. A golden test pins
  the default output byte-for-byte to make any accidental drift fail in CI.
  Date: 2026-05-21

- Decision: The atlas entry point takes already-rendered `(label, Text)` pairs —
  `toMermaidAtlas :: [(Text, Text)] -> Text` — rather than a list of
  transducers.
  Rationale: different transducers have different type parameters (vertex type
  `s`, register list `rs`, input type `ci`, output type `co`), so a single
  homogeneous list `[SymTransducer …]` does not type-check — the elements would
  need identical type parameters, which real aggregates do not share. The
  faithful, simplest API therefore accepts the rendering each caller already
  produced (each caller knows its own concrete types and calls the matching
  `toMermaid` / `toMermaidComposite` / … itself) and only does the labelling and
  concatenation that was the actual duplicated glue. An existential wrapper
  (a type like `data SomeRenderable = forall s rs ci co. (Enum s, Bounded s,
  Show s) => SomeRenderable (SymTransducer (HsPred rs ci) rs s ci co)`) was
  considered and rejected: it would force callers to wrap each transducer, would
  re-derive the `Enum`/`Bounded`/`Show` constraint discipline at the wrapper,
  and could only call the single-transducer renderer (composites use different
  entry points), so it is strictly heavier while removing the caller's freedom
  to pick the matching renderer. The `(label, Text)` shape is the smallest thing
  that removes the glue.
  Date: 2026-05-21

- Decision: `guardSummary` renders the **full prefix walk** including the boolean
  connectives (`PAnd`/`POr`/`PNot`), not the atomic-tags-only variant the plan
  offered as an alternative.
  Rationale: the connectives are part of the guard's structure and are cheap and
  total to render; keeping them makes the summary a faithful structural projection
  (e.g. `PAnd PInCtor PEq` shows the guard is a conjunction, not a single atom).
  The captured golden pins this shape. `PCmp` carries its `Cmp` direction via
  `show` (`CmpLt`/`CmpLe`/`CmpGt`/`CmpGe`); no operand terms or functions are ever
  printed.
  Date: 2026-05-21

- Decision: Keep the summary on the **single-transducer path only**; the composite
  renderers (`toMermaidComposite`/`toMermaidCompose3`/`toMermaidAlternative`/
  `toMermaidFeedback1` and the nested variants) keep the guard-free label unchanged.
  Rationale: this is what Rei's #5 asked for, and `renderTopology` now delegates to
  `renderTopologyWith defaultMermaidOptions`, so the composites that call it inherit
  the guard-free default with zero edits. Extending the summary to composites is
  additive future work; not widened here.
  Date: 2026-05-21


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

**Outcome (2026-05-21): complete, all three milestones landed.** Against the
original purpose — render many diagrams with one call, and let a reviewer
optionally see an edge's writes and guard structure — the result is:

- `toMermaidAtlas :: [(Text, Text)] -> Text` assembles labelled already-rendered
  diagrams into one Markdown document (subsuming Rei's ~80 lines of atlas glue).
- `toMermaidWith` / `MermaidOptions` add an opt-in `[w: …; g: …]` structural
  suffix; the default (`toMermaid`) is byte-identical to before, proven by the
  unchanged `userRegCanonical` golden and actively verified by transiently
  flipping a default and watching that golden fail.
- `docs/guide/mermaid-rendering.md` documents both, explains why the summary is
  structural-not-AST, and reaffirms the guard-free default with a pointer to
  `deriving-lifecycle-transitions.md` (the soft-alignment contract with EP-46).

**Validation:** `cabal test all` green; keiki-test grew from 250 to 253 examples
(the three new goldens), 0 failures.

**Gaps / lessons:**
- The plan's claim that `update e` works as a record selector was wrong (the
  existential write-set makes GHC reject it); the fix was a pattern match. Lesson:
  when a GADT field is existentially quantified, you must pattern-match to read it,
  never use the auto-derived selector.
- The plan's illustrative annotated golden over-specified the guard tags
  (`PAnd PInCtor PTop`); the real `onCmd` output is a bare `PInCtor` unless a
  `requireEq`/comparison is added. Capturing-not-guessing the golden (as the plan
  instructed) was the right call.
- Scope held: the summary stays single-transducer-only; composites inherit the
  guard-free default through the `renderTopology → renderTopologyWith default`
  delegation with no edits.


## Context and Orientation

This section assumes no prior knowledge of keiki. Read it before touching code.

**What keiki is, in one paragraph.** keiki is a pure Haskell library for
modelling an aggregate's lifecycle as a finite-control transducer with a typed
register file. The single source of truth is the type `SymTransducer phi rs s ci
co`, defined in `src/Keiki/Core.hs` (around line 581). Its fields are
`edgesOut :: s -> [Edge phi rs ci co s]` (the outgoing transitions of each
vertex), `initial :: s` (the start vertex), `initialRegs :: RegFile rs` (the
initial register values), and `isFinal :: s -> Bool` (which vertices are
terminal). Here `s` is the vertex (state) type, `rs` is the register schema
(a type-level list of `(name, type)` pairs called `Slot`s), `ci` is the input
command type, `co` is the output event type, and `phi` is the guard-predicate
carrier. For everything in this plan, `phi` is `HsPred rs ci` (the only guard
AST in the repository).

**What an `Edge` carries.** The `Edge` GADT is defined in `src/Keiki/Core.hs`
(around line 569). Its fields are: `guard :: phi` (the predicate that must hold
for the edge to fire); `update :: Update rs w ci` (how the registers change);
`output :: [OutTerm rs ci co]` (the events emitted — `[]` is an "epsilon edge"
emitting nothing, `[o]` one event, `[o1,o2,…]` several); and `target :: s` (the
destination vertex). The `w :: [Symbol]` type parameter of `update` records, at
the type level, the set of register *names* this update writes. Critically, `w`
is **existentially quantified at the `Edge` record** (see the GADT comment at
`src/Keiki/Core.hs` lines ~564–568): different edges out of one vertex write
different slot sets, so the homogeneous list `[Edge phi rs ci co s]` cannot
expose a per-edge `w` in its type. This matters for M2 and is discussed under
"How to recover written-slot names" below.

**The Mermaid renderer as it stands today.** All rendering lives in one module,
`src/Keiki/Render/Mermaid.hs`. Its current export list (lines ~25–40) is exactly:
`toMermaid`, `toMermaidAlternative`, `toMermaidAlternativeWith`,
`toMermaidComposite`, `toMermaidCompositeNested`, `toMermaidCompose3`,
`toMermaidCompose3Nested`, `toMermaidFeedback1`, `vertexLabel`,
`compositeLabel`, `compose3Label`, `edgeInputName`, `edgeOutputName`,
`edgeLabel`. The single-transducer entry point is

    toMermaid
      :: (Enum s, Bounded s, Show s)
      => SymTransducer (HsPred rs ci) rs s ci co
      -> Text
    toMermaid = renderTopology vertexLabel

`renderTopology` (lines ~458–482, **not** exported) is the shared rendering
core. It walks `[minBound .. maxBound]` over the vertex type, emits the header
line `stateDiagram-v2`, an initial-state line `[*] --> <initial>`, one line per
outgoing edge of every vertex, and a final-state line `<vertex> --> [*]` for
each final vertex. The per-edge line is built (around lines ~470–475) as

    [ ind <> label s <> arrow
          <> label (target e) <> colon <> edgeLabel e
    | s <- vertices
    , e <- edgesOut t s
    ]

Note that the list comprehension binds the whole `Edge` value as `e` and calls
`edgeLabel e`. So `renderTopology` already has each `Edge` in hand — the data
needed for the summary is reachable without changing the enumeration.

`edgeLabel` (lines ~548–555) is

    edgeLabel :: Edge (HsPred rs ci) rs ci co s -> Text
    edgeLabel e =
      let inp = maybe (T.pack "?") id (edgeInputName e)
          out = maybe (T.pack "\x03B5") id (edgeOutputName e)
      in inp <> T.pack " / " <> out

`edgeInputName` (lines ~513–524) walks the guard AST for the leftmost
`PInCtor`'s `icName` and **drops** the other predicate constructors
(`PEq`, `PCmp`, `PTop`, `PBot` — it returns `Nothing` for those). `edgeOutputName`
(lines ~537–545) reads each output term's `wcName`. So today's label uses only
the input constructor name and the output constructor name(s); the guard's
*condition* and the update are entirely absent. The `?` fallback appears when no
`PInCtor` is found; the `ε` fallback (the Greek letter epsilon, `\x03B5`) appears
when `output` is `[]`.

There is **no** options or configuration record anywhere in the module today —
`toMermaidAlternativeWith` takes two bare `Text` arguments (arm names), not a
record. There is **no** atlas / batch entry point. Both are gaps this plan fills.

**The guard AST (`HsPred`) and its tags.** `HsPred rs ci` is defined in
`src/Keiki/Core.hs` (lines ~462–488). Its constructors are: `PTop` (always
true), `PBot` (always false), `PAnd a b`, `POr a b`, `PNot p`, `PEq t1 t2`
(equality of two `Term`s), `PInCtor ic` (true iff the input matches the named
constructor `ic`), and `PCmp cmp t1 t2` (an ordering comparison). The
comparison tag `Cmp` (lines ~497–498) is `CmpLt | CmpLe | CmpGt | CmpGe` and
derives `Show` (so `show CmpGe == "CmpGe"`). The `InCtor`'s only human-readable
field is `icName :: String`; `WireCtor`'s is `wcName :: String`. Everything else
in these types is either a `Term` (which itself can hold opaque functions via
`TApp1`/`TApp2`) or a raw Haskell function. That is why only a *structural*
summary is renderable — see the Decision Log.

**The update language (`Update`).** Defined in `src/Keiki/Core.hs` (lines
~374–380):

    data Update (rs :: [Slot]) (w :: [Symbol]) (ci :: Type) where
      UKeep    :: Update rs '[] ci
      USet     :: KnownSymbol s
               => IndexN s rs r -> Term rs ci r -> Update rs '[s] ci
      UCombine :: Update rs w1 ci
               -> Update rs w2 ci
               -> Update rs (Concat w1 w2) ci

`UKeep` writes nothing. `USet ix term` writes the single slot that `ix` points
at; the `KnownSymbol s` constraint on `USet` is the key to recovering the slot
*name* (below). `UCombine` glues two updates. The update field of an `Edge` is
**never read by the renderer today** — M2 is the first reader.

**How to recover written-slot names (important — refines the MasterPlan
sketch).** The MasterPlan's prose suggested recovering the written-slot set
"from its TYPE-LEVEL write-set `w :: [Symbol]` via `KnownSlotNames`". On reading
the live code, that exact route does not work, for two reasons. First,
`KnownSlotNames` (in `src/Keiki/Core.hs`, lines ~311–319) is indexed by a slot
list `rs :: [Slot]` (i.e. `[(Symbol, Type)]`), not by a bare symbol list
`[Symbol]`; the update's `w` is `[Symbol]`, the wrong kind. Second, and
decisively, `w` is **existentially quantified at the `Edge` record** and carries
no `KnownSlotNames`/`KnownSymbols` dictionary, so there is no class evidence to
invoke even if the kinds matched. The faithful route is to recover the names by
**structural recursion over the `Update` value itself**:

    writtenSlots :: Update rs w ci -> [Text]
    writtenSlots UKeep          = []
    writtenSlots (USet ix _)    = [T.pack (indexNName ix)]
    writtenSlots (UCombine a b) = writtenSlots a ++ writtenSlots b

This works *because* `USet`'s `KnownSymbol s` constraint is brought into scope
by the pattern match, and `indexNName :: KnownSymbol s => IndexN s rs r ->
String` (defined in `src/Keiki/Internal/Slots.hs`, lines ~134–135, as
`indexNName _ = symbolVal (Proxy @s)`) reads the slot name off that evidence. No
type-level `w` machinery is needed; the value carries everything. `indexNName`
is exported by the **exposed** module `Keiki.Internal.Slots` (it is listed in
that module's export list and `Keiki.Internal.Slots` is an `exposed-module` in
`keiki.cabal`), but it is **not** re-exported by `Keiki.Core` (which re-exports
only `IndexN(..)` and `HasIndexN(..)`). So the renderer must add an explicit
`import Keiki.Internal.Slots (indexNName)`.

**The existing regression test.** `test/Keiki/Render/MermaidSpec.hs` pins
canonical Mermaid blocks for several fixtures using
[hspec](https://hspec.github.io/) (the project's test framework — each `it`
clause is one example, `shouldBe` asserts equality). The first describe block
(lines ~67–69) is

    describe "toMermaid (single SymTransducer)" $
      it "renders userReg to the canonical stateDiagram-v2 block" $
        toMermaid userReg `shouldBe` userRegCanonical

and `userRegCanonical` (lines ~104–119) is the expected block, including the
line

    "    PotentialCustomer --> RequiresConfirmation : StartRegistration / RegistrationStarted; ConfirmationEmailSent"

This existing golden is the single most important acceptance gate for M2/M3: it
must keep passing **unchanged** after all additions, which is what proves the
default is byte-identical. The spec module imports the fixture `userReg` from
`Keiki.Fixtures.UserRegistration`; that fixture's `StartRegistration` edge
writes the slots `email`, `confirmCode`, `registeredAt` (via three `USet`s
combined; see `test/Keiki/Fixtures/UserRegistration.hs` around lines ~372–377),
its `ConfirmAccount` edge writes `confirmedAt` and carries a `PEq` guard
(`requireEq d.confirmCode #confirmCode`; lines ~398–399), and its
`FulfillGDPRRequest` edges write `deletedAt`. That gives M3 a concrete fixture
whose annotated golden exercises both written-slots and a guard tag.

**Sibling and parent plans (reference only, do not modify).** The parent
MasterPlan is
`docs/masterplans/13-keiki-api-improvements-surfaced-by-the-rei-migration.md`.
The diagram-pedagogy guide is `docs/guide/deriving-lifecycle-transitions.md`.
The renderer's original MasterPlan is
`docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md`. The sibling
plan `docs/plans/46-document-the-output-invertibility-contract-and-derived-value-modeling-patterns.md`
cross-links the same diagram-pedagogy guide; the integration relationship is
described under "Interfaces and Dependencies".


## Plan of Work

The work is three milestones. M1 (atlas) is fully independent of M2 (summary);
either could land first, but they are ordered atlas-then-summary because the
atlas is the simpler, lower-risk change and gives an early observable win. M3
adds the tests and the docs note that lock both in.

### Milestone M1 — the atlas entry point

Scope: add one exported function to `src/Keiki/Render/Mermaid.hs` that takes a
list of `(label, already-rendered-diagram)` pairs and assembles them into one
document. At the end of M1, a caller can render several transducers (using
whichever single / composite entry point matches each one), pair each result
with a human label, and get one document back. Nothing else in the module
changes; no existing behaviour is touched.

The function and its documentation go near the bottom of the module, after the
existing entry points and before (or after) the label helpers — placement is
cosmetic. Add `toMermaidAtlas` to the module export list (lines ~25–40),
appended after `toMermaidFeedback1` so the renderer entry points stay grouped
ahead of the label helpers.

The intended shape:

    -- | Assemble several already-rendered Mermaid diagrams into one
    -- document, each under a labelled section. Each input pair is
    -- @(sectionLabel, renderedDiagram)@ where @renderedDiagram@ is the
    -- 'Text' produced by any single-transducer or composite renderer in
    -- this module (e.g. 'toMermaid', 'toMermaidComposite'). The label is
    -- emitted verbatim as a Markdown level-2 heading; the diagram is
    -- emitted verbatim inside a fenced @mermaid@ code block so it renders
    -- inline in GitHub / Notion / Markdown previewers.
    --
    -- Transducers are heterogeneously typed (each has its own vertex,
    -- register, input and output types), so a single list of transducers
    -- would not type-check; taking already-rendered 'Text' lets each
    -- caller pick the matching renderer for its own transducer. See the
    -- Decision Log of
    -- @docs/plans/50-mermaid-renderer-atlas-entry-point-and-structural-edge-summary-annotations.md@.
    toMermaidAtlas :: [(Text, Text)] -> Text
    toMermaidAtlas sections =
      T.intercalate (T.pack "\n\n")
        [ T.pack "## " <> label <> T.pack "\n\n"
            <> T.pack "```mermaid\n" <> diagram <> T.pack "\n```"
        | (label, diagram) <- sections
        ]

Design notes the implementer must honour:

* The output is a Markdown document (headings plus fenced ```mermaid blocks),
  not itself a single `stateDiagram-v2` block. That is deliberate: the atlas's
  job is to put many *separate* diagrams on one page, and Mermaid has no
  "several state diagrams in one block" construct, so the natural container is a
  Markdown page with one fenced block per diagram. This matches the existing
  diagram-file convention in `docs/guide/diagrams/` (one fenced ```mermaid block
  per diagram), so atlas output can be pasted straight into such a file.
* An empty input list yields the empty `Text`. A single-element list yields one
  heading and one fenced block. These edge cases need no special-casing —
  `T.intercalate` over a one- or zero-element list already does the right thing —
  but the M3 tests should cover at least the two-element case (the motivating
  one) and may cover the empty case.
* The function does **not** validate or re-parse the diagrams; it treats them as
  opaque `Text`. This keeps it total and trivial.

Commands to run at the end of M1:

    cabal build keiki

Acceptance for M1: feeding `toMermaidAtlas` two `toMermaid` outputs with labels
yields one document that contains both diagrams, each under its label. This is
demonstrated by the M3 atlas golden test, but can be eyeballed earlier in a
REPL (see Concrete Steps).

### Milestone M2 — the opt-in structural edge summary

Scope: introduce an options record and a new entry point that threads it
through, so an edge label can optionally carry a structural suffix. At the end
of M2, a caller can render a transducer with the summary turned on and see a
`[w: …; g: …]` suffix on each edge label; with the default options (or via the
unchanged `toMermaid`), the output is exactly as today.

Steps, concretely:

1. Add the options record and its default near the top of the module, after the
   imports. The record has two `Bool` fields: one to show written slots, one to
   show the guard summary. Keeping them independent lets a caller show only
   writes, only the guard, both, or neither.

        -- | Rendering options for the structural edge-summary suffix. All
        -- fields default to 'False' in 'defaultMermaidOptions', so the
        -- default rendering is byte-identical to 'toMermaid'.
        data MermaidOptions = MermaidOptions
          { showWrittenSlots :: Bool
            -- ^ When 'True', append the update's written-slot names, e.g.
            -- @[w: email; confirmCode; registeredAt]@.
          , showGuardSummary :: Bool
            -- ^ When 'True', append a structural guard summary listing the
            -- guard's constructor / comparison tags, e.g. @[g: PCmp CmpGe]@.
          }

        -- | The default: no summary suffix. @'toMermaid' t@ equals
        -- @'toMermaidWith' 'defaultMermaidOptions' t@.
        defaultMermaidOptions :: MermaidOptions
        defaultMermaidOptions = MermaidOptions
          { showWrittenSlots = False
          , showGuardSummary = False
          }

   Export `MermaidOptions(..)`, `defaultMermaidOptions`, and `toMermaidWith`
   (below) by appending them to the module export list. Exporting the record's
   fields (`(..)`) lets callers both construct via record syntax and read the
   accessors.

2. Add the entry point `toMermaidWith` mirroring `toMermaid`'s signature plus an
   options argument:

        -- | Like 'toMermaid', but takes 'MermaidOptions' controlling the
        -- structural edge-summary suffix. @'toMermaidWith'
        -- 'defaultMermaidOptions'@ is byte-identical to 'toMermaid'.
        toMermaidWith
          :: (Enum s, Bounded s, Show s)
          => MermaidOptions
          -> SymTransducer (HsPred rs ci) rs s ci co
          -> Text
        toMermaidWith opts = renderTopologyWith opts vertexLabel

   Keep `toMermaid` defined as today, but route it through the options path with
   the default so there is one rendering core:

        toMermaid = toMermaidWith defaultMermaidOptions

   This re-definition must produce byte-identical output; the M3 default golden
   proves it.

3. Thread options through the rendering core. Today `renderTopology` calls
   `edgeLabel e`. Add an options-aware sibling. The minimal-churn approach is to
   make the existing private `renderTopology` delegate to a new private
   `renderTopologyWith` that takes `MermaidOptions`:

        renderTopology label = renderTopologyWith defaultMermaidOptions label

        renderTopologyWith
          :: (Enum s, Bounded s)
          => MermaidOptions
          -> (s -> Text)
          -> SymTransducer (HsPred rs ci) rs s ci co
          -> Text
        renderTopologyWith opts label t = …  -- body identical to today's
                                              -- renderTopology, but the edge
                                              -- line calls (edgeLabelWith opts e)
                                              -- instead of (edgeLabel e)

   Leaving `renderTopology` in place (delegating to the default) means the other
   renderers that call it (`toMermaidComposite`, `toMermaidCompose3`,
   `toMermaidFeedback1`, and the inline-bodied `toMermaidCompositeNested` /
   `toMermaidCompose3Nested` / `toMermaidAlternativeWith`) keep their current
   guard-free behaviour with no edits. This plan does **not** extend the summary
   to the composite renderers — that would be additive future work; the
   single-transducer path is what Rei's #5 asked for. Record this scope choice
   in the Decision Log if the implementer is tempted to widen it.

4. Add the summary-aware edge label. Keep `edgeLabel` exactly as today (it is
   exported and other code may use it) and add a private `edgeLabelWith`:

        edgeLabelWith
          :: MermaidOptions
          -> Edge (HsPred rs ci) rs ci co s
          -> Text
        edgeLabelWith opts e =
          let base    = edgeLabel e
              wPart   = if showWrittenSlots opts
                          then writtenSlotsSuffix e else T.empty
              gPart   = if showGuardSummary opts
                          then guardSummarySuffix e else T.empty
              summary = T.concat [wPart, gPart]
          in if T.null summary
               then base
               else base <> T.pack " [" <> T.intercalate (T.pack "; ") parts <> T.pack "]"
                 where parts = filter (not . T.null) [wPartInner, gPartInner]
                       wPartInner = …  -- see below
                       gPartInner = …

   The exact assembly of the suffix is up to the implementer, but it must
   satisfy these properties, which the M3 annotated golden will pin:

   * When neither flag is set, `edgeLabelWith opts e == edgeLabel e` (no
     trailing space, no brackets). This is what keeps the default byte-identical.
   * The written-slots part, when shown, reads `w: <slot1>; <slot2>; …` using
     the names from `writtenSlots (update e)` (see "How to recover written-slot
     names" in Context). For an `UKeep` (no writes) the slot list is empty; the
     implementer chooses whether to render `w:` with an empty list or to omit the
     `w:` part entirely when there are no writes — **omit it** (a `w:` with
     nothing after it is noise), and pin that choice in the golden.
   * The guard part, when shown, reads `g: <tag-summary>` where the tag summary
     is produced by walking the `HsPred` and listing its structural tags — see
     `guardSummary` below. For a guard of `PTop` (the always-true guard that
     `onCmd` does not add a `PInCtor` for — though in practice `onCmd`-built
     edges wrap the guard in `PAnd (PInCtor …) inner`), the implementer chooses
     whether to render `g: PTop` or omit it. **Render the tag list as-is**
     (including `PTop`/`PInCtor`) so the summary is faithful, and pin the
     resulting golden. The point of the summary is fidelity to structure, not
     editorial pruning.
   * When both parts are shown, they are joined by `; ` inside one bracket:
     `[w: …; g: …]`.

   A concrete, simple assembly that meets the above:

        edgeLabelWith opts e =
          let base  = edgeLabel e
              ws    = if showWrittenSlots opts then writtenSlots (update e) else []
              wPart = if null ws
                        then []
                        else [ T.pack "w: " <> T.intercalate (T.pack "; ") ws ]
              gPart = if showGuardSummary opts
                        then [ T.pack "g: " <> guardSummary (guard e) ]
                        else []
              parts = wPart ++ gPart
          in if null parts
               then base
               else base <> T.pack " [" <> T.intercalate (T.pack "; ") parts <> T.pack "]"

   Note: pattern-matching `update e` and `guard e` on an `Edge` is fine despite
   the existential `w` — `update e :: Update rs w ci` for *some* hidden `w`, and
   `writtenSlots` is parametric in `w`, so it accepts it. Likewise `guard e ::
   HsPred rs ci` is fully visible (no existential), so `guardSummary` reads it
   directly.

5. Add the two private helpers `writtenSlots` and `guardSummary`. The first is
   exactly the structural recursion shown in Context ("How to recover
   written-slot names"); it needs `import Keiki.Internal.Slots (indexNName)`.
   The second walks the guard:

        -- | A structural, total summary of a guard predicate: the list of
        -- its constructor tags in left-to-right order, with 'PCmp' carrying
        -- its 'Cmp' direction. This does NOT print the operand 'Term's —
        -- those can hold opaque Haskell functions ('TApp1'/'TApp2') and the
        -- input/output constructors carry unprintable match/build functions
        -- ('icMatch'/'icBuild', 'wcMatch'/'wcBuild'). The summary is the
        -- faithful renderable projection of an otherwise unprintable AST.
        guardSummary :: HsPred rs ci -> Text
        guardSummary = T.intercalate (T.pack " ") . go
          where
            go :: HsPred rs ci -> [Text]
            go PTop          = [T.pack "PTop"]
            go PBot          = [T.pack "PBot"]
            go (PAnd a b)    = T.pack "PAnd" : go a ++ go b
            go (POr  a b)    = T.pack "POr"  : go a ++ go b
            go (PNot p)      = T.pack "PNot" : go p
            go (PEq _ _)     = [T.pack "PEq"]
            go (PInCtor _)   = [T.pack "PInCtor"]
            go (PCmp c _ _)  = [T.pack "PCmp " <> T.pack (show c)]

   The exact rendering (flat space-separated prefix walk vs. some other shape)
   is the implementer's choice as long as it is total, prints no operand terms
   or functions, and the M3 annotated golden pins whatever shape is chosen. The
   `show c` on the `Cmp` is safe — `Cmp` derives `Show` (`src/Keiki/Core.hs`
   line ~498), yielding `CmpLt`/`CmpLe`/`CmpGt`/`CmpGe`. A reasonable simpler
   alternative the implementer may prefer: emit only the *atomic* tags
   (`PInCtor`, `PEq`, `PCmp <dir>`) and skip the boolean-connective tags
   (`PAnd`/`POr`/`PNot`) to keep the suffix short; if so, pin that in the golden
   and note it in the Decision Log. Either is acceptable; fidelity to structure
   (no operand terms, no functions) is the hard requirement.

Commands to run at the end of M2:

    cabal build keiki

Acceptance for M2: with `showWrittenSlots = True` and/or
`showGuardSummary = True`, the edge label shows the structural suffix; with
`defaultMermaidOptions` (or via `toMermaid`), the label is unchanged. The M3
goldens prove both directions.

### Milestone M3 — tests and docs

Scope: lock both additions with regression tests in
`test/Keiki/Render/MermaidSpec.hs`, and add a short note to the user-facing docs
describing both additions and the deliberate guard-free default. At the end of
M3, `cabal test` proves the default is byte-identical, the annotated variant
shows the summary, and the atlas assembles a labelled document.

Three new goldens, added as new describe blocks to the existing spec module
(following the module's established "one describe block per renderer, expected
strings inline at module scope" convention — see
`docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md` IP-4):

1. **Default-is-byte-identical golden (the critical one).** The existing
   describe block already asserts `toMermaid userReg == userRegCanonical`. Keep
   it untouched — its continued passing *is* the byte-identical proof. As a
   belt-and-braces addition, also assert that the explicit default path matches:

        describe "toMermaidWith defaultMermaidOptions (byte-identical default)" $
          it "equals toMermaid userReg exactly" $
            toMermaidWith defaultMermaidOptions userReg `shouldBe` toMermaid userReg

   This second assertion guards against a future refactor that changes
   `toMermaid` and `toMermaidWith` divergently.

2. **Annotated-variant golden.** Render `userReg` with both flags on and pin the
   block. The implementer captures the actual output (per the module's
   "output is source of truth" convention noted in MasterPlan-10's Surprises)
   and pastes it verbatim. The expected block differs from `userRegCanonical`
   only by the bracketed suffixes; for example the `StartRegistration` line
   becomes

        "    PotentialCustomer --> RequiresConfirmation : StartRegistration / RegistrationStarted; ConfirmationEmailSent [w: email; confirmCode; registeredAt; g: PAnd PInCtor PTop]"

   and the `ConfirmAccount` line gains `[w: confirmedAt; g: PAnd PInCtor PEq]`
   (the exact guard-tag spelling depends on how `onCmd` wraps the guard and on
   the `guardSummary` shape chosen in M2 — the implementer pins the *captured*
   output, not a guessed one). The shape is

        describe "toMermaidWith (annotated edge summary)" $
          it "renders userReg with written-slot and guard-summary suffixes" $
            toMermaidWith
              (MermaidOptions { showWrittenSlots = True, showGuardSummary = True })
              userReg
              `shouldBe` userRegAnnotatedCanonical

   Important: do **not** hand-compute the guard tags from the builder source;
   capture them from running the renderer, because the precise `HsPred` shape
   `onCmd` produces (it wraps in `PAnd (PInCtor …) inner`) determines the tag
   list. The Concrete Steps section gives the REPL recipe to capture it.

3. **Atlas golden.** Feed two rendered diagrams with labels and pin the
   document. Reuse `userReg` and the composite fixture
   `compose alertSource emailDelivery` (already imported by the spec module) so
   no new fixtures are needed:

        describe "toMermaidAtlas (multi-diagram document)" $
          it "assembles two labelled diagrams into one document" $
            toMermaidAtlas
              [ (T.pack "User registration", toMermaid userReg)
              , (T.pack "Alert ⨾ Email",     toMermaidComposite (compose alertSource emailDelivery))
              ]
              `shouldBe` atlasCanonical

   where `atlasCanonical` is the captured document: two `## ` headings, each
   followed by a fenced ```mermaid block containing the respective diagram.
   Capture it from the REPL rather than hand-typing the fences.

Then add a short docs note. Two acceptable homes; pick one:

* Append a subsection to whichever user-guide page documents the Mermaid
  renderer, **or**
* Add a short note in `docs/guide/` (a new short page or an existing rendering
  page).

Determine the home by searching `docs/guide/` for the existing Mermaid
documentation (`grep -rl "toMermaid" docs/guide`) and extend the page that
already covers the renderer. The note must say, in prose: (a) `toMermaidAtlas`
assembles already-rendered diagrams into one labelled Markdown document, and why
it takes `(label, Text)` pairs rather than transducers (heterogeneous types);
(b) `toMermaidWith`/`MermaidOptions` add an opt-in structural edge summary
(written slots and a guard-tag summary), and that the summary is structural —
not a full AST dump — because the guard/update ASTs carry unprintable functions;
and (c) the default (`toMermaid`) stays guard-free **on purpose**, with an
explicit pointer to `docs/guide/deriving-lifecycle-transitions.md` whose
bug-spotting technique relies on it. This last sentence is the soft-alignment
contract with the sibling EP-46 (see Interfaces and Dependencies).

Commands to run at the end of M3:

    cabal test keiki-test

Acceptance for M3: all goldens pass, including the pre-existing
`userRegCanonical` golden unchanged. See Validation and Acceptance for the exact
expected output.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki`.

**Step 0 — confirm the baseline builds and tests pass before any change.**

    cabal build keiki
    cabal test keiki-test

Expected: the library builds; the test suite reports some number of examples and
`0 failures`. Record the example count here when you run it (it is the M0
baseline). The exact count is whatever the current tree reports; the important
invariant is `0 failures`.

**Step 1 — implement M1 (atlas), then build.**

Edit `src/Keiki/Render/Mermaid.hs`: add `toMermaidAtlas` to the export list and
define it as in the Plan of Work. Then:

    cabal build keiki

Expected: clean build, no warnings about the new export (the module is built
with `-Wall` via the `warnings` import in `keiki.cabal`; an unused-import or
missing-export warning would fail the build, so a clean build confirms the
export is wired correctly).

Eyeball it in the REPL:

    cabal repl keiki-test

then at the `ghci>` prompt:

    ghci> import qualified Data.Text.IO as TIO
    ghci> import Keiki.Render.Mermaid
    ghci> import Keiki.Fixtures.UserRegistration (userReg)
    ghci> import Data.Text (pack)
    ghci> TIO.putStrLn (toMermaidAtlas [(pack "Demo", toMermaid userReg)])

Expected output (a Markdown heading, a fenced block, the diagram inside):

    ## Demo

    ```mermaid
    stateDiagram-v2
        [*] --> PotentialCustomer
        PotentialCustomer --> RequiresConfirmation : StartRegistration / RegistrationStarted; ConfirmationEmailSent
        RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed
        RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent
        RequiresConfirmation --> Deleted : FulfillGDPRRequest / ε
        Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted
        Deleted --> [*]
    ```

**Step 2 — implement M2 (summary), then build.**

Edit `src/Keiki/Render/Mermaid.hs`: add `import Keiki.Internal.Slots
(indexNName)`; add `MermaidOptions(..)`, `defaultMermaidOptions`,
`toMermaidWith` to the export list; add the record, the default, the
`toMermaidWith`/`renderTopologyWith`/`edgeLabelWith`/`writtenSlots`/`guardSummary`
definitions; re-define `toMermaid = toMermaidWith defaultMermaidOptions` and
`renderTopology = renderTopologyWith defaultMermaidOptions`. Then:

    cabal build keiki

Eyeball the annotated render and capture the exact suffix shape (needed for the
M3 golden):

    cabal repl keiki-test
    ghci> import qualified Data.Text.IO as TIO
    ghci> import Keiki.Render.Mermaid
    ghci> import Keiki.Fixtures.UserRegistration (userReg)
    ghci> TIO.putStrLn (toMermaidWith (MermaidOptions True True) userReg)

Expected: the same block as the default plus a `[w: …; g: …]` suffix on each
non-trivial edge line. Copy the exact lines into `userRegAnnotatedCanonical` —
do not retype them. Also confirm the default is unchanged:

    ghci> toMermaidWith defaultMermaidOptions userReg == toMermaid userReg
    True

**Step 3 — implement M3 (tests + docs).**

Add the three describe blocks and the inline expected `Text` values to
`test/Keiki/Render/MermaidSpec.hs` (importing `toMermaidAtlas`, `toMermaidWith`,
`MermaidOptions(..)`, `defaultMermaidOptions` from `Keiki.Render.Mermaid`, and
`pack` from `Data.Text` if not already imported). Capture the atlas and
annotated goldens from the REPL as in Step 2. Add the docs note to the
renderer's user-guide page. Then run the suite:

    cabal test keiki-test

Expected: every example passes, `0 failures`, and the example count is the M0
baseline plus the new examples (one per new `it`).


## Validation and Acceptance

The acceptance is behavioural and proven by `cabal test keiki-test`.

**The single most important acceptance:** the pre-existing
`userRegCanonical` golden — the describe block
`"toMermaid (single SymTransducer)"` asserting
`toMermaid userReg \`shouldBe\` userRegCanonical` — **passes unchanged** after
all additions. Because that golden pins the byte-exact default output, its
continued passing proves the default is byte-identical to today. If any M2 edit
accidentally changes the default label, this test fails first. To make the proof
active rather than passive, the implementer should, before committing, transiently
flip a default in `defaultMermaidOptions` to `True`, run `cabal test keiki-test`,
observe this golden fail with a diff showing the unwanted suffix, then revert. A
clean run after revert confirms the default is genuinely guard-free.

**M1 — atlas behaviour.** The `toMermaidAtlas` golden asserts that feeding two
`(label, rendered)` pairs yields one document with both diagrams under their
labels. Expected document shape (the exact bytes are captured into
`atlasCanonical`):

    ## User registration

    ```mermaid
    stateDiagram-v2
        [*] --> PotentialCustomer
        PotentialCustomer --> RequiresConfirmation : StartRegistration / RegistrationStarted; ConfirmationEmailSent
        RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed
        RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent
        RequiresConfirmation --> Deleted : FulfillGDPRRequest / ε
        Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted
        Deleted --> [*]
    ```

    ## Alert ⨾ Email

    ```mermaid
    stateDiagram-v2
        [*] --> AlertQuiescent_EmailPending
        AlertQuiescent_EmailPending --> AlertEmitted_EmailSentVertex : TriggerAlert / EmailSent
        AlertEmitted_EmailSentVertex --> [*]
    ```

The acceptance is that both `stateDiagram-v2` sub-blocks appear, each under its
`## ` heading, separated by a blank line — i.e. one page carries both diagrams.

**M2 — annotated-summary behaviour.** The `toMermaidWith` annotated golden
asserts that with both flags on, each edge label carries the structural suffix.
The expected annotated line shape (illustrative; the implementer pins the
*captured* tags):

    stateDiagram-v2
        [*] --> PotentialCustomer
        PotentialCustomer --> RequiresConfirmation : StartRegistration / RegistrationStarted; ConfirmationEmailSent [w: email; confirmCode; registeredAt; g: PAnd PInCtor PTop]
        RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed [w: confirmedAt; g: PAnd PInCtor PEq]
        RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent [w: confirmCode; registeredAt; g: PAnd PInCtor PTop]
        RequiresConfirmation --> Deleted : FulfillGDPRRequest / ε [w: deletedAt; g: PAnd PInCtor PTop]
        Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted [w: deletedAt; g: PAnd PInCtor PTop]
        Deleted --> [*]

The acceptance is twofold: (a) the written-slot names match each edge's update
(e.g. `email; confirmCode; registeredAt` for `StartRegistration`,
`confirmedAt` for `ConfirmAccount`), and (b) the guard summary shows only
structural tags (`PAnd`, `PInCtor`, `PEq`/`PCmp …`, `PTop`) and **never** any
operand term, register value, or function. The exact guard-tag spelling is
whatever the captured output shows — the value above is a faithful illustration,
not a hand-derived spec; the test pins the captured bytes.

**M2 — default-unchanged behaviour.** The added assertion
`toMermaidWith defaultMermaidOptions userReg \`shouldBe\` toMermaid userReg`
proves the explicit-default path equals the implicit one.

**M3 — docs.** After the docs note lands, the renderer's user-guide page
describes `toMermaidAtlas` and `toMermaidWith`/`MermaidOptions`, states that the
summary is structural (not a full AST dump) and why, and explicitly says the
default stays guard-free with a pointer to
`docs/guide/deriving-lifecycle-transitions.md`. This is verifiable by reading
the page.

Interpreting results: hspec prints one line per example with a green check or
red `✗`; a failing golden prints the expected-vs-actual diff. Success is
`N examples, 0 failures` with `N` equal to the M0 baseline plus the number of
new `it` clauses added in M3.


## Idempotence and Recovery

Every step is additive and safe to repeat. Re-running `cabal build keiki` or
`cabal test keiki-test` is idempotent. The code edits are append-mostly: the
only existing definitions touched are `toMermaid` (re-pointed at
`toMermaidWith defaultMermaidOptions`) and `renderTopology` (re-pointed at
`renderTopologyWith defaultMermaidOptions`); both re-definitions are required to
preserve byte-identical output, which the default golden verifies — so if a
re-definition is wrong, the test fails loudly rather than drifting silently.

If the annotated or atlas golden mismatches because the captured output differs
from a hand-typed expectation, the recovery is to re-capture the actual output
from the REPL recipe in Concrete Steps and paste it verbatim — the renderer is
the source of truth, never the hand-typed string. If a build fails on the new
`Keiki.Internal.Slots` import, confirm the import names exactly `indexNName`
(not `slotNameN` or similar) and that `Keiki.Internal.Slots` is the
`exposed-module` providing it (it is, per `keiki.cabal`).

To roll back entirely: revert `src/Keiki/Render/Mermaid.hs` and
`test/Keiki/Render/MermaidSpec.hs` and delete the docs-note edit. Because the
changes are additive and the default is byte-identical, a revert leaves the tree
exactly as it was — no migration, no data, no destructive operation is involved.


## Interfaces and Dependencies

**Module ownership.** This plan **owns all edits to**
`src/Keiki/Render/Mermaid.hs`. No other plan in MasterPlan-13 touches that file.
Within the module, this plan adds the exports `toMermaidAtlas`, `toMermaidWith`,
`MermaidOptions(..)`, and `defaultMermaidOptions`, and the private helpers
`renderTopologyWith`, `edgeLabelWith`, `writtenSlots`, `guardSummary`; it
re-points `toMermaid` and `renderTopology` at their options-aware cores without
changing their observable behaviour.

**Libraries and modules used, and why.**

* `Data.Text` / `Data.Text.IO` (the `text` package, already a dependency per
  `keiki.cabal`) — all rendering is `Text`; the atlas concatenates `Text`.
* `Keiki.Core` (`src/Keiki/Core.hs`) — provides `SymTransducer`, `Edge(..)`,
  `HsPred(..)`, `Cmp(..)`, `Update(..)`, `InCtor(..)`, `WireCtor(..)`,
  `OutTerm(..)` already imported by the module. The summary reads `update e` and
  `guard e` off `Edge`, walks `Update` (`UKeep`/`USet`/`UCombine`) and `HsPred`
  (`PTop`/`PBot`/`PAnd`/`POr`/`PNot`/`PEq`/`PInCtor`/`PCmp`), and `show`s `Cmp`.
* `Keiki.Internal.Slots` (`src/Keiki/Internal/Slots.hs`) — provides
  `indexNName :: KnownSymbol s => IndexN s rs r -> String`, the only way to
  recover a written slot's *name* from a `USet`. This is a **new import** for
  the renderer module; `Keiki.Internal.Slots` is an exposed module so the import
  is allowed. `Keiki.Core` does **not** re-export `indexNName`, so the direct
  import is necessary.

**Signatures that must exist at the end of each milestone.**

* End of M1: `toMermaidAtlas :: [(Text, Text)] -> Text`, exported from
  `Keiki.Render.Mermaid`.
* End of M2: `data MermaidOptions = MermaidOptions { showWrittenSlots :: Bool,
  showGuardSummary :: Bool }`; `defaultMermaidOptions :: MermaidOptions`;
  `toMermaidWith :: (Enum s, Bounded s, Show s) => MermaidOptions ->
  SymTransducer (HsPred rs ci) rs s ci co -> Text` — all exported from
  `Keiki.Render.Mermaid`; and `toMermaid t == toMermaidWith defaultMermaidOptions t`
  for all `t`.
* End of M3: three new describe blocks in `test/Keiki/Render/MermaidSpec.hs`
  (default-identity, annotated, atlas) and a docs note on the renderer's
  user-guide page.

**Integration with sibling plans (EP-50 ↔ EP-46).** The sibling plan
`docs/plans/46-document-the-output-invertibility-contract-and-derived-value-modeling-patterns.md`
cross-links the same diagram-pedagogy guide
`docs/guide/deriving-lifecycle-transitions.md`. That guide's bug-spotting
pedagogy depends on `toMermaid`'s default label format being **guard-free** (two
edges differing only by an unshown guard look identical, making a missing edge
obvious). This plan therefore carries a hard constraint: `toMermaid`'s default
output must stay guard-free, byte-for-byte, which the M3 default golden enforces.
There is **no hard code dependency** between EP-50 and EP-46 — neither edits the
other's files. The relationship is a **soft alignment** on the default label
format: as long as this plan keeps the default guard-free (proven by the
golden), the guide that EP-46 cross-links stays correct, and EP-46 needs no
coordination with this plan. Either plan may land first.

**Relationship to MasterPlan-10.** The renderer's original MasterPlan,
`docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md`, deliberately
scoped guard/update visualisation **out** of v1 (Decision Log, 2026-05-02) but
explicitly left the door open for a "labelled by guard summary" variant
(Vision & Scope, "Out of scope" / "the design milestone may revisit"). This plan
realises that variant as the opt-in `toMermaidWith` summary, honouring the
original rejection of *full* AST in labels while adding the *summary* the door
was left open for. MasterPlan-10's IP-1 (the `Keiki.Render.Mermaid` module) and
IP-4 (the `MermaidSpec.hs` regression file) are the integration points this plan
extends: new exports added without renaming or removing existing ones, new
describe blocks added to the same spec file.
