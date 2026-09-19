---
type: Term
title: "edge"
description: "A declared transition with a guard, register update, ordered output expressions, target vertex, and execution mode."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-3
status: current
tags: [core]
related: [TERM-2, TERM-6, TERM-7]
anchors:
  - kind: file
    resource: src/Keiki/Core.hs
---

# edge

A declared transition with a guard, register update, ordered output expressions, target vertex, and execution mode.

A SendEmail edge can test the command, store its recipient, emit an event, and target Sent. The edge declaration is distinct from one execution of that transition.

See [the supporting source or guide](../../src/Keiki/Core.hs).
