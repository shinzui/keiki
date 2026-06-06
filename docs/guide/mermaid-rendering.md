# Mermaid rendering

keiki's render surface lives under `src/Keiki/Render/`. The core is
`Keiki.Render.Mermaid`, which turns a transducer into a Mermaid `stateDiagram-v2`
block — a text diagram that GitHub, Notion, VS Code, and most Markdown previewers
render inline. The single-transducer entry point is `toMermaid`; composites have
their own (`toMermaidComposite`, `toMermaidCompose3`, `toMermaidAlternative`,
`toMermaidFeedback1`, and the nested variants). The default edge label is
`<input command> / <output event>`.

Around that core are four sibling modules, all pure (no IO, no solver):

- **`Keiki.Render.Pretty`** — a domain-readable pretty-printer for `HsPred` /
  `Term` / `Update` (§3).
- **`Keiki.Render.Inspector`** — a full Markdown edge-detail renderer (§6).
- **`Keiki.Render.Markdown`** — regenerate a marked diagram block in place (§7).
- **`Keiki.Render.Validate`** — lint rendered diagram / atlas text (§8).

The default `toMermaid` output is unchanged by all of this; every extension is
opt-in.


## 1. An atlas of many diagrams: `toMermaidAtlas` / `toMermaidAtlasWith`

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
because Mermaid has no "several state diagrams in one block" construct.

For more control, `toMermaidAtlasWith :: MermaidAtlasOptions -> [MermaidSection] -> Text`
takes typed sections and options:

```haskell
data MermaidSection = MermaidSection
  { sectionId      :: Text              -- stable id, also the marker key (§7)
  , sectionTitle   :: Text              -- the heading text
  , sectionKind    :: MermaidSectionKind -- AggregateDiagram | ProcessManagerDiagram | WorkflowDiagram
  , sectionDiagram :: Text              -- the already-rendered diagram
  }

data MermaidAtlasOptions = MermaidAtlasOptions
  { atlasTitle               :: Maybe Text     -- optional top-level `# ` heading (default Nothing)
  , atlasSectionHeadingLevel :: Int            -- per-section heading level (default 2 → `## `)
  , atlasShowSectionKind     :: AtlasKindDisplay -- KindHidden (default) | KindAsLabel | KindAsComment
  , atlasWrapMarkers         :: Maybe Text     -- Just ns → wrap each section in begin/end markers (§7)
  , atlasFenceLanguage       :: Text           -- fenced-block tag (default "mermaid")
  }
```

`toMermaidAtlasWith defaultMermaidAtlasOptions` over sections built from
`(title, diagram)` pairs is **byte-identical** to the legacy `toMermaidAtlas`;
each field only adds output. Set `atlasWrapMarkers (Just ns)` to make the atlas
regenerable in place (§7).


## 2. Edge-label options: `toMermaidWith` / `MermaidOptions`

`toMermaidWith :: MermaidOptions -> SymTransducer … -> Text` is `toMermaid` with a
record controlling an optional bracketed suffix and the label/output layout. Every
field defaults to the no-suffix setting, so `toMermaidWith defaultMermaidOptions`
is byte-identical to `toMermaid`:

```haskell
data MermaidOptions = MermaidOptions
  { showWrittenSlots      :: Bool             -- append [w: <slot>; <slot>; …]
  , showGuardSummary      :: Bool             -- legacy spelling of guardMode = MermaidGuardStructuralSummary
  , guardMode             :: MermaidGuardMode -- Hidden (default) | StructuralSummary | Pretty  (§3)
  , labelLayout           :: MermaidLabelLayout  -- MermaidLabelInline (default) | MermaidLabelMultiline
  , maxInlineWrittenSlots :: Maybe Int        -- Just k → show k slots then `+{n-k} more`
  , maxInlineGuardWidth   :: Maybe Int        -- Just w → truncate the guard segment to w chars + `…`
  , outputLayout          :: MermaidOutputLayout -- Semicolon (default) | Multiline | Counted
  }
