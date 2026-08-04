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
generated:
  by: adopt-architecture-decisions/0.8.0
  at: 2026-08-04T16:35:24Z
---

# ADR-0006: Readable business semantics are the primary rendering contract

- **Plan(s):** `docs/plans/84-preserve-readable-business-semantics-in-keiki-transducers-and-diagrams.md`

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
