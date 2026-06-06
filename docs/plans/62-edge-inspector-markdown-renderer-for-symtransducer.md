---
id: 62
slug: edge-inspector-markdown-renderer-for-symtransducer
title: "Edge inspector Markdown renderer for SymTransducer"
kind: exec-plan
created_at: 2026-06-06T15:47:42Z
intention: "intention_01ktes9wvkekw8nbb69st0naj8"
master_plan: "docs/masterplans/15-keiki-mermaid-diagram-and-documentation-rendering-improvements-surfaced-by-the-seihou-diagram-audit.md"
---

# Edge inspector Markdown renderer for SymTransducer

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This library, **keiki**, models event-sourcing workflows as *symbolic-register transducers*: a
finite control graph (states and edges) over a register file, defined by the `SymTransducer` type
in `src/Keiki/Core.hs`. keiki already renders such a transducer to a Mermaid `stateDiagram-v2`
*topology diagram* via `toMermaid` in `src/Keiki/Render/Mermaid.hs`. That diagram is good for
seeing the *shape* of a workflow (which states connect to which, on which command, emitting which
event), but it is a poor place to read *detail*: a Mermaid edge label is one line of text, so
everything an auditor wants to know about an edge — its guard, the registers it writes, the fields
of the event it emits — has to be crammed into that single label or left out.

After this change a user can call a new function, `renderEdgeInspector`, on the **same**
`SymTransducer` value they already pass to `toMermaid`, and get back a deterministic **Markdown**
document that lays out every edge in full. Edges are grouped under a heading per source state, and
each edge shows its source state, target state, edge index, input (command) constructor, output
(event) constructor(s), the guard predicate, and the register slots the edge writes. An auditor or
documentation author reading the generated Markdown can answer "what does the
`RequiresConfirmation -> Confirmed` transition actually do?" without decoding a dense diagram label
or reading the Haskell source.

You can see it working by running the test suite: a golden test pins the exact Markdown produced
for a real multi-edge fixture transducer (`Keiki.Fixtures.UserRegistration.userReg`), so
`cabal test keiki-test` both proves the renderer compiles and shows, byte for byte, the document a
human would read. The renderer is *pure* (no solver, no IO): it walks the transducer's edges and
emits `Data.Text.Text`, exactly like the Mermaid renderer it sits beside.

This plan delivers **Requirement 3** of MasterPlan 15
(`docs/masterplans/15-keiki-mermaid-diagram-and-documentation-rendering-improvements-surfaced-by-the-seihou-diagram-audit.md`,
see its Vision & Scope bullet for "renderEdgeInspector" at lines 46-49 of that file).


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

Milestone 1 (core inspector + golden):

- [x] Create `src/Keiki/Render/Inspector.hs` with `EdgeInspectorOptions`, `defaultEdgeInspectorOptions`, and `renderEdgeInspector`. (2026-06-06)
- [x] Decide and record: reuse vs replicate the Mermaid helpers. Reused exported `edgeInputName`; defined a local Markdown-safe `outputName` (not `edgeOutputName`, which emits `<br/>` for 3+); replicated the unexported `guardSummary`/`writtenSlots`. (2026-06-06)
- [x] Add `Keiki.Render.Inspector` to `keiki.cabal` `library: exposed-modules`. (2026-06-06)
- [x] Confirm the library builds: `cabal build keiki`. (2026-06-06)
- [x] Create `test/Keiki/Render/InspectorSpec.hs` with a golden over `Keiki.Fixtures.UserRegistration.userReg`. (2026-06-06)
- [x] Add `Keiki.Render.InspectorSpec` to `keiki.cabal` `test-suite keiki-test: other-modules`. (2026-06-06)
- [x] Add the import + `describe` for the inspector spec to `test/Spec.hs`. (2026-06-06)
- [x] Confirm the suite passes: `cabal test keiki-test` (346 examples, 0 failures). (2026-06-06)

Milestone 2 (pretty guard + output-field terms):

- [x] Wire `includePrettyGuard` to `Keiki.Render.Pretty.prettyPred` (EP-61 is merged, so done directly, not deferred). (2026-06-06)
- [x] Wire `includeOutputFields` to `Keiki.Render.Pretty.prettyTerm`, rendering each output field's term positionally, grouped by output constructor. (2026-06-06)
- [x] Add golden cases that exercise both options; full suite passes (346 examples, 0 failures). (2026-06-06)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- EP-61 was already merged when this plan ran, so M1 and M2 were implemented together
  in one pass; the EP-61 fallback path (ship M1 with the pretty options as no-ops) was
  never needed. Both `includePrettyGuard` and `includeOutputFields` reuse
  `Keiki.Render.Pretty` (`prettyPred`/`prettyTerm`) directly, exactly as the
  Integration Points require.
- The `includeOutputFields` rendering is more informative than the plan's prose
  predicted, because `prettyTerm` distinguishes the two term sources. For `userReg`'s
  `ConfirmAccount -> Confirmed` edge the `AccountConfirmed` event's fields render as
  `field 0: email; field 1: ConfirmAccount.confirmCode; field 2: ConfirmAccount.at` —
  field 0 is a *register* read (`email`, no constructor prefix), while fields 1–2 are
  *input-field* reads (`ConfirmAccount.<field>`). So the inspector visibly shows which
  output fields come from stored state vs. the incoming command — a free benefit of
  reusing the EP-61 pretty-printer.
- Confirmed the `WireCtor`-has-no-field-names limitation in the rendered output: every
  output field is labelled `field 0`, `field 1`, … positionally, never by a wire field
  name, because `WireCtor` carries only `wcName` (`src/Keiki/Core.hs:479-483`). This is
  exactly the Decision Log / MasterPlan-15 finding, now visible in the golden.
- Chose a local `outputName` over reusing the exported `edgeOutputName`: the latter
  joins three-or-more outputs with the Mermaid diagram line-break `<br/>`
  (`src/Keiki/Render/Mermaid.hs:600`), which would be wrong inside a Markdown bullet.
  The local version joins all multi-output cases with `"; "`. For `userReg` (max two
  outputs per edge) the rendered bytes are identical either way, but the local version
  is Markdown-correct for transducers with 3+ outputs per edge.


