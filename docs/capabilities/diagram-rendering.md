---
title: "Readable Mermaid, Markdown, and SCXML rendering"
type: Capability
description: "Render a transducer as a behaviour-readable Mermaid diagram, Markdown edge inventory, pretty-printed predicate, or descriptive SCXML state chart directly from its declaration."
generated:
  by: adopt-capabilities/0.9.2
  at: "2026-08-08T00:00:00Z"
capabilityId: CAP-9
provider: mori://shinzui/keiki
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - keiki
interface:
  - Keiki.Render.Mermaid
  - Keiki.Render.Markdown
  - Keiki.Render.Inspector
  - Keiki.Render.Pretty
  - Keiki.Render.SCXML
  - Keiki.Render.Validate
requires:
  - CAP-1
evidence:
  - kind: test
    resource: test/Keiki/Render/MermaidSpec.hs
    proves: Single, composite, alternative, feedback, and multi-event diagrams render with readable guards and stable state IDs.
  - kind: test
    resource: test/Keiki/Render/InspectorSpec.hs
    proves: The Markdown edge inventory lists source/target, command, event, guard, and written slots deterministically.
  - kind: test
    resource: test/Keiki/Render/PrettySpec.hs
    proves: Predicates, terms, and updates pretty-print in domain-readable form while marking opaque and redacted values honestly.
  - kind: test
    resource: test/Keiki/Render/SCXMLSpec.hs
    proves: SCXML export assigns collision-free state IDs, chooses final elements and event labels conservatively, keeps replay-only edges out of the forward view, never forces initial registers or structural-mode literals, and rejects malformed enumerations in a fixed order.
  - kind: test
    resource: scripts/check-scxml.py
    proves: Freshly generated SCXML fixtures parse with Python's standard XML parser, every reference resolves, decoded metadata comments match each fixture's expected graph and descriptions (including hostile text), and the documented example matches fresh output.
---

# Readable Mermaid, Markdown, and SCXML rendering

A transducer declaration is also its own documentation source. keiki renders it
to Mermaid diagrams and Markdown inventories derived from the same edge AST, so
the picture cannot drift from the behaviour. It reads the core declaration in
[CAP-1](typed-transducer-core.md).

## What you adopt

- **`Keiki.Render.Mermaid`**: `toMermaid` (readable-by-default since 0.8.0.0 —
  full guards, complete register assignments, multiline labels, stable state IDs)
  and `toTopologyMermaid` / `topologyMermaidOptions` for compact shape-only
  output. Covers single transducers, sequential composites, alternatives,
  feedback cascades, nested diagrams, and multi-diagram atlases.
- **`Keiki.Render.Inspector`**: deterministic Markdown edge inventories.
- **`Keiki.Render.Markdown`**: marked-block replacement for embedding diagrams in
  docs.
- **`Keiki.Render.Pretty`**: predicate / term / update pretty-printing that marks
  opaque functions and (via `opaqueLit` / `TOpaqueLit`, since 0.8.0.0) redacted
  literals honestly.
- **`Keiki.Render.Validate`**: pure heuristic validation of generated diagrams
  and atlases.
- **`Keiki.Render.SCXML`**: `toSCXML` / `toSCXMLWith` export a flat,
  **descriptive** SCXML state chart (states, initial, finals, event-labelled
  transitions), with guards, assignments, and outputs kept as
  `keiki-scxml-v1` JSON comments. The default view draws only forward (`Live`)
  edges; `includeBehavior = False` is the structural view. See
  [`docs/guide/scxml-export.md`](../guide/scxml-export.md).

## Shortest real usage

```haskell
toMermaid emailDelivery :: Text          -- full behaviour
toTopologyMermaid emailDelivery :: Text  -- shape only
toSCXML emailDelivery :: Either ScxmlError Text  -- descriptive state chart
```

## Limits

- **`since` is established only for the Mermaid renderer.** `Keiki.Render.Mermaid`
  is in the 0.1.0.0 release, and readable-by-default plus `opaqueLit` landed in
  0.8.0.0. The introduction release of the `Markdown`, `Inspector`, `Pretty`, and
  `Validate` companion modules is **not recorded in `CHANGELOG.md`**; I could not
  establish it from release history and did not infer it. Treat their `since` as
  no earlier than the Mermaid renderer.
- **`Keiki.Render.Validate` is heuristic**, not a proof that a diagram is
  faithful.
- **SCXML export is descriptive, not executable.** An SCXML interpreter loading
  the document does not reproduce guards, register updates, event emission,
  command rejection, or replay; `event` attributes are diagram labels, and
  viewers may drop the metadata comments. No graphical editor has been tested,
  and SCXML import is out of scope. `Keiki.Render.SCXML` is unreleased, so no
  `since` version is recorded for it.
- `lit` requires `Show` (breaking, 0.8.0.0); values without `Show`, secrets, and
  deliberately redacted values must use `opaqueLit`, which renders as `<lit>`.
