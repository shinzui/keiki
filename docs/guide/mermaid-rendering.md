# Mermaid rendering

Keiki's render surface lives under `src/Keiki/Render/`. The primary
`Keiki.Render.Mermaid.toMermaid` API turns a transducer into a Mermaid
`stateDiagram-v2` block whose edge labels expose executable business behavior:
the input command, emitted event constructors, complete register assignments,
and guard expression. GitHub, Notion, VS Code, and the repository's documentation
site render that text inline.

`toTopologyMermaid` is the deliberate compact alternative. It emits only
`<input command> / <output event>` and reproduces Keiki 0.7's single-transducer
bytes exactly. Choosing topology output means choosing not to show the conditions
and state changes that explain an edge.

Around that core are four sibling modules, all pure (no IO, no solver):

- **`Keiki.Render.Pretty`** — a domain-readable pretty-printer for `HsPred` /
  `Term` / `Update` (§3).
- **`Keiki.Render.Inspector`** — a full Markdown edge-detail renderer (§6).
- **`Keiki.Render.Markdown`** — regenerate a marked diagram block in place (§7).
- **`Keiki.Render.Validate`** — lint rendered diagram / atlas text (§8).

## 1. Readable behavior is the primary contract

`toMermaid` is equivalent to `toMermaidWith defaultMermaidOptions`. The default
policy renders complete updates and pretty guards on separate label lines, with
no truncation of business semantics. For example, a stateful counter edge
contains source text shaped like:

```text
StageVertex --> StageVertex : MsgB / MsgC<br/>u: regB := (regB + MsgB.payload)<br/>g: (MsgB && regB >= 0)
```

The actual Mermaid source uses backend-safe escaping described in §3; the
rendered label preserves the human-readable operators. Ordinary literal values
are present in guards and update right-hand sides. Output event fields are not:
`WireCtor` records constructor names but does not invent field names that the
executable transducer does not carry.

Use the topology path only when the diagram's purpose is shape rather than
behavior:

```haskell
toTopologyMermaid userReg

toMermaidCompositeWith topologyMermaidOptions composite
```

## 2. Options and every diagram shape

`MermaidOptions` has one authoritative mode for guards and one for updates:

```haskell
data MermaidOptions = MermaidOptions
  { guardMode             :: MermaidGuardMode
  , updateMode            :: MermaidUpdateMode
  , labelLayout           :: MermaidLabelLayout
  , maxInlineWrittenSlots :: Maybe Int
  , maxInlineGuardWidth   :: Maybe Int
  , outputLayout          :: MermaidOutputLayout
  }

data MermaidGuardMode
  = MermaidGuardHidden
  | MermaidGuardStructuralSummary
  | MermaidGuardPretty

data MermaidUpdateMode
  = MermaidUpdateHidden
  | MermaidUpdateWrittenSlots
  | MermaidUpdatePretty
```

`defaultMermaidOptions` selects `MermaidGuardPretty`,
`MermaidUpdatePretty`, `MermaidLabelMultiline`, and no truncation.
`topologyMermaidOptions` selects hidden guard/update modes, inline labels, and
the historical output layout. Written-slot mode retains the compact legacy
summary when assignments are intentionally too detailed:

```text
ConfirmAccount / AccountConfirmed [w: confirmedAt; g: PAnd PInCtor PEq]
```

Every public shape has an options-aware route. The no-options function delegates
with `defaultMermaidOptions`:

| Primary renderer | Options-aware renderer |
|---|---|
| `toMermaid` | `toMermaidWith` |
| `toMermaidComposite` | `toMermaidCompositeWith` |
| `toMermaidCompositeNested` | `toMermaidCompositeNestedWith` |
| `toMermaidCompose3` | `toMermaidCompose3With` |
| `toMermaidCompose3Nested` | `toMermaidCompose3NestedWith` |
| `toMermaidAlternativeWith` | `toMermaidAlternativeWithOptions` |
| `toMermaidFeedback1` | `toMermaidFeedback1With` |
| labeled states | `toMermaidWithLabels` already takes options |

`toMermaidAlternativeWithOptions` takes options first, then the existing left
and right arm names. Passing `topologyMermaidOptions` to any right-hand function
reproduces that shape's 0.7 golden.

## 3. Literals, disclosure, and backend-safe labels

`Keiki.Render.Pretty` is a pure pretty-printer for the syntax trees:

```haskell
prettyTerm   :: Term rs ci ifs r -> Text
prettyPred   :: HsPred rs ci      -> Text
prettyUpdate :: Update rs w ci    -> Text
```