## Decision Log

Record every decision made while working on the plan.

- Decision: Put the inspector in a **new** module `src/Keiki/Render/Inspector.hs`, separate from
  `src/Keiki/Render/Mermaid.hs`.
  Rationale: it is a different output surface — a Markdown *detail* document, not a Mermaid *diagram*
  label. The two share input (a `SymTransducer` value) but nothing about output formatting. Keeping
  them apart means the inspector's acceptance and golden are independent of the Mermaid goldens, and
  the byte-identity constraint on the Mermaid default output (MasterPlan 15, lines 64-69) is never
  at risk from inspector changes. MasterPlan 15 already mandates this split (Decomposition Strategy,
  lines 102-106: "It is a separate stream … because it is a different output surface").
  Date: 2026-06-06

- Decision: Define an edge's **edge index** as its positional index in the list
  `edgesOut t s` (i.e. `zip [0..] (edgesOut t s)`), 0-based.
  Rationale: this is exactly how `checkHiddenInputs` in `src/Keiki/Core.hs` numbers edges — see
  `Core.hs:1027` (`case zip [0 ..] (edgesOut t s) of …`) which feeds `edgeIndex` of the `EdgeRef`
  diagnostic record (`Core.hs:972`). Using the same numbering means an inspector edge index and a
  `checkHiddenInputs` diagnostic refer to the same edge, so the two tools are cross-consistent.
  Date: 2026-06-06

- Decision: `includeOutputFields` renders each output field's *term* **positionally**, not by field
  name; it cannot show output-field names.
  Rationale: an edge's output is a list of `OutTerm` values, each an `OPack inCtor wireCtor outFields`
  (`Core.hs:522-536`). The output constructor's wire tag is `WireCtor` (`Core.hs:478-482`), which
  carries only `wcName :: String`, `wcMatch`, `wcBuild` — there is **no list of output field names**.
  So we can show the output *constructor* name (`wcName`) and the *input* constructor name
  (`icName` of the `OPack`'s `InCtor`), and we can pretty-print each field's `Term`, but we can only
  label fields by position ("field 0", "field 1", …), never by a wire field name. This corrects the
  keiro-runtime-jitsurei audit's Req 3 assumption that fields could be named. (MasterPlan 15 records the same finding
  in its Surprises section, lines 263-265.)
  Date: 2026-06-06

- Decision: (confirmed during M1) Reuse vs replicate the Mermaid helpers — final choice:
  **import `edgeInputName`** (already exported, pure), **replicate `guardSummary` and
  `writtenSlots`** locally (they are not exported; each is a short total function), and **do not
  reuse `edgeOutputName`** — instead define a local `outputName` that joins multi-output edges with
  `"; "` rather than the Mermaid `<br/>` (a diagram-only line break that would corrupt a Markdown
  bullet for 3+ outputs).
  Rationale: this keeps the inspector self-contained, leaves `Keiki.Render.Mermaid` completely
  untouched (so its load-bearing byte-identity is never at risk), and makes the output
  Markdown-correct for any edge fan-out. The two replicated helpers walk fixed ASTs and are unlikely
  to drift; they are kept byte-identical to `Mermaid.hs:649-652` / `Mermaid.hs:662-673`.
  Date: 2026-06-06

- Decision: Soft-depend on EP-61
  (`docs/plans/61-pretty-printer-for-hspred-term-update-and-domain-readable-mermaid-guard-rendering.md`),
  which creates `src/Keiki/Render/Pretty.hs` exporting `prettyPred :: HsPred rs ci -> Text` and
  `prettyTerm :: Term rs ci ifs r -> Text`. `includePrettyGuard` and `includeOutputFields` must
  *import and reuse* those, never re-implement guard/term prettifying.
  Rationale: MasterPlan 15 makes the pretty-printer the single shared readable-guard vocabulary
  (Integration Points, lines 202-208) so the topology renderer and the inspector agree byte for byte.
  Fallback if EP-61 is not yet merged when this plan is implemented: ship M1 (structural guard only)
  and treat `includePrettyGuard`/`includeOutputFields` as no-ops (render nothing extra, or fall back
  to the structural guard summary), then add the pretty rendering in M2 once `Keiki.Render.Pretty`
  exists. The fallback is spelled out in the Plan of Work.
  Date: 2026-06-06


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

EP-62 is complete; M1 and M2 landed together (EP-61 was already merged). Full suite is
green at 346 examples, 0 failures.

- **Delivered.** `src/Keiki/Render/Inspector.hs` exports `EdgeInspectorOptions`,
  `defaultEdgeInspectorOptions`, and `renderEdgeInspector`. Calling
  `renderEdgeInspector defaultEdgeInspectorOptions userReg` produces a deterministic
  Markdown document: a `# Edge inspector` title, a `### <state>` section per source
  state with outgoing edges (in `[minBound .. maxBound]` order; states with no edges,
  like `Deleted`, produce no section), and one bullet block per edge showing source →
  target, 0-based edge index, input constructor, output constructor(s), structural
  guard, and written slots. The ε-edge renders `ε`; the self-loop and delete edge carry
  indices 1 and 2 straight from `edgesOut` order.
- **The two pretty options work** by reusing `Keiki.Render.Pretty`:
  `includePrettyGuard` adds a `guard (pretty)` bullet beside the structural one (e.g.
  `(ConfirmAccount && ConfirmAccount.confirmCode == confirmCode)`), and
  `includeOutputFields` adds an `output fields` bullet listing each output's field terms
  positionally, grouped by output constructor. Three golden cases pin the default, the
  pretty-guard, and the output-fields documents.
