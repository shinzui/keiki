---
type: Term
title: "snapshot update semantics"
description: "The rule that an edge evaluates its register assignments and output expressions against the same pre-transition registers and input."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-12
status: current
tags: [core]
related: [TERM-4, TERM-7, TERM-30]
anchors:
  - kind: file
    resource: docs/guide/multi-event-commands.md
---

# snapshot update semantics

The rule that an edge evaluates its register assignments and output expressions against the same pre-transition registers and input.

Writing recipient and then emitting a register read still reads the old recipient. Emit the command field when the event needs the new value. This use of snapshot is an evaluation rule, distinct from a persisted state snapshot.

See [the supporting source or guide](../../docs/guide/multi-event-commands.md).
