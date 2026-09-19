---
type: Term
title: "trusted wire schema"
description: "Structural evidence derived through trusted constructor bindings for aligning event constructors and their payload fields."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-25
status: current
tags: [analysis]
related: [TERM-22, TERM-32]
anchors:
  - kind: file
    resource: test/Keiki/WireSchemaSpec.hs
---

# trusted wire schema

Structural evidence derived through trusted constructor bindings for aligning event constructors and their payload fields.

Generic and Template Haskell bindings can carry trusted schema evidence. A manually supplied constructor name is a diagnostic label, not proof of identity; closure-based bindings may have unavailable evidence. This schema is distinct from the JSON event version.

See [the supporting source or guide](../../test/Keiki/WireSchemaSpec.hs).
