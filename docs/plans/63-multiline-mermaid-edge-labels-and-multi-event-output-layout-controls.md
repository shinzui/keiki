---
id: 63
slug: multiline-mermaid-edge-labels-and-multi-event-output-layout-controls
title: "Multiline Mermaid edge labels and multi-event output layout controls"
kind: exec-plan
created_at: 2026-06-06T15:47:42Z
intention: "intention_01ktes9wvkekw8nbb69st0naj8"
master_plan: "docs/masterplans/15-keiki-mermaid-diagram-and-documentation-rendering-improvements-surfaced-by-the-seihou-diagram-audit.md"
---

# Multiline Mermaid edge labels and multi-event output layout controls

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

keiki turns a state-machine description (a `SymTransducer`) into a Mermaid `stateDiagram-v2`
diagram so that a human can read a service's command/event topology in GitHub, Notion, or any
Markdown previewer. Today every annotation an edge carries — the input command, the output
event(s), the slots the edge writes, and a structural summary of its guard — is crammed onto a
single label line between two states. When an edge is dense (several written slots, a multi-clause
guard, several emitted events), that single line becomes an unreadable wall of text.

After this change a diagram author can:

- Switch dense edge labels from the current single-line ("inline") form to a **multi-line** form
  where the `command / event` base sits on the first line, the written-slots annotation on a
  second line, and the guard annotation on subsequent lines, using Mermaid's `<br/>` line break.
- Truncate a long written-slot list inline with a deterministic `+N more` suffix (for example, show
  the first three slots then `+4 more`), so a 7-slot edge does not blow out the label width.
- Truncate an over-long guard annotation with a deterministic ellipsis marker once it exceeds a
  configured character width.
- Choose how an edge that emits multiple events renders: the current length-based behavior
  (`MermaidOutputSemicolon`), strictly one event per line (`MermaidOutputMultiline`), or a compact
  `N events` count (`MermaidOutputCounted`).

The reader can see it working by running the test suite (`cabal test keiki-test`) and by inspecting
the new golden Mermaid blocks this plan adds, which show an inline label beside its multiline
equivalent and the three output layouts side by side. Crucially, none of this changes the default:
`toMermaid` and `toMermaidWith defaultMermaidOptions` produce byte-identical output to today, so the
existing diagrams and the existing golden tests in `test/Keiki/Render/MermaidSpec.hs` are untouched.
All new behavior is opt-in through new `MermaidOptions` fields whose defaults reproduce current
behavior.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

Milestone 1 — multiline labels and inline truncation:

- [x] Add `data MermaidLabelLayout = MermaidLabelInline | MermaidLabelMultiline` to `src/Keiki/Render/Mermaid.hs` and export it.
- [x] Add fields `labelLayout :: MermaidLabelLayout`, `maxInlineWrittenSlots :: Maybe Int`, `maxInlineGuardWidth :: Maybe Int` to `MermaidOptions`, after any field EP-61 has added and never before `showWrittenSlots`/`showGuardSummary`.
- [x] Set defaults in `defaultMermaidOptions`: `labelLayout = MermaidLabelInline`, `maxInlineWrittenSlots = Nothing`, `maxInlineGuardWidth = Nothing`.
- [x] Refactor `edgeLabelWith` to build a list of label *segments* (base, optional written-slots segment, optional guard segment) and then lay them out per `labelLayout`.
- [x] Implement deterministic `+N more` truncation of written slots driven by `maxInlineWrittenSlots`.
- [x] Implement deterministic guard-text ellipsis truncation driven by `maxInlineGuardWidth`.
- [x] Add golden cases (multiline label; `+N more`; guard width truncation) to the spec; confirm existing goldens unchanged.
- [x] `cabal build keiki` and `cabal test keiki-test` pass.

Milestone 2 — multi-event output layout:

- [x] Add `data MermaidOutputLayout = MermaidOutputSemicolon | MermaidOutputMultiline | MermaidOutputCounted` and export it.
- [x] Add field `outputLayout :: MermaidOutputLayout` to `MermaidOptions` after the M1 fields; default `MermaidOutputSemicolon`.
- [x] Factor `edgeOutputName` so the layout strategy is chosen by `outputLayout`, with `MermaidOutputSemicolon` reproducing today's exact length-based behavior (`;` for two, `<br/>` for three or more).
- [x] Thread `outputLayout` through `edgeLabel`/`edgeLabelWith` so the base segment uses the chosen output rendering.
- [x] Add golden cases for each of the three output layouts; confirm existing goldens unchanged.
- [x] `cabal build keiki` and `cabal test keiki-test` pass.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- EP-61 had already landed when this plan was implemented, so the field order is
  `showWrittenSlots`, `showGuardSummary`, `guardMode` (EP-61), then this plan's four fields
  (`labelLayout`, `maxInlineWrittenSlots`, `maxInlineGuardWidth`, `outputLayout`). Guard-text
  production was consumed unchanged via EP-61's `renderGuardSegment opts` chokepoint
  (`src/Keiki/Render/Mermaid.hs`); this plan only wrapped segment layout/truncation and the output
  rendering, exactly as the Decision Log anticipated.
