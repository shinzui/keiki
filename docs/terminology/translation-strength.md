---
type: Term
title: "translation strength"
description: "The reported distinction between an exact symbolic translation and a conservative approximation."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-27
status: current
tags: [analysis]
related: [TERM-26, TERM-29]
anchors:
  - kind: file
    resource: src/Keiki/Symbolic.hs
---

# translation strength

The reported distinction between an exact symbolic translation and a conservative approximation.

An unsupported expression can force approximation. Exact translations support stronger conclusions; a conservative result must retain its limitations rather than be presented as a concrete counterexample or complete proof.

See [the supporting source or guide](../../src/Keiki/Symbolic.hs).