- **Goal met.** An auditor can now answer "what does the `RequiresConfirmation →
  Confirmed` transition actually do?" from the generated Markdown alone — guard,
  written registers, and (optionally) the event-field provenance — without decoding a
  dense Mermaid label or reading Haskell. The inspector is rendered from the same
  `userReg` value as the Mermaid golden, so the two are diffable.
- **No regressions / no Mermaid edits.** The plan's preferred path (leave
  `Keiki.Render.Mermaid` untouched, replicate the two unexported helpers) held: no
  existing golden changed, and the byte-identity invariant on the Mermaid default output
  was never at risk.
- **Lesson.** Reusing the EP-61 pretty-printer paid off twice over: it gave identical
  readable-guard text across the topology renderer and the inspector (the whole point of
  the shared module), and its term-level distinction between register reads and
  input-field reads made `output fields` more informative than the plan anticipated.


## Context and Orientation

You are working in the keiki library at `/Users/shinzui/Keikaku/bokuno/keiki`. It is a pure-Haskell
(GHC2024) library; rendering code is pure (no IO, no SMT solver). All commands below run from the
repository root `/Users/shinzui/Keikaku/bokuno/keiki`.

### The transducer model (define the terms)

A **`SymTransducer`** (defined at `src/Keiki/Core.hs:666-671`) is the single source of truth for a
workflow. In plain language it is a finite directed graph whose nodes are *states* and whose arrows
are *edges*, plus a *register file* (named mutable slots) that edges may update. Its fields are:

```haskell
data SymTransducer phi rs s ci co = SymTransducer
  { edgesOut    :: s -> [Edge phi rs ci co s]  -- the outgoing edges of a state
  , initial     :: s                           -- the start state
  , initialRegs :: RegFile rs                  -- initial register values
  , isFinal     :: s -> Bool                   -- which states are terminal
  }
```

The type parameters are: `phi` the guard-predicate carrier, `rs` the register slot list, `s` the
state (vertex) type, `ci` the input symbol type (commands), `co` the output symbol type (events).
keiki's standard guard carrier is `HsPred rs ci`, so the transducers this plan renders have type
`SymTransducer (HsPred rs ci) rs s ci co`.

An **`Edge`** (a GADT at `src/Keiki/Core.hs:654-661`) is one transition:

```haskell
data Edge phi rs ci co s where
  Edge ::
    { guard  :: phi                 -- when this edge is enabled
    , update :: Update rs w ci      -- how it rewrites the register file (w EXISTENTIAL)
    , output :: [OutTerm rs ci co]  -- the events it emits
    , target :: s                   -- the state it moves to
    } -> Edge phi rs ci co s
```

The **guard** `phi` is an `HsPred rs ci` (the predicate AST at `src/Keiki/Core.hs:544-574`):
`PTop`/`PBot` (true/false), `PAnd`/`POr`/`PNot` (boolean structure), `PEq` (term equality),
`PInCtor` (the input is a named command constructor), and `PCmp` (ordering). The leftmost `PInCtor`
in a guard names the command (input constructor) that fires the edge; that is how the renderer
recovers the input-constructor name.

The **output** is a list of `OutTerm` values. Each `OutTerm` (`src/Keiki/Core.hs:522-536`) is a
single constructor `OPack`:

```haskell
data OutTerm rs ci co where
  OPack :: InCtor ci ifs -> WireCtor co fields -> OutFields rs ci ifs fields -> OutTerm rs ci co
```

`OPack` ties together: the **`InCtor`** (`src/Keiki/Core.hs:363-370`) describing the *input*
constructor the edge consumes (its `icName :: String` is the command name); the **`WireCtor`**
(`src/Keiki/Core.hs:478-482`) describing the *output* event constructor (its `wcName :: String` is
the event name); and the **`OutFields`** (`src/Keiki/Core.hs:494-499`) — an HList of `Term`s, one
per field of the event constructor:

```haskell
data OutFields rs ci ifs fs where
  OFNil  :: OutFields rs ci ifs ()
  OFCons :: Term rs ci ifs f -> OutFields rs ci ifs fs -> OutFields rs ci ifs (f, fs)
```

The crucial limitation for this plan: **`WireCtor` carries only `wcName`, no list of field names**
(`src/Keiki/Core.hs:478-482`). So the inspector can show the output *constructor* name and can
pretty-print each output field *term*, but it can only label those fields by *position* (0, 1, …),
never by a wire field name. This is recorded in the Decision Log and in MasterPlan 15's Surprises
(lines 263-265).

The **`update`** is an `Update rs w ci` (`src/Keiki/Core.hs:444-456`): `UKeep` (write nothing),
`USet ix term` (write one slot named by the index `ix`), or `UCombine a b` (do both). The written
slot names are recovered by walking this value.

### The existential-`w` gotcha (read this carefully)

In the `Edge` GADT, `update :: Update rs w ci` has `w` **existentially quantified** — `w` does not
appear in `Edge`'s own type (`src/Keiki/Core.hs:646-661` explains why: different edges write
different slot sets but share one `Edge` type). A consequence GHC enforces: **you cannot apply the
`update` record selector as a function** (it would let the hidden `w` escape; GHC rejects with
"escaped type variable", issue GHC-55876). You must **pattern-match the `Edge` constructor** to get
at `update`, binding it in a `case`/function pattern:

```haskell
case e of
  Edge { guard = g, update = u, output = outs, target = t } -> ...
