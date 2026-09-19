---
type: Term
title: "acceptor"
description: "A one-alphabet state machine derived to recognize accepted input or output sequences."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-23
status: current
tags: [composition]
related: [TERM-13, TERM-15]
anchors:
  - kind: file
    resource: src/Keiki/Acceptor.hs
---

# acceptor

A one-alphabet state machine derived to recognize accepted input or output sequences.

The input acceptor follows commands; the output acceptor follows events and tracks in-flight replay. Acceptance requires successful traversal and a final state, not merely that the sequence prefix can be processed.

See [the supporting source or guide](../../src/Keiki/Acceptor.hs).
