---
type: Term
title: "output inversion"
description: "Recovery of a candidate input command from an observed event and the pre-transition register file."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-16
status: current
tags: [replay]
related: [TERM-18, TERM-19]
anchors:
  - kind: file
    resource: docs/guide/output-invertibility.md
---

# output inversion

Recovery of a candidate input command from an observed event and the pre-transition register file.

Copies of command fields supply recoverable input data. Derived payload fields can be recomputed and checked once the input is recovered; arbitrary Haskell functions are not inverted. Recovery is partial and does not by itself establish an unambiguous replay step.

See [the supporting source or guide](../../docs/guide/output-invertibility.md).