```

The existing renderer does exactly this: `edgeLabelWith` at `src/Keiki/Render/Mermaid.hs:626`
matches `Edge { update = u, guard = g }`. `Core.hs:689-697` provides `applyEdgeUpdate` /
`edgeReadsInput` as the same existential-hiding pattern. Your inspector code must follow suit
wherever it needs `update` (the written-slot listing). Reading `guard`, `output`, and `target` via
their selectors is fine — only `update` is the problem.

### The existing Mermaid renderer and its helpers

`src/Keiki/Render/Mermaid.hs` is the existing renderer. Read its module header export list at
`src/Keiki/Render/Mermaid.hs:25-44` to see what is exported. Relevant facts you will rely on:

- `toMermaid :: (Enum s, Bounded s, Show s) => SymTransducer (HsPred rs ci) rs s ci co -> Text`
  (`Mermaid.hs:97-101`) — the entry point your inspector parallels. Note the class constraints
  `Enum s, Bounded s, Show s` on the state type; the inspector needs the same.
- `renderTopologyWith` (`Mermaid.hs:515-540`) — the enumeration idiom you will reuse: it binds
  `vertices = [minBound .. maxBound]` and, for each vertex `s`, walks `edgesOut t s`. Your inspector
  groups by source state the same way: iterate `[minBound .. maxBound]`, and for each state render
  its outgoing edges.
- `edgeInputName :: Edge (HsPred rs ci) rs ci co s -> Maybe Text` (`Mermaid.hs:571-582`) — walks the
  guard for the leftmost `PInCtor` and returns its `icName`; `Nothing` if the guard has no
  `PInCtor`. **EXPORTED** (`Mermaid.hs:41`).
- `edgeOutputName :: Edge (HsPred rs ci) rs ci co s -> Maybe Text` (`Mermaid.hs:595-604`) — renders
  the output constructor name(s): `[] -> Nothing`; `[o] -> wcName`; `[a,b] -> "a; b"`; three or more
  joined by `<br/>`. **EXPORTED** (`Mermaid.hs:42`). (For Markdown you may prefer a different
  separator for the 3+ case; see Plan of Work — the inspector defines its own join so `<br/>` does
  not leak into Markdown. The `[]`/`[o]`/`[a,b]` behaviour is reused.)
- `guardSummary :: HsPred rs ci -> Text` (`Mermaid.hs:662-673`) — a structural prefix walk of the
  guard's constructor tags, e.g. `"PAnd PInCtor PEq"`. **NOT exported** (it is not in the export
  list at `Mermaid.hs:25-44`).
- `writtenSlots :: Update rs w ci -> [Text]` (`Mermaid.hs:649-652`) — recovers the written slot
  names: `UKeep -> []`, `USet ix _ -> [indexNName ix]`, `UCombine a b -> writtenSlots a ++ writtenSlots b`.
  Uses `indexNName` from `Keiki.Internal.Slots` (`src/Keiki/Internal/Slots.hs:134-135`).
  **NOT exported.**

### The fixture you will render

The golden test renders `Keiki.Fixtures.UserRegistration.userReg`
(`test/Keiki/Fixtures/UserRegistration.hs`), the same multi-edge transducer the Mermaid golden uses.
Its state type `Vertex` (`UserRegistration.hs:173-178`) is
`PotentialCustomer | RequiresConfirmation | Confirmed | Deleted`, deriving
`(Eq, Show, Enum, Bounded)`. The exact edges (source, target, command, event, written slots, guard
shape) are already pinned by the Mermaid annotated golden at
`test/Keiki/Render/MermaidSpec.hs:156-166`; reuse those facts when writing the inspector golden.

### Project conventions you must follow

- Build the library from the repo root: `cabal build keiki`. Run tests: `cabal test keiki-test`.
- The test runner is a **manual aggregator** `test/Spec.hs` (there is **no** `hspec-discover`):
  every spec module is imported and wired into `main` by hand. The project uses **`hspec` only** —
  no QuickCheck, no Hedgehog. You add a spec by (1) creating the module under `test/`, (2) adding it
  to `keiki.cabal` under `test-suite keiki-test: other-modules`, and (3) adding an `import … qualified`
  plus a `describe` line in `test/Spec.hs main`.
- A new library module is added to `keiki.cabal` under `library: exposed-modules`.
- Test fixtures live in `test/Keiki/Fixtures/`; reuse `Keiki.Fixtures.UserRegistration` rather than
  authoring a new fixture, so the inspector golden uses a real multi-edge transducer.
- Commits on this plan carry the trailers `MasterPlan` /
  `ExecPlan (docs/plans/62-edge-inspector-markdown-renderer-for-symtransducer.md)` /
  `Intention: intention_01ktes9wvkekw8nbb69st0naj8` (matching the frontmatter `intention` field).
  Follow Conventional Commits (e.g. `feat(render): add renderEdgeInspector …`). Commit directly to
  the current branch; do not create a feature branch unless asked.

### Sibling plan you depend on (soft)

This plan **soft-depends** on EP-61
(`docs/plans/61-pretty-printer-for-hspred-term-update-and-domain-readable-mermaid-guard-rendering.md`),
which creates module `Keiki.Render.Pretty` exporting `prettyPred :: HsPred rs ci -> Text` and
`prettyTerm :: Term rs ci ifs r -> Text`. Milestone 2 imports and reuses those for the pretty-guard
and output-field-term rendering; it must not re-implement them. If EP-61 is not yet merged when you
implement M2, see the fallback in the Plan of Work (ship M1 structural-only and treat the pretty
options as no-ops until `Keiki.Render.Pretty` lands).


## Plan of Work

The work is two milestones. **M1** delivers a working, golden-tested inspector that shows source,
target, edge index, input constructor, output constructor(s), the *structural* guard summary, and
written slots — everything that does not need the EP-61 pretty-printer. **M2** layers in the two
options that reuse `Keiki.Render.Pretty`: a domain-readable *pretty* guard, and positional rendering
of output-field *terms*.

### The public interface (defined once, here)

The new module `src/Keiki/Render/Inspector.hs` exports exactly:

```haskell
module Keiki.Render.Inspector
  ( EdgeInspectorOptions (..)
  , defaultEdgeInspectorOptions
  , renderEdgeInspector
  ) where

data EdgeInspectorOptions = EdgeInspectorOptions
  { includeEdgeIndex       :: Bool  -- show "edge index: N"
  , includeStructuralGuard :: Bool  -- show the structural guard summary, e.g. "PAnd PInCtor PEq"
  , includePrettyGuard     :: Bool  -- show the domain-readable guard (EP-61 prettyPred); M2
  , includeWrittenSlots    :: Bool  -- show the register slots the edge writes
  , includeOutputFields    :: Bool  -- show each output field's term, positionally (EP-61 prettyTerm); M2
  }

renderEdgeInspector
  :: (Bounded s, Enum s, Show s)
  => EdgeInspectorOptions
  -> SymTransducer (HsPred rs ci) rs s ci co
  -> Text
```

`defaultEdgeInspectorOptions` turns *everything on except the two pretty options that depend on
EP-61*, so the default is useful with M1 alone and stays useful after M2:

```haskell
defaultEdgeInspectorOptions :: EdgeInspectorOptions
defaultEdgeInspectorOptions = EdgeInspectorOptions
  { includeEdgeIndex       = True
  , includeStructuralGuard = True
  , includePrettyGuard     = False  -- opt-in; needs EP-61's prettyPred
  , includeWrittenSlots    = True
  , includeOutputFields    = False  -- opt-in; needs EP-61's prettyTerm
  }