- `userReg`'s densest edge writes only three slots (`StartRegistration`), so the `+N more` golden
  uses `maxInlineWrittenSlots = Just 2` (yielding `registeredAt; confirmCode; +1 more`) rather than
  the plan example's `Just 3` over a four-slot edge — there is no four-slot edge in the fixture.
- For three-or-more events, `MermaidOutputSemicolon` and `MermaidOutputMultiline` render
  identically (`<br/>`-joined); they diverge only at exactly two events (`A; B` vs `A<br/>B`). The
  M2 fixture (`multiEvt`) therefore carries both a 3-event and a 2-event edge so the three layout
  goldens are all observably distinct.
- All eight hand-derived golden strings matched the renderer on the first test run (352 examples,
  0 failures; the six pre-existing renderer goldens unchanged), confirming byte-identity of the
  default output.


## Decision Log

Record every decision made while working on the plan.

- Decision: Extend `MermaidOptions` additively rather than redesigning it. Every new field
  (`labelLayout`, `maxInlineWrittenSlots`, `maxInlineGuardWidth`, `outputLayout`) gets a default in
  `defaultMermaidOptions` that reproduces today's bytes; the existing `showWrittenSlots` and
  `showGuardSummary` fields stay.
  Rationale: the MasterPlan's load-bearing invariant is byte-identity of the default output and the
  existing goldens in `test/Keiki/Render/MermaidSpec.hs`. Additive evolution honors each
  requirement's own "default unchanged" acceptance criterion without a breaking migration.
  Date: 2026-06-06

- Decision: Place this plan's new fields *after* EP-61's `guardMode :: MermaidGuardMode` field in
  the `MermaidOptions` record, and never reorder existing fields.
  Rationale: EP-61
  (`docs/plans/61-pretty-printer-for-hspred-term-update-and-domain-readable-mermaid-guard-rendering.md`)
  also extends `MermaidOptions`. To avoid clobbering each other, the agreed field order is
  `showWrittenSlots`, `showGuardSummary`, then EP-61's `guardMode`, then this plan's four fields. If
  EP-61 has not landed when this plan is implemented, append the four fields after
  `showGuardSummary`; when EP-61 later lands, it inserts `guardMode` before them. Either ordering is
  reconciled by always appending, never inserting in the middle.
  Date: 2026-06-06

- Decision: Define `MermaidOutputSemicolon` (the default `outputLayout`) to reproduce today's exact
  length-based behavior — `;` separator for exactly two events, `<br/>` separator for three or more
  — not pure semicolon joining.
  Rationale: Req 8's wording ("default semicolon output remains unchanged") mischaracterizes the
  current default. `edgeOutputName` (`src/Keiki/Render/Mermaid.hs:595-604`) is length-based today.
  Defining the default to reproduce that exact behavior is what keeps the existing goldens
  byte-identical. `MermaidOutputMultiline` is always one event per line (`<br/>`-joined regardless of
  count); `MermaidOutputCounted` renders `N events`.
  Date: 2026-06-06

- Decision: Separation of concerns with EP-61. EP-61 owns how the *guard text* is produced (it
  routes guard rendering through a `renderGuardSegment opts` helper). This plan owns only how
  segments are *laid out* (inline vs multiline) and how the *output segment* is produced. This plan
  does not change guard-text production; it consumes whatever guard text the renderer produces.
  Rationale: both plans edit `edgeLabelWith`; keeping guard-text production (EP-61) distinct from
  segment layout (this plan) lets them coexist without clobbering. If EP-61 is not merged when this
  plan is implemented, the guard text is the existing `guardSummary g`; the work is identical
  because this plan only re-arranges segments.
  Date: 2026-06-06

- Decision: Truncation formats. Written-slot truncation when `maxInlineWrittenSlots = Just k` and
  there are `n > k` slots renders the first `k` slots (slot order preserved) followed by a single
  trailing token `+{n-k} more`. Guard-width truncation when `maxInlineGuardWidth = Just w` and the
  guard text exceeds `w` characters renders `T.take w` of the text followed by the single-character
  ellipsis `…` (U+2026).
  Rationale: deterministic, order-preserving, and visually unambiguous. Choosing `…` (one codepoint)
  over `...` keeps the truncated text close to the requested width.
  Date: 2026-06-06


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

