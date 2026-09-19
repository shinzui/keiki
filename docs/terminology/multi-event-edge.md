---
type: Term
title: "multi-event edge"
description: "An edge whose output word contains two or more events."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-10
status: current
tags: [core]
related: [TERM-7, TERM-15]
anchors:
  - kind: file
    resource: docs/guide/multi-event-commands.md
---

# multi-event edge

An edge whose output word contains two or more events.

RegistrationStarted followed by ConfirmationEmailSent can come from one transition, with one register update and no synthetic intermediate control vertex. Streaming replay still needs to track the remaining expected events.

See [the supporting source or guide](../../docs/guide/multi-event-commands.md).
