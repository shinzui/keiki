---
type: Term
title: "control vertex"
description: "A named position in the finite control graph that determines which outgoing transitions are available."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-2
status: current
tags: [core]
related: [TERM-3, TERM-4]
anchors:
  - kind: file
    resource: src/Keiki/Core.hs
---

# control vertex

A named position in the finite control graph that determines which outgoing transitions are available.

Pending and Sent are control vertices. A vertex alone is not the complete execution state: the register values matter too.

See [the supporting source or guide](../../src/Keiki/Core.hs).