`lit value` stores a normal `TLit` with a `Show` dictionary, so renderers derive
the displayed text from the executable value itself. `opaqueLit value` stores a
`TOpaqueLit` and renders `<lit>`. Both constructors evaluate, replay, compare,
and translate symbolically as the same exact constant. Display opacity never
means solver opacity.

`Show` is renderer-only evidence, not canonical serialization or a proof
witness. A partial or throwing `Show` may make rendering fail, but execution,
replay, validation, and proof paths do not force it. Values without a `Show`
instance remain modelable with `opaqueLit`.

Readable diagrams disclose ordinary literal text. Secrets, credentials,
personal data, or deliberately redacted constants must use `opaqueLit`; use a
topology renderer when the whole diagram should omit guards and updates.

Edge segments are escaped before Keiki joins them with renderer-owned `<br/>`.
The repository backend decodes XML entities before parsing and recognizes
`<br>`, `<br/>`, `<br />`, and literal `\\n` as layout, so entities alone are
not an isolation boundary. Keiki uses XML entities where one decode is safe,
full-width angle brackets and backslashes for parser-active spellings, and the
visible control pictures `␍`/`␊` for raw line endings. The known `<lit>` marker
is entity-encoded and renders visually as `<lit>`. The fixture at
`diagrams/semantic-label-escaping.mmd` is checked through the same
`beautiful-mermaid` backend as the documentation site.

## 4. Atlases of many diagrams

`toMermaidAtlas :: [(Text, Text)] -> Text` assembles heterogeneous,
already-rendered diagrams under Markdown headings and Mermaid fences. Each
caller chooses readable or topology policy before supplying its diagram:

```haskell
toMermaidAtlas
  [ ("User registration", toMermaid userReg)
  , ("Alert topology", toMermaidCompositeWith topologyMermaidOptions composite)
  ]
```

`toMermaidAtlasWith` adds typed `MermaidSection` values, an optional atlas title,
section-kind display, replacement markers, heading level, and fence language.
`defaultMermaidAtlasOptions` preserves the legacy atlas wrapper bytes; it does
not change the semantics policy of the already-rendered section diagrams.


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

Where `toMermaid` keeps each edge's behavior compact inside the diagram,
`Keiki.Render.Inspector` expands edge metadata and output-field terms into a
Markdown document grouped by source state:

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
fields are labelled by position only. Use this when review needs edge indices,
structural tags, or output term positions beyond the behavioral diagram.


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

Complete readable labels often exceed the historical 80-character style budget.
Set `maxLabelLength = Nothing` when length is not a project rule; keep
`checkSuspiciousChars = True`. Keiki's special-character regression does exactly
that and separately verifies the rendered SVG through the site backend. A
warning-free heuristic result is never a substitute for backend rendering.


## 9. Migrating from 0.7 to 0.8

The `Term` and Mermaid changes are intentionally breaking:

- Normal `lit value` now requires `Show` and appears in readable output. Use
  `opaqueLit value` for a type without `Show` or a value that must be redacted.
- `toMermaid` and every no-options shape renderer now show complete guards and
  updates. Replace `toMermaid t` with `toTopologyMermaid t` when the prior
  shape-only bytes are required.
- For composite, nested, alternative, three-way, feedback, or labeled diagrams,
  call the options-aware renderer with `topologyMermaidOptions` to preserve 0.7
  output.
- Replace `showWrittenSlots = True` with
  `updateMode = MermaidUpdateWrittenSlots`.
- Replace `showGuardSummary = True` with
  `guardMode = MermaidGuardStructuralSummary`. The legacy booleans were removed;
  modes are now the only authorities.
- Code that exhaustively matches `Term` must handle both `TLit` and
  `TOpaqueLit`. Structural transforms should preserve the constructor; a typed
  field-projection fold may lose display evidence and produce `TOpaqueLit` while
  retaining exact execution and symbolic meaning.

## 10. Pointers

- `src/Keiki/Render/Mermaid.hs` — readable and topology renderers, every
  options-aware shape, `MermaidOptions`, state labels, and atlas types.
- `src/Keiki/Render/Pretty.hs` — `prettyPred` / `prettyTerm` / `prettyUpdate` (§3).
- `src/Keiki/Render/Inspector.hs` — `renderEdgeInspector` / `EdgeInspectorOptions` (§6).
- `src/Keiki/Render/Markdown.hs` — `replaceMarkdownDiagramBlock` and the markers (§7).
- `src/Keiki/Render/Validate.hs` — `validateMermaidDiagram` / `validateMermaidAtlas` (§8).
- `docs/adr/0006-readable-business-semantics-are-the-primary-rendering-contract.md`
  — the durable decision and consequences.
- `docs/guide/diagrams/` — generated per-aggregate diagram pages; atlas output
  pastes straight in.