```

With the slot and structural-guard summaries on, an edge label gains a compact
suffix:

```text
ConfirmAccount / AccountConfirmed [w: confirmedAt; g: PAnd PInCtor PEq]
```

- **`guardMode`** chooses how (or whether) the guard renders — see §3. An explicit
  `guardMode` other than `MermaidGuardHidden` takes precedence over the legacy
  `showGuardSummary` flag.
- **`labelLayout = MermaidLabelMultiline`** puts each label segment on its own
  `<br/>`-separated line instead of inline — useful for dense edges.
- **`outputLayout`** controls how a multi-event edge renders its output names:
  `MermaidOutputSemicolon` (today's default: `;` for two, `<br/>` for three or
  more), `MermaidOutputMultiline` (always one per line), or `MermaidOutputCounted`
  (a compact `N events`).
- **`maxInlineWrittenSlots` / `maxInlineGuardWidth`** cap the suffix width so a
  busy edge doesn't blow out the label.

The suffix is applied to the single-transducer path only; the composite renderers
keep the plain `<input> / <output>` label.


## 3. Domain-readable guards and the pretty-printer

`Keiki.Render.Pretty` is a pure pretty-printer for the syntax trees:

```haskell
prettyTerm   :: Term rs ci ifs r -> Text
prettyPred   :: HsPred rs ci      -> Text
prettyUpdate :: Update rs w ci    -> Text
```

It renders a guard the way you wrote it, e.g.
`(ConfirmAccount && ConfirmAccount.confirmCode == confirmCode)`, recovering slot
and constructor names structurally. Setting `guardMode = MermaidGuardPretty` makes
`toMermaidWith` use it for the guard segment; `renderEdgeInspector` (§6) uses it
for the `includePrettyGuard` / `includeOutputFields` detail.

Two things are **provably unprintable** and are *marked, not dropped*: an applied
opaque Haskell function (`Term`'s `TApp1` / `TApp2`) renders as `<fn>(…)`, and a
literal (`TLit`, whose type carries no `Show`) renders as `<lit>`. So a
`MermaidGuardPretty` label is faithful where it can be and honest where it can't —
which doubles as a visual flag for the opaque guards that `validateTransducer`'s
`warnOpaqueGuards` audit catches (see `user-guide.md` §8 and
`modeling-collections.md`).

> Note: an earlier version of this page stated keiki ships no pretty-printer for
> `HsPred`/`Term`/`Update`. That is no longer true — `Keiki.Render.Pretty` is it.
> The *structural summary* (`MermaidGuardStructuralSummary`, the constructor-tag
> walk like `PAnd PInCtor PEq`) remains available as the terser, name-free option.


## 4. The default stays guard-free — on purpose

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

When you *want* to see guards while reviewing, turn them on explicitly —
`MermaidGuardStructuralSummary` for the terse tag walk, `MermaidGuardPretty` for
the domain-readable form (§3). The summary/pretty modes are there for review; the
guard-free default is there for the pedagogy.


## 5. Stable state ids and friendly display labels

By default a vertex's Mermaid id and its visible label both come from `Show s`.
When you want a stable ASCII id (legal Mermaid identifier) *and* a friendly display
label that may contain spaces, supply both via `MermaidStateLabels`:

```haskell
data MermaidStateLabels s = MermaidStateLabels
  { stateId           :: s -> Text   -- stable id, used verbatim in every arrow (not sanitised)
  , stateDisplayLabel :: s -> Text   -- friendly label, may contain spaces
  }

toMermaidWithLabels :: (Bounded s, Enum s)
  => MermaidOptions -> MermaidStateLabels s -> SymTransducer … -> Text
```

For each vertex whose display differs from its id, the renderer emits a
`state "<display>" as <id>` declaration and uses the stable id in every transition
arrow; vertices whose display equals their id get no declaration, so feeding
identical functions reproduces `toMermaidWith` byte-for-byte. The `Show s`
constraint is dropped — labels come from the callbacks.

Because `stateId` is used verbatim, two vertices can collide on one id. Check
before trusting a labeled diagram:

```haskell
duplicateStateIds :: (Bounded s, Enum s) => MermaidStateLabels s -> SymTransducer … -> [Text]
-- [] means every vertex maps to a unique id; otherwise the colliding ids, in first-occurrence order
```

Rendering itself never throws on a collision; `duplicateStateIds` is the AST-level
check, and the §8 validator detects the same collisions over rendered *text* keyed
off the same id token, so the two agree by construction.


## 6. Full edge detail in Markdown: `renderEdgeInspector`

Where `toMermaid` shows the *shape* of a workflow (one line per edge),
`Keiki.Render.Inspector` lays out every edge in *full* as a Markdown document —
edges grouped under a level-3 heading per source state:

```haskell
renderEdgeInspector :: (Bounded s, Enum s, Show s)
  => EdgeInspectorOptions -> SymTransducer (HsPred rs ci) rs s ci co -> Text

data EdgeInspectorOptions = EdgeInspectorOptions
  { includeEdgeIndex       :: Bool   -- `edge index: N` (0-based position in edgesOut t s)
  , includeStructuralGuard :: Bool   -- the structural tag walk, e.g. PAnd PInCtor PEq
  , includePrettyGuard     :: Bool   -- the domain-readable guard via Keiki.Render.Pretty (default off)
  , includeWrittenSlots    :: Bool   -- the register slots the edge writes
  , includeOutputFields    :: Bool   -- each output field's term, positionally (default off)
  }
