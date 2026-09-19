---
type: Term
title: "replay"
description: "Reconstruction of model state by consuming emitted events through the transducer declaration."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-13
status: current
tags: [replay]
related: [TERM-14, TERM-15, TERM-16]
anchors:
  - kind: file
    resource: src/Keiki/Core.hs
---

# replay

Reconstruction of model state by consuming emitted events through the transducer declaration.

Replay recovers candidate commands from event payloads, checks applicable edges, and advances state. It can fail for missing or ambiguous inversions, mismatched expected events, or truncated chunks. It is not command re-execution by an external effects runtime.

See [the supporting source or guide](../../src/Keiki/Core.hs).
