---
type: Term
title: "slot"
description: "A register location identified by a type-level name and its value type."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-5
status: current
tags: [core]
related: [TERM-4, TERM-22]
anchors:
  - kind: file
    resource: src/Keiki/Core.hs
---

# slot

A register location identified by a type-level name and its value type.

An email slot might hold Text and a count slot Int. Slot names must be distinct; sequential composition also requires the two register namespaces to be disjoint.

See [the supporting source or guide](../../src/Keiki/Core.hs).