```

The constraints `(Bounded s, Enum s, Show s)` mirror `toMermaid` (`Mermaid.hs:97-101`): `Bounded` +
`Enum` to enumerate the states `[minBound .. maxBound]`, `Show` to print state names.

### The exact Markdown format (so the golden can pin it)

`renderEdgeInspector` emits one document. The shape, fixed for determinism:

1. A document title line: `# Edge inspector` followed by a blank line.
2. For each state `s` in `[minBound .. maxBound]` **that has at least one outgoing edge**
   (skip states with no edges, so unreachable/terminal states do not produce empty headings):
   a level-3 heading `### <show s>`, a blank line, then one block per outgoing edge.
3. For each outgoing edge of `s`, taken in `edgesOut` order with its 0-based positional index `i`,
   a Markdown bullet list. The first bullet names the transition; the remaining bullets carry the
   detail fields, each emitted only if its option is on (and only if it has content). The exact
   per-edge block (with all M1 options on) is:

   ```text
   - **<show s> -> <show target>**
     - edge index: <i>
     - input: <input constructor name, or "?">
     - output: <output constructor name(s), or "ε">
     - guard (structural): <guardSummary>
     - written slots: <slot; slot; …>   (omitted entirely when the edge writes nothing)
   ```

   Notes on each field:
   - The header bullet always shows `source -> target` using `show`.
   - `input` uses the leftmost `PInCtor`'s `icName`; if the guard has none, render `?` (mirrors
     `edgeLabel`'s `?` convention at `Mermaid.hs:609-613`).
   - `output` is the output constructor name(s). Reuse the `[]`/`[o]`/`[a,b]` cases of
     `edgeOutputName` (`Mermaid.hs:595-604`); for three or more outputs, the inspector joins with
     `"; "` (a comma-free, Markdown-safe separator) rather than the Mermaid `<br/>`, because
     `<br/>` is a diagram-only line break that would look wrong in a Markdown bullet. An ε-edge
     (empty output list) renders the literal `ε` (U+03B5), matching `edgeLabel`.
   - `guard (structural)` appears only when `includeStructuralGuard` is on. It is the structural
     constructor walk `guardSummary g` (e.g. `PAnd PInCtor PEq`).
   - `guard (pretty)` (M2) appears only when `includePrettyGuard` is on, on its own bullet *after*
     the structural one when both are on (the acceptance lets a debugger show BOTH).
   - `written slots` appears only when `includeWrittenSlots` is on **and** the edge writes at least
     one slot; when the edge writes nothing the bullet is omitted entirely (an empty list would be
     noise — the same choice `edgeLabelWith` makes at `Mermaid.hs:631-634`). Slot names are joined
     with `"; "`.
   - `output fields` (M2) appears only when `includeOutputFields` is on and the edge has at least
     one output with at least one field; see M2 below for its exact shape.
4. Blocks within a state are separated by a single newline between bullet lists (no blank line
   between consecutive edge blocks under the same heading); state sections are separated by a blank
   line before each `###` heading. The whole document is assembled with `Data.Text` joins (no
   trailing newline), exactly as the Mermaid renderer assembles its output with
   `T.intercalate "\n"`. The implementer pins the precise whitespace in the golden; pick one
   assembly and keep it stable.

This format is deliberately list-based and `show`/`icName`/`wcName`-driven, all of which are
deterministic, so the output is byte-stable and golden-friendly.

### Reuse-vs-replicate the Mermaid helpers

`edgeInputName` and `edgeOutputName` are already **exported** from `Keiki.Render.Mermaid`
(`Mermaid.hs:41-42`), so import and reuse them directly — no edit to the Mermaid module needed for
those. `guardSummary` and `writtenSlots` are **not** exported (absent from the export list at
`Mermaid.hs:25-44`). Two clean options exist: (a) widen the Mermaid export list additively to export
them, or (b) replicate them in `Inspector.hs`. **Recommendation: replicate** both, because each is a
tiny total function (three or four equations), replication keeps the inspector self-contained and
avoids touching the Mermaid module (whose byte-identity is load-bearing per MasterPlan 15), and the
two helpers are unlikely to drift (they walk fixed ASTs). The replicated `writtenSlots` must use the
existential-`w` pattern-match — call it on `u` bound by `Edge { update = u }`, never via the
`update` selector — and import `indexNName` from `Keiki.Internal.Slots`. Record the final choice in
the Decision Log. (If the implementer instead chooses to export them, that edit is additive: add
`guardSummary` and `writtenSlots` to the `Mermaid.hs` export list; it cannot change any rendered
bytes.)

### Milestone 1 — core inspector + golden (no EP-61 dependency)

