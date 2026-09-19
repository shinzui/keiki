---
type: Term
title: "alternative"
description: "Composition that dispatches disjoint input alternatives to separate transducer components."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-35
status: current
tags: [composition]
related: [TERM-22]
anchors:
  - kind: file
    resource: src/Keiki/Composition.hs
---

# alternative

Composition that dispatches disjoint input alternatives to separate transducer components.

An Either input selects the appropriate component while the composite retains both component states. This is input routing rather than sequentially feeding one component's emitted events into another.

See [the supporting source or guide](../../src/Keiki/Composition.hs).
