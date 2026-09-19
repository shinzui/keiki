---
type: Term
title: "exact projection domain"
description: "A declaration of exactly the values a field projection can return, paired with reconstruction of an owner for each admitted value."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-29
status: current
tags: [analysis]
related: [TERM-28, TERM-27]
anchors:
  - kind: file
    resource: src/Keiki/Core.hs
---

# exact projection domain

A declaration of exactly the values a field projection can return, paired with reconstruction of an owner for each admitted value.

A finite domain can describe the allowed keys of a small enum wrapper. Both owner-to-key coverage and key-to-owner reconstruction must hold; omitting a real key can create a false unsatisfiability result.

See [the supporting source or guide](../../src/Keiki/Core.hs).
