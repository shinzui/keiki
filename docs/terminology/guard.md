---
type: Term
title: "guard"
description: "A predicate over the pre-transition registers and input that determines whether an edge is eligible."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-6
status: current
tags: [core]
related: [TERM-3, TERM-26]
anchors:
  - kind: file
    resource: src/Keiki/Core.hs
---

# guard

A predicate over the pre-transition registers and input that determines whether an edge is eligible.

A withdrawal guard can require the command amount to be no greater than the stored balance. Concrete stepping evaluates this predicate directly; symbolic analysis reasons about possible values separately.

See [the supporting source or guide](../../src/Keiki/Core.hs).
