---
type: Term
title: "replay safety"
description: "The model properties checked to support reconstruction of forward state changes from emitted events."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-17
status: current
tags: [replay]
related: [TERM-11, TERM-18, TERM-13]
anchors:
  - kind: file
    resource: src/Keiki/Core.hs
---

# replay safety

The model properties checked to support reconstruction of forward state changes from emitted events.

Hidden inputs and state-changing epsilon edges are examples of defects reported by validation. Passing a static check is not a guarantee that every external log is complete or valid; runtime replay still returns structured failures.

See [the supporting source or guide](../../src/Keiki/Core.hs).