Scope: everything above except `includePrettyGuard` and `includeOutputFields`. At the end of M1 the
module `src/Keiki/Render/Inspector.hs` exists and exports `EdgeInspectorOptions`,
`defaultEdgeInspectorOptions`, and `renderEdgeInspector`; it is registered in `keiki.cabal`
`exposed-modules`; and a golden spec `test/Keiki/Render/InspectorSpec.hs` pins the exact Markdown for
`userReg` rendered with `defaultEdgeInspectorOptions` (which under M1 has the two pretty options off,
so M1's golden never depends on EP-61). For M1, `includePrettyGuard`/`includeOutputFields` exist in
the record but their code paths render nothing (no-op) — this is the EP-61 fallback path made
permanent for M1 and filled in by M2.

Steps: create the module with the format above, reusing `edgeInputName`/`edgeOutputName` and
replicating `guardSummary`/`writtenSlots`. Add `Keiki.Render.Inspector` to `keiki.cabal`
`library: exposed-modules`. Build with `cabal build keiki`. Create the spec, register it in
`keiki.cabal` `test-suite keiki-test: other-modules` and in `test/Spec.hs`, then `cabal test keiki-test`.

Commands: `cabal build keiki` then `cabal test keiki-test`. Acceptance: both succeed; the inspector
golden matches the Markdown shown in Validation and Acceptance below.

### Milestone 2 — pretty guard + output-field terms (reuses EP-61)

Scope: implement the two opt-in options by importing `Keiki.Render.Pretty`.

- `includePrettyGuard`: when on, add a `- guard (pretty): <prettyPred g>` bullet (after the
  structural one if both are on), where `prettyPred :: HsPred rs ci -> Text` comes from
  `Keiki.Render.Pretty` (EP-61). Do not re-implement guard prettifying.
- `includeOutputFields`: when on, for each output `OPack ic wc fields`, walk the `OutFields` HList
  (`OFNil`/`OFCons`, `Core.hs:494-499`) applying `prettyTerm :: Term rs ci ifs r -> Text` (EP-61) to
  each field `Term`, and emit a bullet listing them positionally, e.g.
  `- output fields: field 0: <term0>; field 1: <term1>`. Because `WireCtor` has no field names
  (`Core.hs:478-482`), the labels are positional indices only — never wire field names. If an edge
  emits multiple outputs, prefix each group with its output constructor name (`wcName`) so the
  reader can tell which event's fields are which, e.g.
  `- output fields: RegistrationStarted[field 0: …]; ConfirmationEmailSent[field 0: …]`. The exact
  separator is pinned by the M2 golden; keep it deterministic.

**EP-61 fallback (state plainly):** if `Keiki.Render.Pretty` does not yet exist when M2 is reached,
do **not** block. Keep M1's behaviour: leave `includePrettyGuard`/`includeOutputFields` as no-ops
(or, for the pretty guard, fall back to the structural summary text), ship M1's golden, and complete
M2 once EP-61 is merged. The two options are additive and have defaults `False`, so a no-op M2 path
changes no existing golden.

At the end of M2 the two options produce content and have their own golden cases (one showing both
structural and pretty guard together; one showing output-field terms). Commands: `cabal test keiki-test`.
Acceptance: full suite passes; the pretty-vs-structural difference is visible in the golden shown in
Validation and Acceptance.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki`.

### Step 1 — create the inspector module (M1)

Create `src/Keiki/Render/Inspector.hs`. A correct M1 skeleton (fill in the exact whitespace, then
let the golden pin it) looks like the following. Note `writtenSlots` is called on `u` bound by the
`Edge` pattern, satisfying the existential-`w` rule.

```haskell
-- | A Markdown edge-detail renderer for 'SymTransducer', a sibling to
-- the Mermaid topology renderer in "Keiki.Render.Mermaid". Produces a
-- deterministic Markdown document, edges grouped by source state.
module Keiki.Render.Inspector
  ( EdgeInspectorOptions (..)
  , defaultEdgeInspectorOptions
  , renderEdgeInspector
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import Keiki.Core
  ( Edge (..)
  , HsPred (..)
  , SymTransducer (..)
  , Update (..)
  )
import Keiki.Internal.Slots (indexNName)
import Keiki.Render.Mermaid (edgeInputName, edgeOutputName)

data EdgeInspectorOptions = EdgeInspectorOptions
  { includeEdgeIndex       :: Bool
  , includeStructuralGuard :: Bool
  , includePrettyGuard     :: Bool
  , includeWrittenSlots    :: Bool
  , includeOutputFields    :: Bool
  }

defaultEdgeInspectorOptions :: EdgeInspectorOptions
defaultEdgeInspectorOptions = EdgeInspectorOptions
  { includeEdgeIndex       = True
  , includeStructuralGuard = True
  , includePrettyGuard     = False
  , includeWrittenSlots    = True
  , includeOutputFields    = False
  }

renderEdgeInspector
  :: (Bounded s, Enum s, Show s)
  => EdgeInspectorOptions
  -> SymTransducer (HsPred rs ci) rs s ci co
  -> Text
renderEdgeInspector opts t =
  let states  = [minBound .. maxBound]
      section s = case edgesOut t s of
        []    -> Nothing
        edges -> Just (renderState opts s edges)
  in T.intercalate (T.pack "\n\n")
       ( T.pack "# Edge inspector"
       : [ blk | Just blk <- map section states ] )

-- renderState / renderEdge / the replicated guardSummary and
-- writtenSlots helpers go here. writtenSlots MUST be applied to the
-- 'Update' bound by an Edge pattern, never via the 'update' selector:
--
--   renderEdge opts s i e@Edge { guard = g, output = outs, update = u, target = tgt } = ...
--
-- guardSummary and writtenSlots are replicated from Keiki.Render.Mermaid
-- (they are not exported there); keep them byte-identical to the
-- originals at Mermaid.hs:649-652 and Mermaid.hs:662-673.
```

Then add the module to the library's exposed modules:

```diff
   exposed-modules:
     ...
     Keiki.Render.Mermaid
+    Keiki.Render.Inspector
     Keiki.Shape
```

Build the library:

```bash
cabal build keiki
```

Expected (abbreviated) transcript:

```text
Building library 'keiki' ...
[ N of M] Compiling Keiki.Render.Inspector ...
```

with no errors. If GHC reports an "escaped type variable" / GHC-55876 error around `update`, you
applied the `update` selector as a function — fix it by pattern-matching the `Edge` constructor.

### Step 2 — create the golden spec (M1)

Create `test/Keiki/Render/InspectorSpec.hs`:

```haskell
module Keiki.Render.InspectorSpec (spec) where

import Data.Text (Text)
import qualified Data.Text as T
import Test.Hspec

import Keiki.Fixtures.UserRegistration (userReg)
import Keiki.Render.Inspector
  ( defaultEdgeInspectorOptions
  , renderEdgeInspector
  )

spec :: Spec
spec =
  describe "renderEdgeInspector (default options)" $
    it "renders userReg to the canonical Markdown inspector block" $
      renderEdgeInspector defaultEdgeInspectorOptions userReg
        `shouldBe` userRegInspectorCanonical

userRegInspectorCanonical :: Text
userRegInspectorCanonical = T.intercalate (T.pack "\n") [ {- exact lines, see Validation -} ]
```

Register it in the test suite and the aggregator:

```diff
   other-modules:
     ...
     Keiki.Render.MermaidSpec
+    Keiki.Render.InspectorSpec
     Keiki.ShapeSpec
```

```diff
 import Keiki.Render.MermaidSpec qualified
+import Keiki.Render.InspectorSpec qualified
```

```diff
     describe "Keiki.Render.Mermaid (EP-30, EP-31, EP-32, EP-33)" Keiki.Render.MermaidSpec.spec
+    describe "Keiki.Render.Inspector (EP-62)" Keiki.Render.InspectorSpec.spec
```

### Step 3 — derive the golden, then pin it

Before hand-writing the canonical `Text`, derive it from the actual renderer so the golden matches
exactly. Print it once from GHCi:

```bash
cabal repl keiki-test
```

```text
ghci> import qualified Data.Text.IO as TIO
ghci> import Keiki.Render.Inspector
ghci> import Keiki.Fixtures.UserRegistration (userReg)
ghci> TIO.putStrLn (renderEdgeInspector defaultEdgeInspectorOptions userReg)
```

Copy the printed block into `userRegInspectorCanonical` line by line (one `Text` per output line,
joined by `T.intercalate "\n"`, exactly as `MermaidSpec` pins its goldens at
`test/Keiki/Render/MermaidSpec.hs:133-145`). The expected content is shown in Validation and
Acceptance — confirm the REPL output matches it before committing; if it differs, fix the renderer
format (the plan's format is the contract), not the golden.

### Step 4 — run the suite (M1 acceptance)

```bash
cabal test keiki-test
```

Expected (abbreviated):

```text
Keiki.Render.Inspector (EP-62)
  renderEdgeInspector (default options)
    renders userReg to the canonical Markdown inspector block
...
Finished in N seconds
M examples, 0 failures
```

### Step 5 — M2 (after EP-61 is available)

Add `import Keiki.Render.Pretty (prettyPred, prettyTerm)` to `Inspector.hs`, implement the
`includePrettyGuard` and `includeOutputFields` branches per the Plan of Work, and add the two M2
golden cases to `InspectorSpec.hs` (one toggling `includePrettyGuard = True` alongside the
structural guard, one toggling `includeOutputFields = True`). Re-run `cabal test keiki-test`. If
EP-61 is not yet merged, skip Step 5 and leave the two options as no-ops (M1 already passes); record
the deferral in Progress and the Decision Log.

### Step 6 — commit

Commit with a Conventional-Commits message and the required trailers:

```text
feat(render): add renderEdgeInspector Markdown edge-detail renderer (EP-62 M1)

MasterPlan: docs/masterplans/15-keiki-mermaid-diagram-and-documentation-rendering-improvements-surfaced-by-the-seihou-diagram-audit.md
ExecPlan: docs/plans/62-edge-inspector-markdown-renderer-for-symtransducer.md
Intention: intention_01ktes9wvkekw8nbb69st0naj8
```


## Validation and Acceptance

The behavioral acceptance is the golden test: `renderEdgeInspector defaultEdgeInspectorOptions
userReg` produces a deterministic Markdown document, edges grouped by source state, each edge
showing source, target, edge index, input constructor, output constructor(s), structural guard, and
written slots. Run:

```bash
cabal test keiki-test
```

and observe the `Keiki.Render.Inspector (EP-62)` describe block pass with `0 failures`.

The facts to render are already pinned by the Mermaid annotated golden at
`test/Keiki/Render/MermaidSpec.hs:156-166`. `userReg` has these outgoing edges (source, target,
command, event(s), written slots, guard shape):

- `PotentialCustomer -> RequiresConfirmation` (index 0): `StartRegistration` /
  `RegistrationStarted; ConfirmationEmailSent`; writes `registeredAt; confirmCode; email`; guard `PInCtor`.
- `RequiresConfirmation -> Confirmed` (index 0): `ConfirmAccount` / `AccountConfirmed`; writes
  `confirmedAt`; guard `PAnd PInCtor PEq`.
- `RequiresConfirmation -> RequiresConfirmation` (index 1): `ResendConfirmation` /
  `ConfirmationResent`; writes `registeredAt; confirmCode`; guard `PInCtor`.
- `RequiresConfirmation -> Deleted` (index 2): `FulfillGDPRRequest` / ε (no output); writes
  `deletedAt`; guard `PInCtor`.
- `Confirmed -> Deleted` (index 0): `FulfillGDPRRequest` / `AccountDeleted`; writes `deletedAt`;
  guard `PInCtor`.

`Deleted` has no outgoing edges, so it produces no section. The expected M1 document (default
options: edge index, structural guard, written slots on; pretty guard and output fields off) is:

```text
# Edge inspector

### PotentialCustomer

- **PotentialCustomer -> RequiresConfirmation**
  - edge index: 0
  - input: StartRegistration
  - output: RegistrationStarted; ConfirmationEmailSent
  - guard (structural): PInCtor
  - written slots: registeredAt; confirmCode; email

### RequiresConfirmation

- **RequiresConfirmation -> Confirmed**
  - edge index: 0
  - input: ConfirmAccount
  - output: AccountConfirmed
  - guard (structural): PAnd PInCtor PEq
  - written slots: confirmedAt
- **RequiresConfirmation -> RequiresConfirmation**
  - edge index: 1
  - input: ResendConfirmation
  - output: ConfirmationResent
  - guard (structural): PInCtor
  - written slots: registeredAt; confirmCode
- **RequiresConfirmation -> Deleted**
  - edge index: 2
  - input: FulfillGDPRRequest
  - output: ε
  - guard (structural): PInCtor
  - written slots: deletedAt

### Confirmed

- **Confirmed -> Deleted**
  - edge index: 0
  - input: FulfillGDPRRequest
  - output: AccountDeleted
  - guard (structural): PInCtor
  - written slots: deletedAt
```

This is the *intended* document. The exact whitespace (whether a blank line follows each `###`
heading, whether edge blocks are separated by a blank line) is the implementer's to fix and then pin
in `userRegInspectorCanonical`; derive the true bytes from the REPL (Concrete Steps, Step 3) and
pin those. The load-bearing acceptance is that all eight detail fields appear, edges are grouped by
source state in `[minBound .. maxBound]` order, indices are the 0-based `edgesOut` positions, the
ε-edge shows `ε`, and `Deleted` (no edges) produces no section. Note the `RequiresConfirmation`
self-loop at index 1 and the `Deleted` edge at index 2 — the indices come straight from `edgesOut`
order, matching `checkHiddenInputs`' numbering (`Core.hs:1027`).

For **M2**, the acceptance adds two cases. With `includePrettyGuard = True` *and*
`includeStructuralGuard = True`, an edge shows both a `- guard (structural): …` bullet and a
`- guard (pretty): …` bullet (the pretty text comes from `Keiki.Render.Pretty.prettyPred`; e.g. the
`ConfirmAccount` edge's `PAnd PInCtor PEq` renders structurally as `PAnd PInCtor PEq` and pretty as
whatever EP-61 defines for that predicate, such as a readable conjunction). With
`includeOutputFields = True`, each edge gains a `- output fields: …` bullet listing each output
field's term positionally via `prettyTerm` (field 0, field 1, …) — never by wire field name, because
`WireCtor` has no field names (`Core.hs:478-482`). The M2 goldens pin the exact pretty text once
EP-61's `Keiki.Render.Pretty` output format is known.

Beyond compilation, the proof is that the golden is generated from the same `userReg` value as the
Mermaid golden in `MermaidSpec`, so a reviewer can diff the inspector document against the diagram
and see they describe the same five edges.


## Idempotence and Recovery

Every step is additive and safe to repeat. The plan creates two new files
(`src/Keiki/Render/Inspector.hs`, `test/Keiki/Render/InspectorSpec.hs`) and makes three small
additive registrations (one `exposed-modules` line, one `other-modules` line, one import + one
`describe` in `test/Spec.hs`). It does **not** modify `src/Keiki/Core.hs`, `src/Keiki/Render/Mermaid.hs`
(unless the implementer chooses the export-widening path for the helpers, which is byte-neutral), or
any existing golden. So re-running `cabal build keiki` / `cabal test keiki-test` is safe and
deterministic; the existing Mermaid goldens are untouched by construction (different module, no
shared mutable state, pure functions).

If a build fails: the most likely cause is the existential-`w` error (GHC-55876) from applying the
`update` selector — fix by pattern-matching `Edge { update = u, … }` and operating on `u`. If
`cabal` cannot find `Keiki.Render.Inspector` or `Keiki.Render.InspectorSpec`, the `keiki.cabal`
registration line is missing or misspelled. If the golden test fails, compare the assertion's
expected/actual: re-derive the canonical `Text` from the REPL (Concrete Steps, Step 3) and pin the
true bytes — the renderer's format is the contract, so prefer aligning the golden to a corrected
renderer rather than masking a format bug.

To roll back, delete the two new files and revert the three registration lines; nothing else is
affected.

If EP-61 is unavailable when M2 is reached, the recovery path is to stop after M1: leave
`includePrettyGuard`/`includeOutputFields` as no-ops (defaults `False`), which leaves M1's golden
green, and resume M2 once `Keiki.Render.Pretty` exists. This is documented in Progress and the
Decision Log so a future contributor can restart from this file alone.


## Interfaces and Dependencies

No new package dependencies. The inspector uses only what the renderer already uses: `text`
(`Data.Text`) and the in-repo modules below. There is no IO and no SMT solver. MasterPlan 15
explicitly forbids adding any `keiki.cabal` dependency beyond `text`/`containers` (Vision & Scope,
lines 82-84).

Modules consumed:

- `Keiki.Core` (`src/Keiki/Core.hs`) — the ASTs: `SymTransducer (..)`, `Edge (..)`, `HsPred (..)`,
  `Update (..)`, `OutTerm (..)` / `WireCtor (..)` / `InCtor (..)` / `OutFields (..)` (the last four
  for M2's output-field walk). Pattern-match `Edge` (never apply the `update` selector).
- `Keiki.Render.Mermaid` (`src/Keiki/Render/Mermaid.hs`) — reuse the exported
  `edgeInputName :: Edge (HsPred rs ci) rs ci co s -> Maybe Text` and
  `edgeOutputName :: Edge (HsPred rs ci) rs ci co s -> Maybe Text`. `guardSummary` and `writtenSlots`
  are not exported; replicate them in `Inspector.hs` (or widen the export list — Decision Log).
- `Keiki.Internal.Slots` (`src/Keiki/Internal/Slots.hs`) — `indexNName :: KnownSymbol s => IndexN s rs r -> String`,
  used by the replicated `writtenSlots` to read a `USet`'s slot name.
- `Keiki.Render.Pretty` (`src/Keiki/Render/Pretty.hs`, **created by EP-61**) — `prettyPred :: HsPred rs ci -> Text`
  and `prettyTerm :: Term rs ci ifs r -> Text`, consumed by M2 only.

Interfaces that must exist at the end of each milestone:

End of **M1** — module `Keiki.Render.Inspector` exporting:

```haskell
data EdgeInspectorOptions = EdgeInspectorOptions
  { includeEdgeIndex       :: Bool
  , includeStructuralGuard :: Bool
  , includePrettyGuard     :: Bool
  , includeWrittenSlots    :: Bool
  , includeOutputFields    :: Bool
  }

defaultEdgeInspectorOptions :: EdgeInspectorOptions

renderEdgeInspector
  :: (Bounded s, Enum s, Show s)
  => EdgeInspectorOptions
  -> SymTransducer (HsPred rs ci) rs s ci co
  -> Text
```

With M1, `renderEdgeInspector` honors `includeEdgeIndex`, `includeStructuralGuard`, and
`includeWrittenSlots`; `includePrettyGuard` and `includeOutputFields` are accepted but render nothing.

End of **M2** — the same signatures, with `includePrettyGuard` now emitting a `guard (pretty)` bullet
via `Keiki.Render.Pretty.prettyPred`, and `includeOutputFields` emitting an `output fields` bullet
that lists each output field's `Keiki.Render.Pretty.prettyTerm` positionally.

No signature changes to any existing module are required. (If the implementer widens
`Keiki.Render.Mermaid`'s export list to expose `guardSummary`/`writtenSlots`, that is the only
existing-module edit, and it is purely additive — it changes no rendered bytes and no existing
golden.)
