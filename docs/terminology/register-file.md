---
type: Term
title: "register file"
description: "The typed heterogeneous collection of named values retained across transitions."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-4
status: current
tags: [core]
related: [TERM-5, TERM-21]
anchors:
  - kind: file
    resource: src/Keiki/Core.hs
---

# register file

The typed heterogeneous collection of named values retained across transitions.

The register file contains all declared slots, even when only some are meaningful at the current vertex. A recipient slot can survive several commands; a B-view exposes only the slots designated live at a particular vertex.

See [the supporting source or guide](../../src/Keiki/Core.hs).