```

`defaultEdgeInspectorOptions` turns on everything that needs no domain-readable
rendering; the two pretty options (`includePrettyGuard`, `includeOutputFields`)
reuse §3 and default to `False`. `WireCtor` carries no field names, so output
fields are labelled by position only. This is the tool for a human-reviewable
"what does every edge actually do?" page that the topology diagram is too terse for.


## 7. Regenerating a diagram block in place: `Keiki.Render.Markdown`

`Keiki.Render.Markdown` closes the loop on a checked-in diagram document: it
rewrites a single marked block in place, preserving every byte outside it. The
marker convention is a matched pair of HTML comments,
`<!-- {namespace}: {id} begin -->` / `<!-- {namespace}: {id} end -->` — exactly
what `toMermaidAtlasWith` emits when `atlasWrapMarkers = Just ns` (keyed by each
section's `sectionId`).

```haskell
data MarkdownDiagramBlock = MarkdownDiagramBlock
  { blockNamespace :: Text   -- marker namespace, e.g. a service name
  , blockId        :: Text   -- marker id; the atlas sectionId
  , blockLanguage  :: Text   -- fenced-block tag, e.g. "mermaid"
  , blockContent   :: Text   -- already-rendered body (no fences)
  }

replaceMarkdownDiagramBlock :: MarkdownDiagramBlock -> Text -> Either MarkdownDiagramError Text
```

It returns `Left` with a precise `MarkdownDiagramError`
(`MissingBeginMarker` / `MissingEndMarker` / `DuplicateMarker`, each carrying the
expected marker text) rather than silently corrupting the document. This is how a
regeneration step refreshes one aggregate's diagram in a multi-aggregate page
without touching the surrounding prose. `beginMarker` / `endMarker :: Text -> Text -> Text`
produce the marker strings for a `(namespace, id)` pair. The module references no
keiki type — it works on any marked Markdown.


## 8. Linting rendered diagrams: `Keiki.Render.Validate`

`Keiki.Render.Validate` provides cheap, pure structural-heuristic checks over
rendered diagram / atlas **text**, mirroring the list-of-warnings house style of
`Keiki.Core.validateTransducer` (§8 of `user-guide.md`):

```haskell
validateMermaidDiagram :: MermaidValidationOptions -> Text -> [MermaidValidationWarning]
validateMermaidAtlas   :: MermaidValidationOptions -> Text -> [MermaidValidationWarning]

data MermaidValidationWarning
  = MissingStateDiagramHeader                                   -- no `stateDiagram-v2` header
  | EmptyDiagram                                                -- header but no transition/declaration/group
  | LabelTooLong          { warnLine :: Int, warnLength :: Int, warnLabel :: Text }
  | DuplicateStateId      { warnStateId :: Text }               -- a `state "…" as <id>` id declared twice
  | SuspiciousUnescapedChar { warnLine :: Int, warnChar :: Char, warnLabel :: Text }
```

`defaultMermaidValidationOptions` uses an 80-character label budget and the
denylist `{ '"', '<', '>', '|', '{', '}' }` (the literal `<br/>` keiki emits for
multiline labels is always exempt). These are **not** a Mermaid parser: an empty
result means "no problem detected", never "guaranteed valid Mermaid" — they exist
so a downstream unit test catches the common, cheap-to-detect mistakes before a
rendered document is committed. The `DuplicateStateId` check over text agrees with
the AST-level `duplicateStateIds` (§5) by keying off the same id token.


## 9. Pointers

- `src/Keiki/Render/Mermaid.hs` — `toMermaid`, `toMermaidWith`, `toMermaidWithLabels`,
  `toMermaidAtlas`, `toMermaidAtlasWith`, `MermaidOptions`, `MermaidStateLabels`,
  `duplicateStateIds`, and the atlas types.
- `src/Keiki/Render/Pretty.hs` — `prettyPred` / `prettyTerm` / `prettyUpdate` (§3).
- `src/Keiki/Render/Inspector.hs` — `renderEdgeInspector` / `EdgeInspectorOptions` (§6).
- `src/Keiki/Render/Markdown.hs` — `replaceMarkdownDiagramBlock` and the markers (§7).
- `src/Keiki/Render/Validate.hs` — `validateMermaidDiagram` / `validateMermaidAtlas` (§8).
- `docs/guide/deriving-lifecycle-transitions.md` — the bug-spotting pedagogy the
  guard-free default protects.
- `docs/guide/diagrams/` — generated per-aggregate diagram pages; atlas output
  pastes straight in.
