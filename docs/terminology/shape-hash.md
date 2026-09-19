---
type: Term
title: "shape hash"
description: "A codec-independent structural fingerprint of a register slot list or control-state datatype."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-30
status: current
tags: [codecs]
related: [TERM-33]
anchors:
  - kind: file
    resource: src/Keiki/Shape.hs
---

# shape hash

A codec-independent structural fingerprint of a register slot list or control-state datatype.

Changing a slot name or type can change the fingerprint. Changing only a JSON instance can leave it unchanged, so shape hashes cannot replace golden tests for persisted encoding compatibility.

See [the supporting source or guide](../../src/Keiki/Shape.hs).
