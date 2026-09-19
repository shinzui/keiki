---
type: Term
title: "epsilon edge"
description: "An edge with an empty output word."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-11
status: current
tags: [core]
related: [TERM-7, TERM-17]
anchors:
  - kind: file
    resource: docs/guide/multi-event-commands.md
---

# epsilon edge

An edge with an empty output word.

Here epsilon describes the output: no event is emitted. It should not be read as a promise of automatic input-free execution. A state-changing epsilon edge leaves no event-log evidence of its change and is flagged by replay-safety validation.

See [the supporting source or guide](../../docs/guide/multi-event-commands.md).
