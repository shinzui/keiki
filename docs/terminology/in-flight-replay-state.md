---
type: Term
title: "in-flight replay state"
description: "A streaming replay state that remembers a target vertex and the remaining expected events of a partially consumed output word."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-15
status: current
tags: [replay]
related: [TERM-10, TERM-13, TERM-14]
anchors:
  - kind: file
    resource: src/Keiki/Core.hs
---

# in-flight replay state

A streaming replay state that remembers a target vertex and the remaining expected events of a partially consumed output word.

After the first event of a two-event edge, InFlight retains the expected second event. Settled means that queue is empty. This state can cross page boundaries when replayEvents processes an event log incrementally.

See [the supporting source or guide](../../src/Keiki/Core.hs).
