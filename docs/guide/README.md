---
type: Navigation
title: "Keiki guides"
description: "Find authoring tutorials, modeling guidance, interface references, and documentation maintenance commands."
docId: DOC-1
tags: [documentation, navigation, authoring]
generated:
  by: process:codex
  at: "2026-10-03T03:26:47Z"
---

# Keiki guides

Start with the [user guide](user-guide.md) to author and run an aggregate, then
work through the [loan application tutorial](loan-application-tutorial.md) for a
workflow spanning several aggregates. The [foundations](../foundations/00-reading-guide.md)
introduce the underlying event-sourcing and automata vocabulary.

- Author models with [B-views](b-views.md), [multi-event commands](multi-event-commands.md),
  [composition](composition.md), and [profunctor adapters](profunctor.md).
- Choose modeling patterns for [collections](modeling-collections.md) and
  [derived lifecycle transitions](deriving-lifecycle-transitions.md), or
  [author the AST directly](ast-drop-down.md).
- Understand [output invertibility](output-invertibility.md) and
  [why Keiki uses SMT](why-smt.md), then [wire symbolic checks into CI](symbolic-ci.md).
- Look up [Mermaid rendering](mermaid-rendering.md), [SCXML export](scxml-export.md),
  and the diagram inventory in `diagrams/index.md`.
- Resolve [generic-lens and label conflicts](generic-lens-and-label-reads.md) and
  follow the [ADR conventions](adr-conventions.md) when documenting decisions.

The generated `index.md` lists every page by reader intent.

## Maintaining this bundle

This directory follows the shared
[user-documentation profile](mori://shinzui/okf-profiles/profiles/user-documentation),
pinned to v0.19.0 in [profile.dhall](profile.dhall), and declares OKF v0.2.
Pages use one primary reader intent: `Navigation`, `Tutorial`, `Guide`,
`Explanation`, `Reference`, or `Runbook`.

Each Markdown page needs `type`, `title`, `description`, a stable `docId`,
a list of `tags`, and `generated.by` / `generated.at`. Preserve the visible
heading and existing IDs when moving or reclassifying pages. New IDs are
allocated across this entire bundle, including diagram notes:

```bash
okf id next docs/guide DOC --profile docs/guide/profile.dhall
```

Stable concept URIs have the form
`mori://shinzui/keiki/okf/guides/concepts/DOC-N`. `index.md` and `log.md`
are reserved bundle files; Mermaid `.mmd` files remain diagram assets.

Record the actual content producer with an OKF actor such as `human:<id>` or
`process:<id>` and the last meaningful revision in UTC. Existing pages retain
their Git author as `human:nadeem` and their last content commit's author date;
the metadata migration does not restamp them or claim independent verification.

After editing content, update its generation provenance and record the change:

```bash
okf log add docs/guide --kind Update -m "Describe the documentation change."
okf index docs/guide --write --okf-version 0.2
just guides-validate
```

The validation target requires `okf` 0.9.0.0 or later and `dhall` on `PATH`,
matching the repository's other documentation checks. Use
`just documentation-validate` to check all profile-governed documentation.
The bundle's `log.md` records adoption and subsequent changes.