Both milestones landed as designed. `MermaidOptions` now carries `labelLayout`,
`maxInlineWrittenSlots`, `maxInlineGuardWidth` (M1) and `outputLayout` (M2), all defaulted in
`defaultMermaidOptions` to reproduce today's bytes. `edgeLabelWith` assembles label segments and
lays them out inline or multiline with deterministic `+N more` / `…` truncation; `edgeOutputName`
delegates to a new `edgeOutputNameWith` and `edgeLabel` to `edgeLabelWithLayout`, both keeping their
original types and behaviour for existing callers. Six new goldens in
`test/Keiki/Render/MermaidSpec.hs` pin the multiline layout, both truncations, and the three output
layouts; the suite is green at 352 examples with every pre-existing renderer golden byte-identical,
satisfying the MasterPlan's load-bearing byte-identity invariant. No core type changed; the work is
confined to `src/Keiki/Render/Mermaid.hs` and the spec. The only deviation from the plan text was
the `+N more` golden's threshold (`Just 2`, since the fixture has no four-slot edge) — a fixture
artefact, not a design change.


## Context and Orientation

keiki is a pure-Haskell library at `/Users/shinzui/Keikaku/bokuno/keiki`. It models a workflow as a
`SymTransducer` — a symbolic-register transducer: a finite set of states with labelled transitions
("edges"), where each edge reacts to an input command, optionally writes to named registers ("slots"),
optionally emits output events, and is taken only when its guard predicate holds. The renderer module
`src/Keiki/Render/Mermaid.hs` turns a `SymTransducer` into a Mermaid `stateDiagram-v2` text block.
Mermaid is a text diagram language; `stateDiagram-v2` is its state-machine dialect. A transition is
written `Src --> Tgt : <label>`, and the `<label>` is the edge annotation this plan reshapes.

Key definitions for this plan, all in plain terms:

- **Edge label**: the text after the colon on a transition line. Today it is `command / event`
  optionally followed by a bracketed suffix `[w: …; g: …]`. Produced by `edgeLabel` (base) and
  `edgeLabelWith` (base plus suffix) in `src/Keiki/Render/Mermaid.hs`.
- **Written slots**: the register names an edge's `Update` assigns. Recovered by `writtenSlots`
  (`src/Keiki/Render/Mermaid.hs:649-652`): `UKeep` writes nothing, `USet ix _` writes the one slot
  named by `ix`, `UCombine a b` concatenates. Shown in the label as `w: a; b; c` when
  `showWrittenSlots` is on.
- **Guard summary**: a structural, total projection of the edge's guard predicate — its constructor
  tags in left-to-right order, e.g. `PAnd PInCtor PEq`. Produced by `guardSummary`
  (`src/Keiki/Render/Mermaid.hs:662-673`). Shown as `g: …` when `showGuardSummary` is on. It cannot
  print operand values because guard terms can hold opaque Haskell functions and literals carry no
  `Show`.
- **Multi-event output**: an edge's `output` is a list of `OutTerm` values; each carries a
  `WireCtor` whose `wcName :: String` is the event constructor name. The label shows these names.
- **`<br/>`**: the literal four-character string Mermaid interprets as a line break *inside* a label.
  The renderer already uses it: `edgeOutputName` joins three-or-more output names with `<br/>` today
  (`src/Keiki/Render/Mermaid.hs:600`). That is direct supporting evidence that `<br/>` inside a
  `stateDiagram-v2` transition label is already assumed valid, so the multiline label work this plan
  adds rests on a behavior the renderer already relies on.

The current code, verified by reading:

- `data MermaidOptions = MermaidOptions { showWrittenSlots :: Bool, showGuardSummary :: Bool }`
  (`src/Keiki/Render/Mermaid.hs:69-76`); `defaultMermaidOptions` sets both to `False`
  (`src/Keiki/Render/Mermaid.hs:81-85`).
- `edgeLabel` (`src/Keiki/Render/Mermaid.hs:609-613`): `inp <> " / " <> out`; a missing input
  constructor becomes `"?"`, an ε-edge (empty output) becomes the Unicode `ε` (U+03B5).
- `edgeLabelWith` (`src/Keiki/Render/Mermaid.hs:622-641`): pattern-matches
  `Edge { update = u, guard = g }`, computes `base = edgeLabel e`, optionally a `w: …` part and a
  `g: …` part, and joins them with `; ` inside ` [ … ]`. When no parts are present it returns `base`
  alone (no brackets) — this is what keeps the default byte-identical.
