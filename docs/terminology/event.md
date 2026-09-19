---
type: Term
title: "event"
description: "An output value emitted by a transition and consumable as evidence during replay."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-9
status: current
tags: [core]
related: [TERM-8, TERM-7, TERM-13]
anchors:
  - kind: file
    resource: docs/guide/user-guide.md
---

# event

An output value emitted by a transition and consumable as evidence during replay.

EmailSent can carry the recipient copied from SendEmail. Keiki returns events as values; emitting one does not itself send email or commit to an event store.

See [the supporting source or guide](../../docs/guide/user-guide.md).
