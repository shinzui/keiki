---
type: Term
title: "sequential composition"
description: "Construction of a transducer that feeds the first component's outputs into the second component's inputs."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-22
status: current
tags: [composition]
related: [TERM-7, TERM-25]
anchors:
  - kind: file
    resource: src/Keiki/Composition.hs
---

# sequential composition

Construction of a transducer that feeds the first component's outputs into the second component's inputs.

For a multi-event output, the second component processes each intermediate event in order and its resulting outputs are concatenated. composeChecked checks the structural boundary; matching diagnostic names alone is insufficient evidence.

See [the supporting source or guide](../../src/Keiki/Composition.hs).
