---
type: Term
title: "replay-only edge"
description: "An edge excluded from forward decisions but available as a fallback for replaying historical events."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-20
status: current
tags: [replay]
related: [TERM-3, TERM-13]
anchors:
  - kind: file
    resource: src/Keiki/Core.hs
---

# replay-only edge

An edge excluded from forward decisions but available as a fallback for replaying historical events.

When a business guard is tightened, a replay-only edge can retain the retired input region for historical events. Replay tries live edges first and considers replay-only edges only when no live candidate matches.

See [the supporting source or guide](../../src/Keiki/Core.hs).
