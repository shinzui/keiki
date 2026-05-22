# Mermaid rendering

keiki's `Keiki.Render.Mermaid` turns a transducer into a Mermaid
`stateDiagram-v2` block — a text diagram that GitHub, Notion, VS Code, and most
Markdown previewers render inline. The single-transducer entry point is
`toMermaid`; composites have their own (`toMermaidComposite`,
`toMermaidCompose3`, `toMermaidAlternative`, `toMermaidFeedback1`, and the nested
variants). The default edge label is `<input command> / <output event>`.

This page covers the two opt-in extensions: assembling many diagrams into one
document, and an opt-in structural edge summary. Neither changes the default
output.


## 1. An atlas of many diagrams: `toMermaidAtlas`

`toMermaidAtlas :: [(Text, Text)] -> Text` assembles several **already-rendered**
diagrams into one Markdown document — each under a `## ` heading, each wrapped in
a fenced ` ```mermaid ` block, sections separated by a blank line. It is the
one-call replacement for the per-aggregate "render, wrap in a heading,
concatenate" glue a multi-aggregate page would otherwise need.

```haskell
toMermaidAtlas
  [ ("User registration", toMermaid userReg)
  , ("Alert ⨾ Email",     toMermaidComposite (compose alertSource emailDelivery))
  ]
```

It takes `(label, rendered-diagram)` **pairs**, not a list of transducers,
because transducers are heterogeneously typed — each has its own vertex,
register, command, and event types, so a single `[SymTransducer …]` would not
type-check. Letting each caller render its own transducer (with whichever entry
point matches it) and pass the resulting `Text` is the smallest API that removes
the glue. The output is a Markdown page, not a single `stateDiagram-v2` block,
because Mermaid has no "several state diagrams in one block" construct; the page
pastes straight into a file under `docs/guide/diagrams/`.


## 2. An opt-in structural edge summary: `toMermaidWith` / `MermaidOptions`

`toMermaidWith :: MermaidOptions -> SymTransducer … -> Text` is `toMermaid` with
a `MermaidOptions` record controlling an optional bracketed suffix on each edge
label:

```haskell
data MermaidOptions = MermaidOptions
  { showWrittenSlots :: Bool   -- append [w: <slot>; <slot>; …]
  , showGuardSummary :: Bool   -- append [g: <guard tag walk>]
  }
```

With both flags on, an edge label gains a compact suffix, e.g.

```text
ConfirmAccount / AccountConfirmed [w: confirmedAt; g: PAnd PInCtor PEq]
```

The summary is **structural**, not a full pretty-print of the guard / update /
output abstract syntax trees. That is a hard constraint, not a stylistic one:
keiki ships no pretty-printer for `HsPred` / `Term` / `Update`, and those trees
carry **unprintable Haskell functions** — `Term`'s `TApp1` / `TApp2` hold opaque
closures, and the `InCtor` / `WireCtor` inside guards and outputs hold
`icMatch` / `icBuild` / `wcMatch` / `wcBuild`. None of those can be turned back
into text. So the summary lists only what is faithfully renderable: the
written-slot **names** (recovered structurally from the `Update`), and the guard's
**constructor / comparison tags** (`PAnd`, `POr`, `PNot`, `PEq`, `PInCtor`,
`PCmp <dir>`) — never an operand term, a register value, or a function.

The summary is applied to the single-transducer path only; the composite
renderers keep the plain `<input> / <output>` label.


## 3. The default stays guard-free — on purpose

`toMermaid` (and `toMermaidWith defaultMermaidOptions`) produce **byte-identical**
output to before: no suffix, no guard. This is load-bearing, not incidental. The
bug-spotting technique in
[Deriving lifecycle transitions](deriving-lifecycle-transitions.md) (§1) relies on
the default label *deliberately omitting the guard*: two edges out of one vertex
that differ only by an unshown guard render to identical-looking lines, which is
exactly what makes a **missing** second edge (the "one-way door" bug) glaring as a
topology. If the default ever started showing guards, those two edges would look
different and the technique would lose its force. A regression golden pins the
default output byte-for-byte so any accidental drift fails in CI.

If you *want* to see guards while reviewing, turn them on explicitly with
`toMermaidWith (MermaidOptions { showWrittenSlots = True, showGuardSummary = True })`.
The structural summary is there for review; the guard-free default is there for
the pedagogy.


## 4. Pointers

- `src/Keiki/Render/Mermaid.hs` — the renderer; `toMermaid`, `toMermaidWith`,
  `toMermaidAtlas`, `MermaidOptions`, `defaultMermaidOptions`.
- `docs/guide/deriving-lifecycle-transitions.md` — the bug-spotting pedagogy the
  guard-free default protects.
- `docs/guide/diagrams/` — generated per-aggregate diagram pages; atlas output
  pastes straight in.