- `edgeOutputName` (`src/Keiki/Render/Mermaid.hs:595-604`): length-based — `[]` → `Nothing` (so the
  label shows `ε`); `[o]` → the one `wcName`; `[a, b]` → `wcName a <> "; " <> wcName b` (semicolon for
  *exactly two*); three or more → `T.intercalate "<br/>"` of the names (already multiline today). The
  helper `wcN (OPack _ wc _) = T.pack (wcName wc)`.
- `renderTopologyWith` (`src/Keiki/Render/Mermaid.hs:515-540`) emits each edge as
  `<src> --> <tgt> : <edgeLabelWith opts e>`.

Core types, in `src/Keiki/Core.hs`:

- `data Edge phi rs ci co s` (`src/Keiki/Core.hs:654-661`): the record fields are `guard`, `update`,
  `output :: [OutTerm rs ci co]`, and `target`. **Existential-w gotcha**: the `update` field has type
  `Update rs w ci` where `w` is *existentially quantified*, so the `update` record selector cannot be
  used as a function (it would let the existential escape; GHC error 55876). The only safe way to get
  at `u` is to pattern-match the `Edge` constructor — which `edgeLabelWith` already does at
  `src/Keiki/Render/Mermaid.hs:626` via `Edge { update = u, guard = g }`. Any new code that needs the
  update must keep pattern-matching, never apply `update` as a selector.
- `data OutTerm` (`src/Keiki/Core.hs:522-536`): `OPack (InCtor ci ifs) (WireCtor co fields)
  (OutFields …)`, and `WireCtor { wcName :: String, … }` (`src/Keiki/Core.hs:478-482`).

**Byte-identity invariant (load-bearing, high-risk for this plan).** The MasterPlan
(`docs/masterplans/15-keiki-mermaid-diagram-and-documentation-rendering-improvements-surfaced-by-the-seihou-diagram-audit.md`)
requires that `toMermaid` and `toMermaidWith defaultMermaidOptions` produce byte-identical output to
today, and that the existing goldens in `test/Keiki/Render/MermaidSpec.hs` pass unchanged. Every new
field this plan adds must default to a value that reproduces today's bytes. The single biggest risk is
the output-layout refactor: because `MermaidOutputSemicolon` must reproduce the *length-based* default
(`;` for two, `<br/>` for three or more), it is easy to accidentally regress to pure-semicolon joining.

**Sibling plans (referenced by path only).**
`docs/plans/61-pretty-printer-for-hspred-term-update-and-domain-readable-mermaid-guard-rendering.md`
adds a `guardMode :: MermaidGuardMode` field to `MermaidOptions` and owns guard-text production via a
`renderGuardSegment` helper; this plan adds its fields *after* EP-61's and consumes whatever guard text
the renderer produces (the existing `guardSummary g` if EP-61 has not landed yet).
`docs/plans/62-edge-inspector-markdown-renderer-for-symtransducer.md` builds the edge inspector that
shows full event details; Req 8's "N events inline with details in the edge inspector" splits across
the two — this plan provides only the `Counted` topology label (`N events`), and the inspector (EP-62)
shows the per-event details. Project conventions: build with `cabal build keiki` and test with
`cabal test keiki-test` from the repo root; tests use hspec only (no QuickCheck/Hedgehog), aggregated
in `test/Spec.hs`; GHC2024 with `OverloadedStrings`; rendering is pure (no z3). Commits carry the
trailers `MasterPlan`,
`ExecPlan (docs/plans/63-multiline-mermaid-edge-labels-and-multi-event-output-layout-controls.md)`,
and `Intention: intention_01ktes9wvkekw8nbb69st0naj8`.


## Plan of Work

All edits land in `src/Keiki/Render/Mermaid.hs` (the renderer) and `test/Keiki/Render/MermaidSpec.hs`
(the goldens). No core types change. The work is two milestones: multiline labels with inline
truncation (M1), then multi-event output layout (M2). Each is independently verifiable by the test
suite and leaves the default output byte-identical.

### Milestone 1 — multiline labels and inline truncation

Scope: add the layout vocabulary and the segment-assembly refactor so labels can render multi-line and
written-slot/guard annotations can be truncated. At the end, `MermaidOptions` carries
`labelLayout`, `maxInlineWrittenSlots`, and `maxInlineGuardWidth`; `edgeLabelWith` assembles label
segments and lays them out inline or multiline; and new goldens demonstrate a multiline label, the
`+N more` truncation, and guard-width truncation. The default remains byte-identical. Commands:
`cabal build keiki` then `cabal test keiki-test` from `/Users/shinzui/Keikaku/bokuno/keiki`.
Acceptance: the suite passes, the pre-existing goldens are unchanged, and the new multiline golden
shows the base on line one with `<br/>`-separated segments after it.

