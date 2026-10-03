---
type: Architecture Decision Record
title: Readable business semantics are the primary rendering contract
description: >-
  Make TLit carry Show evidence so primary Mermaid renderers show full guard and update
  semantics by default, while TOpaqueLit and topology mode remain the explicit routes to
  redact or omit them.
docId: ADR-6
status: Accepted
date: 2026-08-02
timestamp: 2026-10-03T03:39:02Z
generated:
  by: adopt-architecture-decisions/0.8.0
  at: 2026-08-04T16:35:24Z
---

# ADR-0006: Readable business semantics are the primary rendering contract

- **Plan(s):** `docs/plans/84-preserve-readable-business-semantics-in-keiki-transducers-and-diagrams.md`; `docs/plans/91-add-descriptive-scxml-state-chart-export-for-transducers.md`

## Context

A transition diagram that shows only source, target, command, and event
constructors proves topology but hides why an edge fires and how it changes
state. Keiki already owns those guard and update syntax trees, so hiding them in
the primary renderer makes reviewers reconstruct behavior from source or a
separate inspector dump.

Ordinary `Term` literals previously carried no `Show` evidence, forcing every
literal to render as `<lit>`. Adding display evidence must not change execution,
replay inversion, pure overlap analysis, symbolic translation, or the domain of
values Keiki can model. Rendering also crosses a parser boundary: the repository's
`beautiful-mermaid` backend decodes XML entities before recognizing break tags
and literal `\\n`, so naive entity escaping can turn data into layout.

Readable literals may expose sensitive values. The API therefore needs an
honest, explicit distinction between ordinary display and intentional redaction,
plus a whole-diagram topology policy.

## Decision

`TLit` carries `Show` evidence and `lit` requires `Show`. Renderers derive text
from the stored executable value; callers cannot attach an unrelated display
label. `TOpaqueLit` and `opaqueLit` retain a value without display evidence and
render it as `<lit>`.

The two literal constructors have identical executable and proof meaning. No
runtime, replay, validation, pure-analysis, composition, or symbolic path may
force `Show`. Structural rewrites preserve readable versus opaque evidence when
they possess it. A field-projection fold may produce `TOpaqueLit` when the
projection interface cannot supply `Show` for its result; this is presentation
loss, not symbolic opacity.

`toMermaid` and every no-options shape renderer use readable guards, complete
updates, multiline labels, and no semantic truncation. `toTopologyMermaid` and
`topologyMermaidOptions` explicitly select the compact Keiki 0.7 policy. Every
diagram shape has an options-aware route; guard and update modes are the sole
authorities.

Mermaid edge semantics are escaped before renderer-owned `<br/>` joins. Safe
punctuation uses XML entities; parser-active angle brackets and backslashes use
visible full-width forms; raw CR/LF use visible control pictures. The known
`<lit>` marker is entity-encoded and stays visually exact. Tests verify source
line and transition counts, heuristic warnings, recovered SVG text, and the
checked-in documentation backend.

The SCXML export (`Keiki.Render.SCXML`) applies the same contract at a
different boundary. It is descriptive, not executable: the document declares
`datamodel="null"` and never moves Haskell guards, updates, or outputs into
SCXML `cond`, `<assign>`, or `<send>`. An interpreter that loaded those elements
would run them as executable content, and update right-hand sides read the
edge-entry snapshot (ADR-4) rather than sequential assignments. Readable
behavior is the default. It is recorded in XML comments of the form
`<!--keiki-scxml-v1 {JSON}-->`, using the same `prettyPred`/`prettyUpdate`/
`prettyTerm` text, `<fn>`/`<lit>` markers, and literal disclosure policy as
Mermaid. The JSON writes every hyphen and every XML-forbidden or discouraged
character as a `\u` escape and is never entity-escaped, so parsing the XML and
then decoding the JSON recovers each string exactly. Structural mode
(`includeBehavior = False`) is the explicit redaction route: it omits guards,
assignments, and outputs and never forces a pretty-printer or `Show`. `event`
attributes are diagram labels. The exporter uses a constructor name only when
the guard has exactly one safe `PInCtor` and it is a top-level conjunct, and
otherwise uses a reserved `keiki_` synthetic label. Because transitions carry no
`cond`, sibling arrows that share a constructor label are all qualified as
`<Ctor>.e<j>`. A state-chart processor would otherwise treat them as
unconditional and shadow all but the first. Replay-only edges stay out of the default
forward graph. An independent standard-library XML/JSON checker validates the
generated documents.

## Consequences

- Primary diagrams expose the command, states, event constructors, full guard,
  and register right-hand expressions needed for behavioral review.
- Ordinary `lit` values are disclosed by readable rendering. Secrets,
  credentials, personal data, and intentionally redacted values must use
  `opaqueLit`; topology policy redacts all guard and update semantics.
- A partial, expensive, or stylized `Show` can affect rendering but cannot
  affect execution or proof results. `Show` text is not canonical serialization.
- Values without `Show` remain executable through `opaqueLit`.
- Exhaustive `Term` matches and `MermaidOptions` record updates require a PVP
  migration. Callers needing stable 0.7 diagram bytes must opt into topology.
- Full-width control punctuation is a visible sign that semantic input was
  neutralized at the Mermaid boundary, not silently interpreted as structure.
- SCXML exports interchange the chart's shape, not its behavior. Generic viewers
  may drop the metadata comments, so editor round-trips are not guaranteed, and
  executable or editor-specific SCXML would need its own decision and semantic
  tests.
