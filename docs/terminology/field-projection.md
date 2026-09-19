---
type: Term
title: "field projection"
description: "A nominally identified getter that exposes a field of a consumer-owned value to terms and symbolic reasoning."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-28
status: current
tags: [analysis]
related: [TERM-29, TERM-26]
anchors:
  - kind: file
    resource: src/Keiki/Core.hs
---

# field projection

A nominally identified getter that exposes a field of a consumer-owned value to terms and symbolic reasoning.

One coherent tag identifies one logical getter. Reusing that tag lets repeated reads share a symbolic variable; two distinct tags with the same display name do not establish shared identity.

See [the supporting source or guide](../../src/Keiki/Core.hs).