First add the layout type near `MermaidOptions` in `src/Keiki/Render/Mermaid.hs`:

```haskell
-- | How dense edge labels are laid out.
data MermaidLabelLayout
  = MermaidLabelInline      -- ^ The current single-line @[seg; seg]@ form.
  | MermaidLabelMultiline   -- ^ Base on line one; each further segment on its
                            --   own @<br/>@-separated line.
  deriving (Eq, Show)
```

Then extend `MermaidOptions`. The exact final field order depends on whether EP-61 has landed. If it
has, EP-61's `guardMode` already sits after `showGuardSummary`; append this plan's fields after it. If
it has not, append after `showGuardSummary`. Either way, never reorder existing fields. The additive
diff (EP-61 absent) is:

```diff
 data MermaidOptions = MermaidOptions
   { showWrittenSlots :: Bool
   , showGuardSummary :: Bool
+  , labelLayout :: MermaidLabelLayout
+    -- ^ Inline (default, byte-identical) or multiline @<br/>@ layout.
+  , maxInlineWrittenSlots :: Maybe Int
+    -- ^ When @Just k@ and an edge writes @n > k@ slots, show the first
+    --   @k@ then a single @+{n-k} more@ token. @Nothing@ = no truncation.
+  , maxInlineGuardWidth :: Maybe Int
+    -- ^ When @Just w@ and the guard text exceeds @w@ characters, take @w@
+    --   characters then append the ellipsis @…@. @Nothing@ = no truncation.
   }
```

And set the defaults so today's bytes are reproduced:

```diff
 defaultMermaidOptions = MermaidOptions
   { showWrittenSlots = False
   , showGuardSummary = False
+  , labelLayout = MermaidLabelInline
+  , maxInlineWrittenSlots = Nothing
+  , maxInlineGuardWidth = Nothing
   }
```

