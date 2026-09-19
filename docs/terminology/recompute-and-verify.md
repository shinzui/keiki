---
type: Term
title: "recompute-and-verify"
description: "Replay verification of a derived event field by evaluating its expression using recovered input and pre-transition registers."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-19
status: current
tags: [replay]
related: [TERM-16, TERM-18]
anchors:
  - kind: file
    resource: docs/guide/output-invertibility.md
---

# recompute-and-verify

Replay verification of a derived event field by evaluating its expression using recovered input and pre-transition registers.

A stored line total can be checked against recovered quantity times unit price. The derived field verifies the recovered command; it does not supply missing command data. Register-dependent expressions require the correct replay register state.

See [the supporting source or guide](../../docs/guide/output-invertibility.md).
