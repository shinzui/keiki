---
type: Term
title: "forward equivalence"
description: "Agreement of forward transitions and emitted outputs over every command sequence, comparing control states up to the documented state isomorphism."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-36
status: current
tags: [composition]
related: [TERM-13, TERM-17]
anchors:
  - kind: file
    resource: src/Keiki/Profunctor.hs
---

# forward equivalence

Agreement of forward transitions and emitted outputs over every command sequence, comparing control states up to the documented state isomorphism.

Profunctor mapping can preserve forward behavior while losing event inversion. The experimental categorical surface therefore distinguishes tested forward laws from replay equivalence; a mapped transducer is not automatically replay-safe.

See [the supporting source or guide](../../src/Keiki/Profunctor.hs).