Now refactor `edgeLabelWith` (`src/Keiki/Render/Mermaid.hs:622-641`) to build a list of *segments*
and then lay them out. The base segment is the `command / event` text from `edgeLabel`. The
written-slots segment is the existing `w: …` string, but with `+N more` truncation applied. The guard
segment is the existing `g: …` string (the guard text comes from `guardSummary g`, or, once EP-61 has
landed, from EP-61's `renderGuardSegment opts` — this plan does not change guard-text production), with
guard-width truncation applied to the text. The inline layout is exactly today's form
(`base <> " [" <> intercalate "; " parts <> "]"`, or `base` alone when there are no parts). The
multiline layout puts the base on line one and each further segment on its own `<br/>`-prefixed line:

```haskell
edgeLabelWith opts e@Edge { update = u, guard = g } =
  let base  = edgeLabel e
      ws    = if showWrittenSlots opts then writtenSlots u else []
      wPart = case truncateSlots (maxInlineWrittenSlots opts) ws of
                [] -> []
                xs -> [ T.pack "w: " <> T.intercalate (T.pack "; ") xs ]
      gText = guardSummary g                       -- EP-61: renderGuardSegment opts g
      gPart = if showGuardSummary opts
                then [ T.pack "g: " <> truncateGuard (maxInlineGuardWidth opts) gText ]
                else []
      parts = wPart ++ gPart
  in case labelLayout opts of
       MermaidLabelInline ->
         if null parts
           then base
           else base <> T.pack " [" <> T.intercalate (T.pack "; ") parts <> T.pack "]"
       MermaidLabelMultiline ->
         T.intercalate (T.pack "<br/>") (base : parts)
```

with two small total helpers:

```haskell
-- | Keep the first @k@ slots, replacing the rest with a single
-- @+{n-k} more@ token. @Nothing@ or @n <= k@ leaves the list unchanged.
truncateSlots :: Maybe Int -> [Text] -> [Text]
truncateSlots Nothing  xs = xs
truncateSlots (Just k) xs
  | length xs > k = take k xs ++ [ T.pack ("+" <> show (length xs - k) <> " more") ]
  | otherwise     = xs

-- | Truncate guard text to @w@ characters, appending @…@ when it was longer.
truncateGuard :: Maybe Int -> Text -> Text
truncateGuard Nothing  t = t
truncateGuard (Just w) t
  | T.length t > w = T.take w t <> T.pack "\x2026"
  | otherwise      = t
```

Note that when `labelLayout` stays `MermaidLabelInline` and both truncation knobs stay `Nothing`, the
function reduces to exactly today's behavior, so the default bytes are preserved. The `+N more` token
participates in the written-slots segment, so in inline mode a truncated edge reads
`[w: a; b; c; +4 more]` and in multiline mode the same segment occupies its own `<br/>` line.

Finally export `MermaidLabelLayout` from the module's export list alongside `MermaidOptions`.

### Milestone 2 — multi-event output layout

Scope: let callers choose how a multi-event edge renders its output. At the end, `MermaidOptions`
carries `outputLayout :: MermaidOutputLayout`; `edgeOutputName`/`edgeLabel`/`edgeLabelWith` thread the
layout through so the base segment uses the chosen rendering; and new goldens show all three layouts.
The default (`MermaidOutputSemicolon`) reproduces today's length-based behavior exactly, so the default
bytes are unchanged. Commands and acceptance as in M1.

Add the layout type:

```haskell
-- | How an edge that emits several events renders its output names.
data MermaidOutputLayout
  = MermaidOutputSemicolon  -- ^ Today's length-based default: @;@ for two,
                            --   @<br/>@ for three or more.
  | MermaidOutputMultiline  -- ^ Always one event per line (@<br/>@-joined),
                            --   regardless of count.
  | MermaidOutputCounted    -- ^ A compact @N events@ count for two or more.
  deriving (Eq, Show)
```

Extend `MermaidOptions` with `outputLayout :: MermaidOutputLayout` after the M1 fields, and add
`outputLayout = MermaidOutputSemicolon` to `defaultMermaidOptions`.

Because `edgeOutputName` is called from `edgeLabel`, and `edgeLabel` from `edgeLabelWith`, thread the
layout down. The cleanest minimal change is to add a layout-taking variant `edgeOutputNameWith ::
MermaidOutputLayout -> Edge … -> Maybe Text` and have the existing `edgeOutputName` delegate to it with
`MermaidOutputSemicolon` (preserving its current type and behavior for any other caller). Likewise add
`edgeLabelWithLayout :: MermaidOutputLayout -> Edge … -> Text` that `edgeLabel` delegates to with the
default; `edgeLabelWith` calls `edgeLabelWithLayout (outputLayout opts) e` for its base segment.

The layout-aware output function:

```haskell
edgeOutputNameWith :: MermaidOutputLayout -> Edge (HsPred rs ci) rs ci co s -> Maybe Text
edgeOutputNameWith layout Edge { output = outs } = case outs of
  []  -> Nothing
  [o] -> Just (wcN o)                       -- single event: name only, every layout
  _   -> Just (render layout (map wcN outs))
  where
    wcN :: OutTerm rs ci co -> Text
    wcN (OPack _ wc _) = T.pack (wcName wc)
    render MermaidOutputSemicolon ns
      | length ns == 2 = T.intercalate (T.pack "; ") ns
      | otherwise      = T.intercalate (T.pack "<br/>") ns
    render MermaidOutputMultiline ns = T.intercalate (T.pack "<br/>") ns
    render MermaidOutputCounted   ns = T.pack (show (length ns) <> " events")
```

This preserves transducer output order (the list order is used directly). For `MermaidOutputSemicolon`
the two-element case yields `a; b` and the three-or-more case yields `a<br/>b<br/>c`, exactly today's
`edgeOutputName`. For `MermaidOutputCounted`, zero events stays `Nothing` (so the label shows `ε`, the
sensible empty rendering) and one event stays the single constructor name (counting a single event as
`1 events` would be noise); only two-or-more events render as `N events`.

Add golden cases for each layout and confirm the existing goldens are unchanged.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki`.

First confirm the baseline builds and the existing goldens pass before any edit, so a later failure is
attributable to this work:

```bash
cabal build keiki
cabal test keiki-test
```

Expected (abbreviated):

```text
Build profile: -w ghc ...
Up to date
...
Keiki.Render.Mermaid
  toMermaid (single SymTransducer)
    renders userReg to the canonical stateDiagram-v2 block [✔]
  ...
Finished in N.NNN seconds
All M examples passed
```

Make the M1 edits to `src/Keiki/Render/Mermaid.hs` as shown in Plan of Work (add `MermaidLabelLayout`,
extend `MermaidOptions` and `defaultMermaidOptions`, refactor `edgeLabelWith`, add `truncateSlots` and
`truncateGuard`, export `MermaidLabelLayout`). Rebuild and re-test:

```bash
cabal build keiki
cabal test keiki-test
```

Then add M1 golden cases to `test/Keiki/Render/MermaidSpec.hs`. Add a new `describe` block under the
existing ones that renders a representative edge with `defaultMermaidOptions { showWrittenSlots = True,
showGuardSummary = True, labelLayout = MermaidLabelMultiline }` and pins the multiline label, plus a
case with `maxInlineWrittenSlots = Just 3` over an edge writing more than three slots that pins the
`+N more` token, plus a case with `maxInlineGuardWidth = Just w` pinning the `…` truncation. Import the
new constructors by widening the `Keiki.Render.Mermaid` import list (add `MermaidLabelLayout (..)`).
Re-run `cabal test keiki-test` and confirm all examples pass and the pre-existing goldens are unchanged.

Make the M2 edits (add `MermaidOutputLayout`, extend the record and defaults, add `edgeOutputNameWith`
and `edgeLabelWithLayout`, delegate the existing functions, export `MermaidOutputLayout`). Rebuild,
re-test, then add M2 golden cases for an edge emitting three events under each of
`MermaidOutputSemicolon`, `MermaidOutputMultiline`, and `MermaidOutputCounted`:

```bash
cabal build keiki
cabal test keiki-test
```

If a multi-event fixture does not already exist in the spec, define a small local `SymTransducer` (or
reuse an existing fixture whose edge emits two or more events) in the spec file, following the
`toy3deep` pattern at the bottom of `test/Keiki/Render/MermaidSpec.hs`. No new spec file is strictly
required because `MermaidSpec` already covers the renderer; if a new file is preferred, create it,
add it to `keiki.cabal`'s test-suite `other-modules`, and import/`describe` it in `test/Spec.hs`.


## Validation and Acceptance

The single test command is `cabal test keiki-test` from `/Users/shinzui/Keikaku/bokuno/keiki`. Success
is the whole suite passing with no change to any pre-existing golden. The new behavior is observable in
the new golden blocks. Below, take an edge whose input command is `Submit`, whose output is the single
event `Accepted`, that writes slots `email`, `code`, `at`, `region`, and whose guard summary is
`PAnd PInCtor PEq`.

Inline versus multiline label (M1). With `showWrittenSlots = True, showGuardSummary = True` and the
default `labelLayout = MermaidLabelInline`, the label is one line:

```text
Submit / Accepted [w: email; code; at; region; g: PAnd PInCtor PEq]
```

With the same options but `labelLayout = MermaidLabelMultiline`, the base sits on line one and each
segment follows on its own `<br/>` line:

```text
Submit / Accepted<br/>w: email; code; at; region<br/>g: PAnd PInCtor PEq
```

Written-slot truncation (M1). With `maxInlineWrittenSlots = Just 3` over the same four-slot edge:

```text
Submit / Accepted [w: email; code; at; +1 more; g: PAnd PInCtor PEq]
```

Guard-width truncation (M1). With `maxInlineGuardWidth = Just 10` over the guard text
`PAnd PInCtor PEq` (length 16), the guard segment becomes `g: PAnd PInCt…`:

```text
Submit / Accepted [g: PAnd PInCt…]
```

Output layouts (M2). Take an edge emitting three events `A`, `B`, `C` (output order preserved). With
`outputLayout = MermaidOutputSemicolon` (the default), three-or-more events join with `<br/>`, matching
today exactly:

```text
Submit / A<br/>B<br/>C
```

A two-event edge under the same default uses `;`:

```text
Submit / A; B
```

With `outputLayout = MermaidOutputMultiline`, every multi-event edge is one event per line regardless of
count (so a two-event edge becomes `A<br/>B`, unlike the default's `A; B`). With
`outputLayout = MermaidOutputCounted`, the three-event edge collapses to a count:

```text
Submit / 3 events
```

The byte-identity acceptance is concrete: the existing `toMermaid userReg` golden and the
`toMermaidWith defaultMermaidOptions` golden in `test/Keiki/Render/MermaidSpec.hs` must remain exactly
as they are now — the new fields default to inline layout, no truncation, and semicolon (length-based)
output, so those goldens cannot move. Multiline labels remain valid `stateDiagram-v2` because the
renderer already emits `<br/>` inside transition labels for three-or-more outputs today.


## Idempotence and Recovery

Every step here is additive and pure. The edits add new types, new record fields with current-behavior
defaults, and new helper functions; they touch only `src/Keiki/Render/Mermaid.hs` and
`test/Keiki/Render/MermaidSpec.hs`. There is no migration, no I/O, and no persistent state, so any step
can be repeated safely. Rebuilding (`cabal build keiki`) and re-running the suite
(`cabal test keiki-test`) are idempotent and the natural way to re-validate after any retry.

The chief risk is breaking byte-identity. The guard against it is the pre-existing goldens: if any edit
moves the default bytes, `cabal test keiki-test` fails on the existing `toMermaid` /
`toMermaidWith defaultMermaidOptions` cases, pointing at the regression immediately. To roll back, revert
`src/Keiki/Render/Mermaid.hs` and `test/Keiki/Render/MermaidSpec.hs` to the last commit
(`git checkout -- src/Keiki/Render/Mermaid.hs test/Keiki/Render/MermaidSpec.hs`) and re-run the suite.

If EP-61 lands while this plan is in progress, do not insert fields in the middle of `MermaidOptions`;
re-apply this plan's fields after EP-61's `guardMode` (see Decision Log) and switch the guard segment's
text source from `guardSummary g` to EP-61's `renderGuardSegment opts`, leaving the layout logic
unchanged. Conversely, if this plan lands first, EP-61 inserts `guardMode` before these fields. Because
both plans only ever *append*, the merge is mechanical.


## Interfaces and Dependencies

No new libraries are needed. All work uses `Data.Text` (`text`), already a dependency of the renderer.
The only module edited for production code is `Keiki.Render.Mermaid`
(`src/Keiki/Render/Mermaid.hs`); the only test module is `Keiki.Render.MermaidSpec`
(`test/Keiki/Render/MermaidSpec.hs`). The core types `Edge`, `OutTerm`, `WireCtor`, `Update`, and
`HsPred` (`src/Keiki/Core.hs`) are consumed read-only and are not changed.

At the end of Milestone 1 the following must exist in `Keiki.Render.Mermaid`:

```haskell
data MermaidLabelLayout = MermaidLabelInline | MermaidLabelMultiline

-- MermaidOptions gains (after showGuardSummary, and after EP-61's guardMode
-- if present):
--   labelLayout           :: MermaidLabelLayout
--   maxInlineWrittenSlots :: Maybe Int
--   maxInlineGuardWidth   :: Maybe Int
-- defaultMermaidOptions sets: MermaidLabelInline, Nothing, Nothing.

edgeLabelWith :: MermaidOptions -> Edge (HsPred rs ci) rs ci co s -> Text
truncateSlots :: Maybe Int -> [Text] -> [Text]
truncateGuard :: Maybe Int -> Text -> Text
```

`edgeLabelWith` keeps its existing type and pattern-matches `Edge { update = u, guard = g }` (the
existential-`w` gotcha forbids using the `update` selector). `truncateSlots`/`truncateGuard` may be
local `where`-bindings or top-level helpers; they need not be exported.

At the end of Milestone 2 the following must also exist in `Keiki.Render.Mermaid`:

```haskell
data MermaidOutputLayout
  = MermaidOutputSemicolon
  | MermaidOutputMultiline
  | MermaidOutputCounted

-- MermaidOptions gains (after the M1 fields):
--   outputLayout :: MermaidOutputLayout
-- defaultMermaidOptions sets: MermaidOutputSemicolon.

edgeOutputName       :: Edge (HsPred rs ci) rs ci co s -> Maybe Text          -- unchanged type
edgeOutputNameWith   :: MermaidOutputLayout -> Edge (HsPred rs ci) rs ci co s -> Maybe Text
edgeLabel            :: Edge (HsPred rs ci) rs ci co s -> Text                 -- unchanged type
edgeLabelWithLayout  :: MermaidOutputLayout -> Edge (HsPred rs ci) rs ci co s -> Text
```

`edgeOutputName` delegates to `edgeOutputNameWith MermaidOutputSemicolon` and `edgeLabel` to
`edgeLabelWithLayout MermaidOutputSemicolon`, so both retain their current types and current behavior
for any existing caller while `edgeLabelWith` routes the configured `outputLayout opts` through the
base segment.

`MermaidLabelLayout` and `MermaidOutputLayout` must be added to the module export list (export their
constructors). The `MermaidOptions` constructor and field selectors are already exported via
`MermaidOptions (..)`, so the new fields are exported automatically.

Integration: this plan shares the `MermaidOptions` record and `edgeLabelWith` with
`docs/plans/61-pretty-printer-for-hspred-term-update-and-domain-readable-mermaid-guard-rendering.md`,
which owns guard-text production (`renderGuardSegment`); this plan owns segment layout and output
production and appends its fields after EP-61's. The `MermaidOutputCounted` topology label (`N events`)
pairs with the per-event details surfaced by
`docs/plans/62-edge-inspector-markdown-renderer-for-symtransducer.md`; this plan provides only the
topology-label half.
