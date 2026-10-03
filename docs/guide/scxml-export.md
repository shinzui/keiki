# SCXML state-chart export

`Keiki.Render.SCXML` exports a finite transducer as a
[State Chart XML (SCXML)](https://www.w3.org/TR/scxml/) document: one vertex per
control state, one event-labelled arrow per edge, and readable descriptions of the
guards, register assignments, and emitted events, all derived from the same
`SymTransducer` declaration that keiki executes.

**The export is descriptive, not executable.** The document declares
`datamodel="null"` and contains no `cond`, `<assign>`, `<send>`, or other
executable content. Loading it into an SCXML interpreter does **not** reproduce
keiki's command rejection, guard evaluation, register updates, event emission, or
replay. Use it to inspect a chart in state-chart tooling or to interchange its
shape; run behavior with keiki itself.

## 1. API

```haskell
import Data.ByteString qualified as BS
import Data.Text.Encoding (encodeUtf8)
import Keiki.Render.SCXML

main :: IO ()
main = case toSCXML emailDelivery of
  Left err -> fail (show err)
  Right xml -> BS.writeFile "email-delivery.scxml" (encodeUtf8 xml)
```

- `toSCXML :: (Eq s, Enum s, Bounded s, Show s) => SymTransducer (HsPred rs ci) rs s ci co -> Either ScxmlError Text`
  exports with `defaultScxmlOptions`.
- `toSCXMLWith :: ScxmlOptions -> …` takes explicit options:

  ```haskell
  data ScxmlOptions = ScxmlOptions
    { edgeView :: ScxmlEdgeView        -- ForwardEdges (default) | AllDeclaredEdges
    , includeBehavior :: Bool          -- True (default) | False for structure only
    }
  ```

The result is XML 1.0 text with an `encoding="UTF-8"` declaration, two-space
indentation, and a trailing newline. Write it as UTF-8 bytes, as above:
`Data.Text.IO.writeFile` uses the locale's encoding, which may not be UTF-8.
Export is pure and deterministic: the same declaration and options always yield
identical text.

The state type must have lawful, finite `Eq`, `Enum`, and `Bounded` instances.
States are enumerated with `[minBound .. maxBound]` and located with `(==)`. A
malformed enumeration is reported, never rendered as a partial document. The
checks run in this order:

| Error | Cause |
|---|---|
| `EmptyStateEnumeration` | `[minBound .. maxBound]` is empty. |
| `InitialStateNotEnumerated` | `initial` equals no enumerated state. |
| `TargetStateNotEnumerated {sourceStateId, edgeIndex}` | An edge target equals no enumerated state. This check covers replay-only edges that are not drawn. Edges are checked in enumeration and declaration order. |

## 2. The document subset

```xml
<?xml version="1.0" encoding="UTF-8"?>
<scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0" datamodel="null" initial="s0_EmailPending">
  <!--keiki-scxml-v1 {"kind":"document",…}-->
  <state id="s0_EmailPending">
    <!--keiki-scxml-v1 {"kind":"state",…}-->
    <transition event="SendEmail" target="s1_EmailSentVertex">
      <!--keiki-scxml-v1 {"kind":"edge",…}-->
    </transition>
  </state>
  <final id="s1_EmailSentVertex">
    <!--keiki-scxml-v1 {"kind":"state",…}-->
  </final>
</scxml>
```

The full generated document is
[`docs/examples/email-delivery.scxml`](../examples/email-delivery.scxml). The
export uses only these elements:

- **One flat element per enumerated state**, in enumeration order, including
  unreachable and isolated states. No nested states or `<parallel>` are
  reconstructed. A product state type still renders, but as a flat graph.
- **State IDs** take the form `s<i>_<name>`. `<i>` is the state's enumeration
  position. `<name>` is its `show` text with every character outside ASCII
  letters, digits, and underscore replaced by `_`. The prefix keeps IDs legal and
  distinct even when two states show identically or sanitize to the same text.
  IDs are deterministic for a fixed declaration but are not persistent identities:
  reordering the state type renumbers them. The exact `show` text is kept in the
  state record's `label`.
- **`<final>` versus `<state>`.** A keiki accepting state (`isFinal`) becomes
  `<final>` only when it has no drawn outgoing edges. An accepting state that has
  outgoing edges stays a `<state>` and is marked `"accepting":true`. SCXML
  `<final>` cannot carry transitions, and keiki's `isFinal` is an acceptance
  predicate, not a prohibition on further forward steps.
- **One `<transition>` per drawn edge**, in declaration order, including
  self-loops and edges that emit nothing. An edge that emits several events is
  still one arrow, and its record keeps the output order.
- **Every transition has an `event`.** In SCXML, omitting `event` would mean an
  automatically eligible eventless transition. The label is the edge's input
  constructor name when the guard contains exactly one `PInCtor` and that test
  is a top-level conjunct (reached from the root through `&&` only), so the
  edge can fire only for that constructor. Other conjuncts may freely use `||`
  and `!`, as in `ReplacePreferences && (flag differs || …)`. The name must
  also match `[A-Za-z_][A-Za-z0-9_]*` and not start with `keiki_`. Builder
  `onCmd` edges qualify. Every other edge gets the synthetic label
  `keiki_edge_s<i>_e<j>` (source position `i`, local edge index `j`). Examples
  include a disjunction over constructors, a negated constructor test, two
  constructor tests, or a wildcard guard.
- **No arrow shadows a sibling.** Transitions carry no `cond`, so an SCXML
  processor treats sibling transitions on the same event as unconditional and
  takes the first in document order, even when keiki's guards are mutually
  exclusive (for example `MarkBounced` split on `permanent == True` and
  `permanent == False`). When two or more drawn arrows leaving one state would
  share a constructor label, **every** arrow in that group is labelled
  `<Ctor>.e<j>`, for example `MarkBounced.e1` and `MarkBounced.e2`. SCXML
  matches events by dot-separated token prefix, so these qualified labels
  cannot match each other. Leaving any one of them bare would match them all.
  The guard in each edge record tells the arrows apart. **Event labels are
  diagram labels, not a command encoding.** The exporter does not prune guards
  it believes are false, and it does not claim that every drawn path is
  feasible.

## 3. Edge views

| View | Drawn arrows | Replay-only edges |
|---|---|---|
| `ForwardEdges` (default) | `Live` edges only | Recorded as edge comments directly inside the source state, with `"displayed":false` |
| `AllDeclaredEdges` | All edges | Drawn with the reserved label `keiki_replay_s<i>_e<j>`, even when an input constructor name is available |

Replay-only edges exist to interpret historical events. They are never taken by a
forward command, so the default view leaves them out of the forward graph. The
all-edges view draws them as historical inversion paths, and both the document
and edge records say so. Whether a state is `<final>` depends on the drawn edges
in the selected view. An accepting state whose only outgoing edges are
replay-only is therefore `<final>` in the forward view and `<state>` in the
all-edges view.

## 4. Metadata comments (`keiki-scxml-v1`)

Every comment the exporter writes has the form
`<!--keiki-scxml-v1 <JSON object>-->`. The object has a `kind` discriminator:

| Comment position | `kind` | Fields, in output order |
|---|---|---|
| First child of `<scxml>` | `document` | `purpose` (`"descriptive-only"`), `edgeView` (`"forward-edges"` or `"all-declared-edges"`), `includeBehavior`, `warning`, `replayEdges`, `edgeIndex`, `updateSemantics` (explanatory strings) |
| First child of each `<state>`/`<final>` | `state` | `id`, `index`, `label` (exact `show` text), `accepting` |
| Inside each `<transition>`, or directly in the source state for an omitted replay-only edge | `edge` | `source`, `target` (state IDs), `edgeIndex` (local declaration position, not a durable identifier), `mode` (`"Live"` or `"ReplayOnly"`), `displayed`, `event`, `eventSource` (`"input-constructor"`, `"qualified-input-constructor"`, or `"synthetic"`), then `note` for replay-only edges, then the behavior fields |

With `includeBehavior = True` (the default), an edge record also contains:

- `guard`: the full `prettyPred` text;
- `update`: the full `prettyUpdate` text;
- `assignments`: one `slot := term` string for each `USet`, in AST order;
- `updateReads`: `"edge-entry-snapshot"`. Every assignment's right-hand side
  reads the registers from before the edge (ADR-4), so assignments are not
  sequential `<assign>` operations;
- `outputs`: an ordered array of `{"constructor": …, "fields": [...]}`, one
  object per emitted event. Field expressions are pretty-printed terms, and an
  edge that emits nothing has an explicit `[]`.

Opaque values stay visibly opaque: an applied opaque function renders as
`<fn>(…)` and an `opaqueLit` value renders as `<lit>`. Ordinary `lit` values
render through their `Show` evidence, with the same disclosure policy as the
Mermaid renderer (ADR-6).

`includeBehavior = False` is an explicit structural view. It omits `guard`,
`update`, `assignments`, `updateReads`, and `outputs`, and it never calls the
pretty-printers or any literal's `Show` instance. Neither view reads
`initialRegs` or applies a function stored in a term.

Readers should look up fields by name. The fixed field order exists only to keep
the output byte-stable. The comment JSON is written so that it is also valid XML
comment content:

- every hyphen is written as `-`, so `--` and `-->` cannot occur inside a
  comment;
- control characters, DEL/C1 characters, surrogate code points, and
  noncharacters are written as JSON `\u` escapes;
- nothing is XML entity-escaped, because comment content is not entity-decoded.

Parsing the XML and then JSON-decoding the comment text therefore recovers every
string exactly, including multiline and non-ASCII text.

## 5. Viewers and tools

Any XML-aware SCXML viewer can show the states, the initial state, the final
states, and the event-labelled arrows. Viewers are free to ignore, hide, or drop
comments, so the descriptions may not survive an editor round-trip. No specific
graphical editor has been tested, and none is claimed to be compatible.
Importing SCXML into keiki is out of scope.

## 6. Verification

`nix develop -c just scxml-check` runs `scripts/check-scxml.sh`. The script
regenerates every fixture in `test/Keiki/Render/SCXMLFixtures.hs` from the
compiled test component and validates the results with `scripts/check-scxml.py`,
which uses only Python's standard XML and JSON parsers. It then byte-compares
`docs/examples/email-delivery.scxml` against the fresh export. Pass a directory
(`just scxml-check out/`) to keep the checked documents. To refresh the example
after an intentional change, run:

```bash
nix develop -c just scxml-check /tmp/scxml; cp /tmp/scxml/email-delivery.scxml docs/examples/
```

The checker validates this export contract only. Passing it is not a general
SCXML conformance result or a compatibility claim for third-party tools.
