---
type: Term
title: "chunk replay"
description: "Replay of a complete event chunk that must finish with no pending events from a multi-event edge."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-14
status: current
tags: [replay]
related: [TERM-13, TERM-15]
anchors:
  - kind: file
    resource: docs/guide/multi-event-commands.md
---

# chunk replay

Replay of a complete event chunk that must finish with no pending events from a multi-event edge.

A runtime preserving command boundaries can pass all events from one command to applyEventsEither. Ending after only RegistrationStarted when ConfirmationEmailSent is still expected produces a truncation failure.

See [the supporting source or guide](../../docs/guide/multi-event-commands.md).
