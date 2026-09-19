---
type: Term
title: "feedback1"
description: "A single-step two-copy cascade that routes one transducer copy's output through a policy transducer into a second copy."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-24
status: current
tags: [composition]
related: [TERM-22]
anchors:
  - kind: file
    resource: src/Keiki/Composition.hs
---

# feedback1

A single-step two-copy cascade that routes one transducer copy's output through a policy transducer into a second copy.

The policy converts the first copy's emitted event into a follow-up command for the second copy; the composite emits the second copy's output. The copies occupy distinct control-state dimensions and register segments, subject to the composition constraints; they do not share aggregate state. This combinator expresses one round of feedback; it is not an unbounded loop that repeatedly executes until a fixed point.

See [the supporting source or guide](../../src/Keiki/Composition.hs).
