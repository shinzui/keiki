---
type: Term
title: "symbolic analysis"
description: "Build-time reasoning about transducer predicates and outputs using symbolic values and a solver."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-26
status: current
tags: [analysis]
related: [TERM-6, TERM-27, TERM-28]
anchors:
  - kind: file
    resource: src/Keiki/Symbolic.hs
---

# symbolic analysis

Build-time reasoning about transducer predicates and outputs using symbolic values and a solver.

It can examine guard overlap or replay inversion without enumerating concrete command values. Normal forward stepping and replay evaluate concretely and do not invoke the solver for each event.

See [the supporting source or guide](../../src/Keiki/Symbolic.hs).
